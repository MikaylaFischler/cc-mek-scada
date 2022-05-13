local comms = require("scada-common.comms")
local log = require("scada-common.log")
local types = require("scada-common.types")

local txnctrl = require("supervisor.session.rtu.txnctrl")

local emachine = {}

local PROTOCOLS = comms.PROTOCOLS
local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES
local MODBUS_FCODE = types.MODBUS_FCODE

local rtu_t = types.rtu_t

local TXN_TYPES = {
    BUILD = 0,
    STORAGE = 1
}

local PERIODICS = {
    BUILD = 1000,
    STORAGE = 500
}

-- create a new energy machine rtu session runner
---@param session_id integer
---@param advert rtu_advertisement
---@param out_queue mqueue
emachine.new = function (session_id, advert, out_queue)
    -- type check
    if advert.type ~= RTU_UNIT_TYPES.EMACHINE then
        log.error("attempt to instantiate emachine RTU for type '" .. advert.type .. "'. this is a bug.")
        return nil
    end

    local log_tag = "session.rtu(" .. session_id .. ").emachine(" .. advert.index .. "): "

    local self = {
        uid = advert.index,
        -- reactor = advert.reactor,
        reactor = 0,
        out_q = out_queue,
        transaction_controller = txnctrl.new(),
        has_build = false,
        periodics = {
            next_build_req = 0,
            next_storage_req = 0,
        },
        ---@class emachine_session_db
        db = {
            build = {
                max_energy = 0
            },
            storage = {
                energy = 0,
                energy_need = 0,
                energy_fill = 0.0
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
        -- read input register 1 (start = 1, count = 1)
        _send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 1 })
    end

    -- query the state of the energy storage
    local _request_storage = function ()
        -- read input registers 2 through 4 (start = 2, count = 3)
        _send_request(TXN_TYPES.STORAGE, MODBUS_FCODE.READ_INPUT_REGS, { 2, 3 })
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
                    if m_pkt.length == 1 then
                        self.db.build.max_energy = m_pkt.data[1]
                    else
                        log.debug(log_tag .. "MODBUS transaction reply length mismatch (emachine.build)")
                    end
                elseif txn_type == TXN_TYPES.STORAGE then
                    -- storage response
                    if m_pkt.length == 3 then
                        self.db.storage.energy = m_pkt.data[1]
                        self.db.storage.energy_need = m_pkt.data[2]
                        self.db.storage.energy_fill = m_pkt.data[3]
                    else
                        log.debug(log_tag .. "MODBUS transaction reply length mismatch (emachine.storage)")
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

        if self.next_storage_req <= time_now then
            _request_storage()
            self.next_storage_req = time_now + PERIODICS.STORAGE
        end
    end

    return public
end

return emachine
