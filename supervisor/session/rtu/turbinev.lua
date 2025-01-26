local log          = require("scada-common.log")
local mqueue       = require("scada-common.mqueue")
local types        = require("scada-common.types")
local util         = require("scada-common.util")

local qtypes       = require("supervisor.session.rtu.qtypes")
local unit_session = require("supervisor.session.rtu.unit_session")

local turbinev = {}

local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local DUMPING_MODE = types.DUMPING_MODE
local MODBUS_FCODE = types.MODBUS_FCODE

local TBV_RTU_S_CMDS = qtypes.TBV_RTU_S_CMDS
local TBV_RTU_S_DATA = qtypes.TBV_RTU_S_DATA

local TXN_TYPES = {
    FORMED = 1,
    BUILD = 2,
    STATE = 3,
    TANKS = 4,
    INC_DUMP = 5,
    DEC_DUMP = 6,
    SET_DUMP = 7
}

local TXN_TAGS = {
    "turbinev.formed",
    "turbinev.build",
    "turbinev.state",
    "turbinev.tanks",
    "turbinev.inc_dump",
    "turbinev.dec_dump",
    "turbinev.set_dump"
}

local PERIODICS = {
    FORMED = 2000,
    BUILD = 1000,
    STATE = 500,
    TANKS = 1000
}

local WRITE_BUSY_WAIT = 1000

