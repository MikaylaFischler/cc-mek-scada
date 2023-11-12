local log          = require("scada-common.log")
local mqueue       = require("scada-common.mqueue")
local types        = require("scada-common.types")
local util         = require("scada-common.util")

local qtypes       = require("supervisor.session.rtu.qtypes")
local unit_session = require("supervisor.session.rtu.unit_session")

local dynamicv = {}

local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local CONTAINER_MODE = types.CONTAINER_MODE
local MODBUS_FCODE = types.MODBUS_FCODE

local DTV_RTU_S_CMDS = qtypes.DTV_RTU_S_CMDS
local DTV_RTU_S_DATA = qtypes.DTV_RTU_S_DATA

local TXN_TYPES = {
    FORMED = 1,
    BUILD = 2,
    STATE = 3,
    TANKS = 4,
    INC_CONT = 5,
    DEC_CONT = 6,
    SET_CONT = 7
}

local TXN_TAGS = {
    "dynamicv.formed",
    "dynamicv.build",
    "dynamicv.state",
    "dynamicv.tanks",
    "dynamicv.inc_cont_mode",
    "dynamicv.dec_cont_mode",
    "dynamicv.set_cont_mode"
}

local PERIODICS = {
    FORMED = 2000,
    BUILD = 1000,
    STATE = 1000,
    TANKS = 500
}

