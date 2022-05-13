local comms = require("scada-common.comms")
local log = require("scada-common.log")
local types = require("scada-common.types")

local txnctrl = require("supervisor.session.rtu.txnctrl")

local boiler = {}

local PROTOCOLS = comms.PROTOCOLS
local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES
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

-- create a new boiler rtu session runner
---@param session_id integer
---@param advert rtu_advertisement
---@param out_queue mqueue
boiler.new = function (session_id, advert, out_queue)
    -- type check
    if advert.type ~= RTU_UNIT_TYPES.BOILER then
        log.error("attempt to instantiate boiler RTU for type '" .. advert.type .. "'. this is a bug.")
        return nil
    end

    local log_tag = "session.rtu(" .. session_id .. ").boiler(" .. advert.index .. "): "

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
        ---@class boiler_session_db
        db = {
            build = {
                boil_cap = 0.0,
                steam_cap = 0,
                water_cap = 0,
                hcoolant_cap = 0,
                ccoolant_cap = 0,
                superheaters = 0,
                max_boil_rate = 0.0
            },
            state = {
                temperature = 0.0,
                boil_rate = 0.0
            },
            tanks = {
                steam = 0,
                steam_need = 0,
                steam_fill = 0.0,
                water = 0,
                water_need = 0,
                water_fill = 0.0,
                hcool = {},         ---@type tank_fluid
                hcool_need = 0,
                hcool_fill = 0.0,
                ccool = {},         ---@type tank_fluid
                ccool_need = 0,
                ccool_fill = 0.0
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
        -- read input registers 1 through 7 (start = 1, count = 7)
        _send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 7 })
    end

    -- query the state of the device
    local _request_state = function ()
        -- read input registers 8 through 9 (start = 8, count = 2)
        _send_request(TXN_TYPES.STATE, MODBUS_FCODE.READ_INPUT_REGS, { 8, 2 })
    end

    -- query the tanks of the device
    local _request_tanks = function ()
        -- read input registers 10 through 21 (start = 10, count = 12)
        _send_request(TXN_TYPES.TANKS, MODBUS_FCODE.READ_INPUT_REGS, { 10, 12 })
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
                    if m_pkt.length == 7 then
                        self.db.build.boil_cap = m_pkt.data[1]
                        self.db.build.steam_cap = m_pkt.data[2]
                        self.db.build.water_cap = m_pkt.data[3]
                        self.db.build.hcoolant_cap = m_pkt.data[4]
                        self.db.build.ccoolant_cap = m_pkt.data[5]
                        self.db.build.superheaters = m_pkt.data[6]
                        self.db.build.max_boil_rate = m_pkt.data[7]
                    else
                        log.debug(log_tag .. "MODBUS transaction reply length mismatch (boiler.build)")
                    end
                elseif txn_type == TXN_TYPES.STATE then
                    -- state response
                    if m_pkt.length == 2 then
                        self.db.state.temperature = m_pkt.data[1]
                        self.db.state.boil_rate = m_pkt.data[2]
                    else
                        log.debug(log_tag .. "MODBUS transaction reply length mismatch (boiler.state)")
                    end
                elseif txn_type == TXN_TYPES.TANKS then
                    -- tanks response
                    if m_pkt.length == 12 then
                        self.db.tanks.steam = m_pkt.data[1]
                        self.db.tanks.steam_need = m_pkt.data[2]
                        self.db.tanks.steam_fill = m_pkt.data[3]
                        self.db.tanks.water = m_pkt.data[4]
                        self.db.tanks.water_need = m_pkt.data[5]
                        self.db.tanks.water_fill = m_pkt.data[6]
                        self.db.tanks.hcool = m_pkt.data[7]
                        self.db.tanks.hcool_need = m_pkt.data[8]
                        self.db.tanks.hcool_fill = m_pkt.data[9]
                        self.db.tanks.ccool = m_pkt.data[10]
                        self.db.tanks.ccool_need = m_pkt.data[11]
                        self.db.tanks.ccool_fill = m_pkt.data[12]
                    else
                        log.debug(log_tag .. "MODBUS transaction reply length mismatch (boiler.tanks)")
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
        if not self.has_build and self.next_build_req <= time_now then
            _request_build()
            self.next_build_req = time_now + PERIODICS.BUILD
        end

        if self.next_state_req <= time_now then
            _request_state()
            self.next_state_req = time_now + PERIODICS.STATE
        end

        if self.next_tanks_req <= time_now then
            _request_tanks()
            self.next_tanks_req = time_now + PERIODICS.TANKS
        end
    end

    return public
end

return boiler