-- create a new turbinev rtu session runner
---@nodiscard
---@param session_id integer RTU gateway session ID
---@param unit_id integer RTU ID
---@param advert rtu_advertisement RTU advertisement table
---@param out_queue mqueue RTU message out queue
function turbinev.new(session_id, unit_id, advert, out_queue)
    -- checks
    if advert.type ~= RTU_UNIT_TYPE.TURBINE_VALVE then
        log.error("attempt to instantiate turbinev RTU for type " .. types.rtu_type_to_string(advert.type))
        return nil
    elseif not util.is_int(advert.index) then
        log.error("attempt to instantiate turbinev RTU without index")
        return nil
    end

    local log_tag = util.c("session.rtu(", session_id, ").turbinev(", advert.index, ")[@", unit_id, "]: ")

    local self = {
        session = unit_session.new(session_id, unit_id, advert, out_queue, log_tag, TXN_TAGS),
        has_build = false,
        mode_cmd = nil, ---@type dumping_mode|nil
        resend_mode = false,
        periodics = {
            next_formed_req = 0,
            next_build_req = 0,
            next_state_req = 0,
            next_tanks_req = 0
        },
        ---@class turbinev_session_db
        db = {
            formed = false,
            build = {
                last_update = 0,
                length = 0,
                width = 0,
                height = 0,
                min_pos = types.new_zero_coordinate(),
                max_pos = types.new_zero_coordinate(),
                blades = 0,
                coils = 0,
                vents = 0,
                dispersers = 0,
                condensers = 0,
                steam_cap = 0,
                max_energy = 0,
                max_flow_rate = 0,
                max_production = 0,
                max_water_output = 0
            },
            state = {
                last_update = 0,
                flow_rate = 0,
                prod_rate = 0,
                steam_input_rate = 0,
                dumping_mode = DUMPING_MODE.IDLE ---@type dumping_mode
            },
            tanks = {
                last_update = 0,
                steam = types.new_empty_gas(),
                steam_need = 0,
                steam_fill = 0.0,
                energy = 0,
                energy_need = 0,
                energy_fill = 0.0
            }
        }
    }

    ---@class turbinev_session:unit_session
    local public = self.session.get()

    -- PRIVATE FUNCTIONS --

    -- increment the dumping mode
    local function _inc_dump_mode()
        -- set mode command
        if self.mode_cmd == "IDLE" then self.mode_cmd = "DUMPING_EXCESS"
        elseif self.mode_cmd == "DUMPING_EXCESS" then self.mode_cmd = "DUMPING"
        elseif self.mode_cmd == "DUMPING" then self.mode_cmd = "IDLE"
        end

        -- write coil 1 with unused value 0
        if self.session.send_request(TXN_TYPES.INC_DUMP, MODBUS_FCODE.WRITE_SINGLE_COIL, { 1, 0 }, WRITE_BUSY_WAIT) == false then
            self.resend_mode = true
        end
    end

    -- decrement the dumping mode
    local function _dec_dump_mode()
        -- set mode command
        if self.mode_cmd == "IDLE" then self.mode_cmd = "DUMPING"
        elseif self.mode_cmd == "DUMPING_EXCESS" then self.mode_cmd = "IDLE"
        elseif self.mode_cmd == "DUMPING" then self.mode_cmd = "DUMPING_EXCESS"
        end

        -- write coil 2 with unused value 0
        if self.session.send_request(TXN_TYPES.DEC_DUMP, MODBUS_FCODE.WRITE_SINGLE_COIL, { 2, 0 }, WRITE_BUSY_WAIT) == false then
            self.resend_mode = true
        end
    end

    -- set the dumping mode
    ---@param mode dumping_mode
    local function _set_dump_mode(mode)
        self.mode_cmd = mode

        -- write holding register 1
        if self.session.send_request(TXN_TYPES.SET_DUMP, MODBUS_FCODE.WRITE_SINGLE_HOLD_REG, { 1, mode }, WRITE_BUSY_WAIT) == false then
            self.resend_mode = true
        end
    end

    -- query if the multiblock is formed
    ---@param time_now integer
    local function _request_formed(time_now)
        -- read discrete input 1 (start = 1, count = 1)
        if self.session.send_request(TXN_TYPES.FORMED, MODBUS_FCODE.READ_DISCRETE_INPUTS, { 1, 1 }) ~= false then
            self.periodics.next_formed_req = time_now + PERIODICS.FORMED
        end
    end

    -- query the build of the device
    ---@param time_now integer
    local function _request_build(time_now)
        -- read input registers 1 through 15 (start = 1, count = 15)
        if self.session.send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 15 }) ~= false then
            self.periodics.next_build_req = time_now + PERIODICS.BUILD
        end
    end

    -- query the state of the device
    ---@param time_now integer
    local function _request_state(time_now)
        -- read input registers 16 through 19 (start = 16, count = 4)
        if self.session.send_request(TXN_TYPES.STATE, MODBUS_FCODE.READ_INPUT_REGS, { 16, 4 }) ~= false then
            self.periodics.next_state_req = time_now + PERIODICS.STATE
        end
    end

    -- query the tanks of the device
    ---@param time_now integer
    local function _request_tanks(time_now)
        -- read input registers 20 through 25 (start = 20, count = 6)
        if self.session.send_request(TXN_TYPES.TANKS, MODBUS_FCODE.READ_INPUT_REGS, { 20, 6 }) ~= false then
            self.periodics.next_tanks_req = time_now + PERIODICS.TANKS
        end
    end

    -- PUBLIC FUNCTIONS --

    -- handle a packet
    ---@param m_pkt modbus_frame
    function public.handle_packet(m_pkt)
        local txn_type = self.session.try_resolve(m_pkt)
        if txn_type == false then
            -- nothing to do
        elseif txn_type == TXN_TYPES.FORMED then
            -- formed response
            -- load in data if correct length
            if m_pkt.length == 1 then
                self.db.formed = m_pkt.data[1]

                if not self.db.formed then self.has_build = false end
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.BUILD then
            -- build response
            if m_pkt.length == 15 then
                self.db.build.last_update      = util.time_ms()
                self.db.build.length           = m_pkt.data[1]
                self.db.build.width            = m_pkt.data[2]
                self.db.build.height           = m_pkt.data[3]
                self.db.build.min_pos          = m_pkt.data[4]
                self.db.build.max_pos          = m_pkt.data[5]
                self.db.build.blades           = m_pkt.data[6]
                self.db.build.coils            = m_pkt.data[7]
                self.db.build.vents            = m_pkt.data[8]
                self.db.build.dispersers       = m_pkt.data[9]
                self.db.build.condensers       = m_pkt.data[10]
                self.db.build.steam_cap        = m_pkt.data[11]
                self.db.build.max_energy       = m_pkt.data[12]
                self.db.build.max_flow_rate    = m_pkt.data[13]
                self.db.build.max_production   = m_pkt.data[14]
                self.db.build.max_water_output = m_pkt.data[15]
                self.has_build = true

                out_queue.push_data(unit_session.RTU_US_DATA.BUILD_CHANGED, { unit = advert.reactor, type = advert.type })
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.STATE then
            -- state response
            if m_pkt.length == 4 then
                self.db.state.last_update      = util.time_ms()
                self.db.state.flow_rate        = m_pkt.data[1]
                self.db.state.prod_rate        = m_pkt.data[2]
                self.db.state.steam_input_rate = m_pkt.data[3]
                self.db.state.dumping_mode     = m_pkt.data[4]

                if self.mode_cmd == nil then
                    self.mode_cmd = self.db.state.dumping_mode
                end
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.TANKS then
            -- tanks response
            if m_pkt.length == 6 then
                self.db.tanks.last_update = util.time_ms()
                self.db.tanks.steam       = m_pkt.data[1]
                self.db.tanks.steam_need  = m_pkt.data[2]
                self.db.tanks.steam_fill  = m_pkt.data[3]
                self.db.tanks.energy      = m_pkt.data[4]
                self.db.tanks.energy_need = m_pkt.data[5]
                self.db.tanks.energy_fill = m_pkt.data[6]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.INC_DUMP or txn_type == TXN_TYPES.DEC_DUMP or txn_type == TXN_TYPES.SET_DUMP then
            -- successful acknowledgement
        elseif txn_type == nil then
            log.error(log_tag .. "unknown transaction reply")
        else
            log.error(log_tag .. "unknown transaction type " .. txn_type)
        end
    end

    -- update this runner
    ---@param time_now integer milliseconds
    function public.update(time_now)
        -- check command queue
        while self.session.in_q.ready() do
            -- get a new message to process
            local msg = self.session.in_q.pop()

            if msg ~= nil then
                if msg.qtype == mqueue.TYPE.COMMAND then
                    -- instruction
                    local cmd = msg.message

                    if cmd == TBV_RTU_S_CMDS.INC_DUMP_MODE then
                        _inc_dump_mode()
                    elseif cmd == TBV_RTU_S_CMDS.DEC_DUMP_MODE then
                        _dec_dump_mode()
                    else
                        log.debug(util.c(log_tag, "unrecognized in-queue command ", cmd))
                    end
                elseif msg.qtype == mqueue.TYPE.DATA then
                    -- instruction with body
                    local cmd = msg.message ---@type queue_data
                    if cmd.key == TBV_RTU_S_DATA.SET_DUMP_MODE then
                        if cmd.val == types.DUMPING_MODE.IDLE or
                           cmd.val == types.DUMPING_MODE.DUMPING_EXCESS or
                           cmd.val == types.DUMPING_MODE.DUMPING then
                            _set_dump_mode(cmd.val)
                        else
                            log.debug(util.c(log_tag, "unrecognized dumping mode \"", cmd.val, "\""))
                        end
                    else
                        log.debug(util.c(log_tag, "unrecognized in-queue data ", cmd.key))
                    end
                end
            end

            -- max 100ms spent processing queue
            if util.time() - time_now > 100 then
                log.warning(log_tag .. "exceeded 100ms queue process limit")
                break
            end
        end

        -- try to resend mode if needed
        if self.resend_mode then
            self.resend_mode = false
            _set_dump_mode(self.mode_cmd)
        end

        time_now = util.time()

        -- handle periodics

        if self.periodics.next_formed_req <= time_now then _request_formed(time_now) end

        if self.db.formed then
            if not self.has_build and self.periodics.next_build_req <= time_now then _request_build(time_now) end
            if self.periodics.next_state_req <= time_now then _request_state(time_now) end
            if self.periodics.next_tanks_req <= time_now then _request_tanks(time_now) end
        end

        self.session.post_update()
    end

    -- invalidate build cache
    function public.invalidate_cache()
        self.periodics.next_formed_req = 0
        self.periodics.next_build_req = 0
        self.has_build = false
    end

    -- get the unit session database
    ---@nodiscard
    function public.get_db() return self.db end

    return public
end

return turbinev
