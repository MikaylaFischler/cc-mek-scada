local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local types = require("scada-common.types")

local unit_session = require("supervisor.session.rtu.unit_session")

local turbine = {}

local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES
local DUMPING_MODE = types.DUMPING_MODE
local MODBUS_FCODE = types.MODBUS_FCODE

local TXN_TYPES = {
    BUILD = 1,
    STATE = 2,
    TANKS = 3
}

local TXN_TAGS = {
    "turbine.build",
    "turbine.state",
    "turbine.tanks",
}

local PERIODICS = {
    BUILD = 1000,
    STATE = 500,
    TANKS = 1000
}

-- create a new turbine rtu session runner
---@param session_id integer
---@param unit_id integer
---@param advert rtu_advertisement
---@param out_queue mqueue
function turbine.new(session_id, unit_id, advert, out_queue)
    -- type check
    if advert.type ~= RTU_UNIT_TYPES.TURBINE then
        log.error("attempt to instantiate turbine RTU for type '" .. advert.type .. "'. this is a bug.")
        return nil
    end

    local log_tag = "session.rtu(" .. session_id .. ").turbine(" .. advert.index .. "): "

    local self = {
        session = unit_session.new(unit_id, advert, out_queue, log_tag, TXN_TAGS),
        has_build = false,
        periodics = {
            next_build_req = 0,
            next_state_req = 0,
            next_tanks_req = 0,
        },
        ---@class turbine_session_db
        db = {
            build = {
                blades = 0,
                coils = 0,
                vents = 0,
                dispersers = 0,
                condensers = 0,
                steam_cap = 0,
                max_flow_rate = 0,
                max_production = 0,
                max_water_output = 0
            },
            state = {
                flow_rate = 0.0,
                prod_rate = 0.0,
                steam_input_rate = 0.0,
                dumping_mode = DUMPING_MODE.IDLE    ---@type DUMPING_MODE
            },
            tanks = {
                steam = 0,
                steam_need = 0,
                steam_fill = 0.0
            }
        }
    }

    local public = self.session.get()

    -- PRIVATE FUNCTIONS --

    -- query the build of the device
    local function _request_build()
        -- read input registers 1 through 9 (start = 1, count = 9)
        self.session.send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 9 })
    end

    -- query the state of the device
    local function _request_state()
        -- read input registers 10 through 13 (start = 10, count = 4)
        self.session.send_request(TXN_TYPES.STATE, MODBUS_FCODE.READ_INPUT_REGS, { 10, 4 })
    end

    -- query the tanks of the device
    local function _request_tanks()
        -- read input registers 14 through 16 (start = 14, count = 3)
        self.session.send_request(TXN_TYPES.TANKS, MODBUS_FCODE.READ_INPUT_REGS, { 14, 3 })
    end

    -- PUBLIC FUNCTIONS --

    -- handle a packet
    ---@param m_pkt modbus_frame
    function public.handle_packet(m_pkt)
        local txn_type = self.session.try_resolve(m_pkt.txn_id)
        if txn_type == false then
            -- nothing to do
        elseif txn_type == TXN_TYPES.BUILD then
            -- build response
            if m_pkt.length == 9 then
                self.db.build.blades           = m_pkt.data[1]
                self.db.build.coils            = m_pkt.data[2]
                self.db.build.vents            = m_pkt.data[3]
                self.db.build.dispersers       = m_pkt.data[4]
                self.db.build.condensers       = m_pkt.data[5]
                self.db.build.steam_cap        = m_pkt.data[6]
                self.db.build.max_flow_rate    = m_pkt.data[7]
                self.db.build.max_production   = m_pkt.data[8]
                self.db.build.max_water_output = m_pkt.data[9]
                self.has_build = true
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.STATE then
            -- state response
            if m_pkt.length == 4 then
                self.db.state.flow_rate        = m_pkt.data[1]
                self.db.state.prod_rate        = m_pkt.data[2]
                self.db.state.steam_input_rate = m_pkt.data[3]
                self.db.state.dumping_mode     = m_pkt.data[4]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.TANKS then
            -- tanks response
            if m_pkt.length == 3 then
                self.db.tanks.steam      = m_pkt.data[1]
                self.db.tanks.steam_need = m_pkt.data[2]
                self.db.tanks.steam_fill = m_pkt.data[3]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == nil then
            log.error(log_tag .. "unknown transaction reply")
        else
            log.error(log_tag .. "unknown transaction type " .. txn_type)
        end
    end

    -- update this runner
    ---@param time_now integer milliseconds
    function public.update(time_now)
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

        self.session.post_update()
    end

    -- get the unit session database
    function public.get_db() return self.db end

    return public
end

return turbine