-- create a new dynamicv rtu session runner
---@nodiscard
---@param session_id integer RTU session ID
---@param unit_id integer RTU unit ID
---@param advert rtu_advertisement RTU advertisement table
---@param out_queue mqueue RTU unit message out queue
function dynamicv.new(session_id, unit_id, advert, out_queue)
    -- checks
    if advert.type ~= RTU_UNIT_TYPE.DYNAMIC_VALVE then
        log.error("attempt to instantiate dynamicv RTU for type " .. types.rtu_type_to_string(advert.type))
        return nil
    elseif not util.is_int(advert.index) then
        log.error("attempt to instantiate dynamicv RTU without index")
        return nil
    end

    local log_tag = util.c("session.rtu(", session_id, ").dynamicv(", advert.index, ")[@", unit_id, "]: ")

    local self = {
        session = unit_session.new(session_id, unit_id, advert, out_queue, log_tag, TXN_TAGS),
        has_build = false,
        periodics = {
            next_formed_req = 0,
            next_build_req = 0,
            next_state_req = 0,
            next_tanks_req = 0
        },
        ---@class dynamicv_session_db
        db = {
            formed = false,
            build = {
                last_update = 0,
                length = 0,
                width = 0,
                height = 0,
                min_pos = types.new_zero_coordinate(),
                max_pos = types.new_zero_coordinate(),
                tank_capacity = 0,
                chem_tank_capacity = 0
            },
            state = {
                last_update = 0,
                container_mode = CONTAINER_MODE.BOTH    ---@type container_mode
            },
            tanks = {
                last_update = 0,
                stored = types.new_empty_gas(),
                fill = 0
            }
        }
    }

    local public = self.session.get()

    -- PRIVATE FUNCTIONS --

    -- increment the container mode
    local function _inc_cont_mode()
        -- write coil 1 with unused value 0
        self.session.send_request(TXN_TYPES.INC_CONT, MODBUS_FCODE.WRITE_SINGLE_COIL, { 1, 0 })
    end

    -- decrement the container mode
    local function _dec_cont_mode()
        -- write coil 2 with unused value 0
        self.session.send_request(TXN_TYPES.DEC_CONT, MODBUS_FCODE.WRITE_SINGLE_COIL, { 2, 0 })
    end

    -- set the container mode
    ---@param mode container_mode
    local function _set_cont_mode(mode)
        -- write holding register 1
        self.session.send_request(TXN_TYPES.SET_CONT, MODBUS_FCODE.WRITE_SINGLE_HOLD_REG, { 1, mode })
    end

    -- query if the multiblock is formed
    local function _request_formed()
        -- read discrete input 1 (start = 1, count = 1)
        self.session.send_request(TXN_TYPES.FORMED, MODBUS_FCODE.READ_DISCRETE_INPUTS, { 1, 1 })
    end

    -- query the build of the device
    local function _request_build()
        -- read input registers 1 through 7 (start = 1, count = 7)
        self.session.send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 7 })
    end

    -- query the state of the device
    local function _request_state()
        -- read holding register 1 (start = 1, count = 1)
        self.session.send_request(TXN_TYPES.STATE, MODBUS_FCODE.READ_MUL_HOLD_REGS, { 1, 1 })
    end

    -- query the tanks of the device
    local function _request_tanks()
        -- read input registers 8 through 9 (start = 8, count = 2)
        self.session.send_request(TXN_TYPES.TANKS, MODBUS_FCODE.READ_INPUT_REGS, { 8, 2 })
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
            if m_pkt.length == 7 then
                self.db.build.last_update        = util.time_ms()
                self.db.build.length             = m_pkt.data[1]
                self.db.build.width              = m_pkt.data[2]
                self.db.build.height             = m_pkt.data[3]
                self.db.build.min_pos            = m_pkt.data[4]
                self.db.build.max_pos            = m_pkt.data[5]
                self.db.build.tank_capacity      = m_pkt.data[6]
                self.db.build.chem_tank_capacity = m_pkt.data[7]
                self.has_build = true

                out_queue.push_data(unit_session.RTU_US_DATA.BUILD_CHANGED, { unit = advert.reactor, type = advert.type })
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.STATE then
            -- state response
            if m_pkt.length == 1 then
                self.db.state.last_update    = util.time_ms()
                self.db.state.container_mode = m_pkt.data[1]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.TANKS then
            -- tanks response
            if m_pkt.length == 2 then
                self.db.tanks.last_update = util.time_ms()
                self.db.tanks.stored      = m_pkt.data[1]
                self.db.tanks.fill        = m_pkt.data[2]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.INC_CONT or txn_type == TXN_TYPES.DEC_CONT or txn_type == TXN_TYPES.SET_CONT then
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

                    if cmd == DTV_RTU_S_CMDS.INC_CONT_MODE then
                        _inc_cont_mode()
                    elseif cmd == DTV_RTU_S_CMDS.DEC_CONT_MODE then
                        _dec_cont_mode()
                    else
                        log.debug(util.c(log_tag, "unrecognized in-queue command ", cmd))
                    end
                elseif msg.qtype == mqueue.TYPE.DATA then
                    -- instruction with body
                    local cmd = msg.message     ---@type queue_data
                    if cmd.key == DTV_RTU_S_DATA.SET_CONT_MODE then
                        if cmd.val == types.CONTAINER_MODE.BOTH or
                           cmd.val == types.CONTAINER_MODE.FILL or
                           cmd.val == types.CONTAINER_MODE.EMPTY then
                            _set_cont_mode(cmd.val)
                        else
                            log.debug(util.c(log_tag, "unrecognized container mode \"", cmd.val, "\""))
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

        time_now = util.time()

        -- handle periodics

        if self.periodics.next_formed_req <= time_now then
            _request_formed()
            self.periodics.next_formed_req = time_now + PERIODICS.FORMED
        end

        if self.db.formed then
            if not self.has_build and self.periodics.next_build_req <= time_now then
                _request_build()
                self.periodics.next_build_req = time_now + PERIODICS.BUILD
            end

            if self.periodics.next_state_req <= time_now then
                _request_state()
                self.periodics.next_state_req = time_now + PERIODICS.STATE
            end

            if self.periodics.next_tanks_req <= time_now then
                _request_tanks()
                self.periodics.next_tanks_req = time_now + PERIODICS.TANKS
            end
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

return dynamicv
