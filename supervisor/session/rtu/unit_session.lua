local comms   = require("scada-common.comms")
local log     = require("scada-common.log")
local mqueue  = require("scada-common.mqueue")
local types   = require("scada-common.types")
local util    = require("scada-common.util")

local txnctrl = require("supervisor.session.rtu.txnctrl")

local unit_session = {}

local PROTOCOL = comms.PROTOCOL
local MODBUS_FCODE = types.MODBUS_FCODE
local MODBUS_EXCODE = types.MODBUS_EXCODE

local RTU_US_CMDS = {
}

local RTU_US_DATA = {
    BUILD_CHANGED = 1
}

unit_session.RTU_US_CMDS = RTU_US_CMDS
unit_session.RTU_US_DATA = RTU_US_DATA

local DEFAULT_BUSY_WAIT = 3000

-- create a new unit session runner
---@nodiscard
---@param session_id integer RTU gateway session ID
---@param unit_id integer MODBUS unit ID
---@param advert rtu_advertisement RTU advertisement for this unit
---@param out_queue mqueue send queue
---@param log_tag string logging tag
---@param txn_tags string[] transaction log tags
function unit_session.new(session_id, unit_id, advert, out_queue, log_tag, txn_tags)
    local self = {
        device_index = advert.index,
        reactor = advert.reactor,
        transaction_controller = txnctrl.new(),
        connected = true,
        device_fail = false,
        last_busy = 0
    }

    ---@class _unit_session
    local protected = {
        in_q = mqueue.new()
    }

    ---@class unit_session
    local public = {}

    -- PROTECTED FUNCTIONS --

    -- send a MODBUS message, creating a transaction in the process
    ---@param txn_type integer transaction type
    ---@param f_code MODBUS_FCODE function code
    ---@param register_param (number|string)[] register range or register and values
    ---@param busy_wait integer|nil milliseconds to wait (>0), or uses the default
    ---@return integer|false txn_id transaction ID of this transaction or false if not sent due to being busy
    function protected.send_request(txn_type, f_code, register_param, busy_wait)
        local txn_id = false ---@type integer|false

        busy_wait = busy_wait or DEFAULT_BUSY_WAIT

        if (util.time_ms() - self.last_busy) >= busy_wait then
            local m_pkt = comms.modbus_packet()
            txn_id = self.transaction_controller.create(txn_type)

            m_pkt.make(txn_id, unit_id, f_code, register_param)

            out_queue.push_packet(m_pkt)
        end

        return txn_id
    end

    -- try to resolve a MODBUS transaction
    ---@nodiscard
    ---@param m_pkt modbus_frame MODBUS packet
    ---@return integer|false txn_type, integer txn_id transaction type or false on error/busy, transaction ID
    function protected.try_resolve(m_pkt)
        if m_pkt.scada_frame.protocol() == PROTOCOL.MODBUS_TCP then
            if m_pkt.unit_id == unit_id then
                local txn_type = self.transaction_controller.resolve(m_pkt.txn_id)
                local txn_tag = util.c(" (", txn_tags[txn_type], ")")

                if txn_type == nil then
                    -- couldn't find this transaction
                    log.debug(log_tag .. "MODBUS: expired or spurious transaction reply (txn_id " .. m_pkt.txn_id .. ")")
                    return false, m_pkt.txn_id
                end

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
                        -- will have to try again later
                        self.last_busy = util.time_ms()
                        log.warning(log_tag .. "MODBUS: device busy" .. txn_tag)
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
                    return txn_type, m_pkt.txn_id
                end
            else
                log.error(log_tag .. "wrong unit ID: " .. m_pkt.unit_id, true)
            end
        else
            log.error(log_tag .. "illegal packet type " .. m_pkt.scada_frame.protocol(), true)
        end

        -- error or transaction in progress, return false
        return false, m_pkt.txn_id
    end

    -- post update tasks
    function protected.post_update()
        self.transaction_controller.cleanup()
    end

    -- get the public interface
    ---@nodiscard
    function protected.get() return public end

    -- PUBLIC FUNCTIONS --

    -- get the RTU gateway session ID
    ---@nodiscard
    function public.get_session_id() return session_id end
    -- get the unit ID
    ---@nodiscard
    function public.get_unit_id() return unit_id end
    -- get the RTU type
    ---@nodiscard
    function public.get_unit_type() return advert.type end
    -- get the device index
    ---@nodiscard
    function public.get_device_idx() return self.device_index or 0 end
    -- get the reactor ID
    ---@nodiscard
    function public.get_reactor() return self.reactor end
    -- get the command queue
    ---@nodiscard
    function public.get_cmd_queue() return protected.in_q end

    -- close this unit
    function public.close() self.connected = false end
    -- check if this unit is connected
    ---@nodiscard
    function public.is_connected() return self.connected end
    -- check if this unit is faulted
    ---@nodiscard
    function public.is_faulted() return self.device_fail end

    -- PUBLIC TEMPLATE FUNCTIONS --

-- luacheck: no unused args

    -- handle a packet
    ---@param m_pkt modbus_frame
---@diagnostic disable-next-line: unused-local
    function public.handle_packet(m_pkt)
        log.debug("template unit_session.handle_packet() called", true)
    end

    -- update this runner
    ---@param time_now integer milliseconds
---@diagnostic disable-next-line: unused-local
    function public.update(time_now)
        log.debug("template unit_session.update() called", true)
    end

-- luacheck: unused args

    -- invalidate build cache
    function public.invalidate_cache()
        log.debug("template unit_session.invalidate_cache() called", true)
    end

    -- get the unit session database
    ---@nodiscard
    function public.get_db()
        log.debug("template unit_session.get_db() called", true)
        return {}
    end

    return protected
end

return unit_session
