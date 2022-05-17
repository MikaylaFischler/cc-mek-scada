local comms = require("scada-common.comms")
local log = require("scada-common.log")
local types = require("scada-common.types")

local txnctrl = require("supervisor.session.rtu.txnctrl")

local unit_session = {}

local PROTOCOLS = comms.PROTOCOLS
local MODBUS_FCODE = types.MODBUS_FCODE
local MODBUS_EXCODE = types.MODBUS_EXCODE

-- create a new unit session runner
---@param log_tag string
---@param advert rtu_advertisement
---@param out_queue mqueue
---@param txn_tags table
unit_session.new = function (log_tag, advert, out_queue, txn_tags)
    local self = {
        log_tag = log_tag,
        txn_tags = txn_tags,
        uid = advert.index,
        reactor = advert.reactor,
        out_q = out_queue,
        transaction_controller = txnctrl.new(),
        connected = true,
        device_fail = false
    }

    ---@class _unit_session
    local protected = {}

    ---@class unit_session
    local public = {}

    -- PROTECTED FUNCTIONS --

    -- send a MODBUS message, creating a transaction in the process
    ---@param txn_type integer transaction type
    ---@param f_code MODBUS_FCODE function code
    ---@param register_param table register range or register and values
    protected.send_request = function (txn_type, f_code, register_param)
        local m_pkt = comms.modbus_packet()
        local txn_id = self.transaction_controller.create(txn_type)

        m_pkt.make(txn_id, self.uid, f_code, register_param)

        self.out_q.push_packet(m_pkt)
    end

    -- try to resolve a MODBUS transaction
    ---@param m_pkt modbus_frame MODBUS packet
    ---@return integer|false txn_type transaction type or false on error/busy
    protected.try_resolve = function (m_pkt)
        if m_pkt.scada_frame.protocol() == PROTOCOLS.MODBUS_TCP then
            if m_pkt.unit_id == self.uid then
                local txn_type = self.transaction_controller.resolve(m_pkt.txn_id)
                local txn_tag = " (" .. self.txn_tags[txn_type] .. ")"

                if bit.band(m_pkt.func_code, MODBUS_FCODE.ERROR_FLAG) ~= 0 then
                    -- transaction incomplete or failed
                    local ex = m_pkt.data[1]
                    if ex == MODBUS_EXCODE.ILLEGAL_FUNCTION then
                        log.error(log_tag .. "MODBUS: illegal function" .. txn_tag)
                    elseif ex == MODBUS_EXCODE.ILLEGAL_DATA_ADDR then
                        log.error(log_tag .. "MODBUS: illegal data address" .. txn_tag)
                    elseif ex == MODBUS_EXCODE.SERVER_DEVICE_FAIL then
                        if self.device_fail then
                            log.debug(log_tag .. "MODBUS: repeated device failure" .. txn_tag)
                        else
                            self.device_fail = true
                            log.warning(log_tag .. "MODBUS: device failure" .. txn_tag)
                        end
                    elseif ex == MODBUS_EXCODE.ACKNOWLEDGE then
                        -- will have to wait on reply, renew the transaction
                        self.transaction_controller.renew(m_pkt.txn_id, txn_type)
                    elseif ex == MODBUS_EXCODE.SERVER_DEVICE_BUSY then
                        -- will have to wait on reply, renew the transaction
                        self.transaction_controller.renew(m_pkt.txn_id, txn_type)
                        log.debug(log_tag .. "MODBUS: device busy" .. txn_tag)
                    elseif ex == MODBUS_EXCODE.NEG_ACKNOWLEDGE then
                        -- general failure
                        log.error(log_tag .. "MODBUS: negative acknowledge (bad request)" .. txn_tag)
                    elseif ex == MODBUS_EXCODE.GATEWAY_PATH_UNAVAILABLE then
                        -- RTU gateway has no known unit with the given ID
                        log.error(log_tag .. "MODBUS: gateway path unavailable (unknown unit)" .. txn_tag)
                    elseif ex ~= nil then
                        -- unsupported exception code
                        log.debug(log_tag .. "MODBUS: unsupported error " .. ex .. txn_tag)
                    else
                        -- nil exception code
                        log.debug(log_tag .. "MODBUS: nil exception code" .. txn_tag)
                    end
                else
                    -- clear device fail flag
                    self.device_fail = false

                    -- no error, return the transaction type
                    return txn_type
                end
            else
                log.error(log_tag .. "wrong unit ID: " .. m_pkt.unit_id, true)
            end
        else
            log.error(log_tag .. "illegal packet type " .. m_pkt.scada_frame.protocol(), true)
        end

        -- error or transaction in progress, return false
        return false
    end

    -- get the public interface
    protected.get = function () return public end

    -- PUBLIC FUNCTIONS --

    -- get the unit ID
    public.get_uid = function () return self.uid end
    -- get the reactor ID
    public.get_reactor = function () return self.reactor end

    -- close this unit
    public.close = function () self.connected = false end
    -- check if this unit is connected
    public.is_connected = function () return self.connected end
    -- check if this unit is faulted
    public.is_faulted = function () return self.device_fail end

    return protected
end

return unit_session
