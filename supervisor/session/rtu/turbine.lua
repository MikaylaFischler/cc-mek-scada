local comms = require("scada-common.comms")
local log = require("scada-common.log")
local types = require("scada-common.types")

local txnctrl = require("supervisor.session.rtu.txnctrl")

local turbine = {}

local PROTOCOLS = comms.PROTOCOLS
local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES
local DUMPING_MODE = types.DUMPING_MODE
local MODBUS_FCODE = types.MODBUS_FCODE

local rtu_t = types.rtu_t

local TXN_TYPES = {
    BUILD = 0,
    STATE = 1,
    TANKS = 2
}

local PERIODICS = {
    BUILD = 1000,
    STATE = 500,
    TANKS = 1000
}

-- create a new turbine rtu session runner
---@param session_id integer
---@param advert rtu_advertisement
---@param out_queue mqueue
turbine.new = function (session_id, advert, out_queue)
    -- type check
    if advert.type ~= RTU_UNIT_TYPES.TURBINE then
        log.error("attempt to instantiate turbine RTU for type '" .. advert.type .. "'. this is a bug.")
        return nil
    end

    local log_tag = "session.rtu(" .. session_id .. ").turbine(" .. advert.index .. "): "

    local self = {
        uid = advert.index,
        reactor = advert.reactor,
        out_q = out_queue,
        transaction_controller = txnctrl.new(),
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

    ---@class unit_session
    local public = {}

    -- PRIVATE FUNCTIONS --

    local _send_request = function (txn_type, f_code, register_range)
        local m_pkt = comms.modbus_packet()
        local txn_id = self.transaction_controller.create(txn_type)

        m_pkt.make(txn_id, self.uid, f_code, register_range)

        self.out_q.push_packet(m_pkt)
    end

    -- query the build of the device
    local _request_build = function ()
        -- read input registers 1 through 9 (start = 1, count = 9)
        _send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 9 })
    end

    -- query the state of the device
    local _request_state = function ()
        -- read input registers 10 through 13 (start = 10, count = 4)
        _send_request(TXN_TYPES.STATE, MODBUS_FCODE.READ_INPUT_REGS, { 10, 4 })
    end

    -- query the tanks of the device
    local _request_tanks = function ()
        -- read input registers 14 through 16 (start = 14, count = 3)
        _send_request(TXN_TYPES.TANKS, MODBUS_FCODE.READ_INPUT_REGS, { 14, 3 })
    end

    -- PUBLIC FUNCTIONS --

    -- handle a packet
    ---@param m_pkt modbus_frame
    public.handle_packet = function (m_pkt)
        local success = false

        if m_pkt.scada_frame.protocol() == PROTOCOLS.MODBUS_TCP then
            if m_pkt.unit_id == self.uid then
                local txn_type = self.transaction_controller.resolve(m_pkt.txn_id)
                if txn_type == TXN_TYPES.BUILD then
                    -- build response
                    if m_pkt.length == 9 then
                        self.db.build.blades = m_pkt.data[1]
                        self.db.build.coils = m_pkt.data[2]
                        self.db.build.vents = m_pkt.data[3]
                        self.db.build.dispersers = m_pkt.data[4]
                        self.db.build.condensers = m_pkt.data[5]
                        self.db.build.steam_cap = m_pkt.data[6]
                        self.db.build.max_flow_rate = m_pkt.data[7]
                        self.db.build.max_production = m_pkt.data[8]
                        self.db.build.max_water_output = m_pkt.data[9]
                    else
                        log.debug(log_tag .. "MODBUS transaction reply length mismatch (turbine.build)")
                    end
                elseif txn_type == TXN_TYPES.STATE then
                    -- state response
                    if m_pkt.length == 4 then
                        self.db.state.flow_rate = m_pkt.data[1]
                        self.db.state.prod_rate = m_pkt.data[2]
                        self.db.state.steam_input_rate = m_pkt.data[3]
                        self.db.state.dumping_mode = m_pkt.data[4]
                    else
                        log.debug(log_tag .. "MODBUS transaction reply length mismatch (turbine.state)")
                    end
                elseif txn_type == TXN_TYPES.TANKS then
                    -- tanks response
                    if m_pkt.length == 3 then
                        self.db.tanks.steam = m_pkt.data[1]
                        self.db.tanks.steam_need = m_pkt.data[2]
                        self.db.tanks.steam_fill = m_pkt.data[3]
                    else
                        log.debug(log_tag .. "MODBUS transaction reply length mismatch (turbine.tanks)")
                    end
                elseif txn_type == nil then
                    log.error(log_tag .. "unknown transaction reply")
                else
                    log.error(log_tag .. "unknown transaction type " .. txn_type)
                end
            else
                log.error(log_tag .. "wrong unit ID: " .. m_pkt.unit_id, true)
            end
        else
            log.error(log_tag .. "illegal packet type " .. m_pkt.scada_frame.protocol(), true)
        end

        return success
    end

    public.get_uid = function () return self.uid end
    public.get_reactor = function () return self.reactor end
    public.get_db = function () return self.db end

    -- update this runner
    ---@param time_now integer milliseconds
    public.update = function (time_now)
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

    return public
end

return turbine
