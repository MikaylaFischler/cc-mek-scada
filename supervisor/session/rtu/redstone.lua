local comms = require("scada-common.comms")
local log = require("scada-common.log")
local rsio = require("scada-common.rsio")
local types = require("scada-common.types")

local txnctrl = require("supervisor.session.rtu.txnctrl")

local redstone = {}

local PROTOCOLS = comms.PROTOCOLS
local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES
local MODBUS_FCODE = types.MODBUS_FCODE

local RS_IO = rsio.IO
local IO_LVL = rsio.IO_LVL
local IO_DIR = rsio.IO_DIR
local IO_MODE = rsio.IO_MODE

local rtu_t = types.rtu_t

local TXN_TYPES = {
    DI_READ = 0,
    INPUT_REG_READ = 1
}

local PERIODICS = {
    INPUT_READ = 200
}

-- create a new redstone rtu session runner
---@param session_id integer
---@param advert rtu_advertisement
---@param out_queue mqueue
redstone.new = function (session_id, advert, out_queue)
    -- type check
    if advert.type ~= RTU_UNIT_TYPES.REDSTONE then
        log.error("attempt to instantiate redstone RTU for type '" .. advert.type .. "'. this is a bug.")
        return nil
    end

    local log_tag = "session.rtu(" .. session_id .. ").redstone(" .. advert.index .. "): "

    local self = {
        uid = advert.index,
        reactor = advert.reactor,
        out_q = out_queue,
        transaction_controller = txnctrl.new(),
        has_di = false,
        has_ai = false,
        periodics = {
            next_di_req = 0,
            next_ir_req = 0,
        },
        io_list = {
            digital_in = {},    -- discrete inputs
            digital_out = {},   -- coils
            analog_in = {},     -- input registers
            analog_out = {}     -- holding registers
        },
        db = {}
    }

    ---@class unit_session
    local public = {}

    -- INITIALIZE --

    for _ = 1, #RS_IO do
        table.insert(self.db, IO_LVL.DISCONNECT)
    end

    for i = 1, #advert.rsio do
        local channel = advert.rsio[i]
        local mode = rsio.get_io_mode(channel)

        if mode == IO_MODE.DIGITAL_IN then
            self.has_di = true
            table.insert(self.io_list.digital_in, channel)
        elseif mode == IO_MODE.DIGITAL_OUT then
            table.insert(self.io_list.digital_out, channel)
        elseif mode == IO_MODE.ANALOG_IN then
            self.has_ai = true
            table.insert(self.io_list.analog_in, channel)
        elseif mode == IO_MODE.ANALOG_OUT then
            table.insert(self.io_list.analog_out, channel)
        else
            -- should be unreachable code, we already validated channels
            log.error(log_tag .. "failed to identify advertisement channel IO mode (" .. channel .. ")", true)
            return nil
        end

        self.db[channel] = IO_LVL.LOW
    end


    -- PRIVATE FUNCTIONS --

    local _send_request = function (txn_type, f_code, register_range)
        local m_pkt = comms.modbus_packet()
        local txn_id = self.transaction_controller.create(txn_type)

        m_pkt.make(txn_id, self.uid, f_code, register_range)

        self.out_q.push_packet(m_pkt)
    end

    -- query discrete inputs
    local _request_discrete_inputs = function ()
        _send_request(TXN_TYPES.DI_READ, MODBUS_FCODE.READ_DISCRETE_INPUTS, { 1, #self.io_list.digital_in })
    end

    -- query input registers
    local _request_input_registers = function ()
        _send_request(TXN_TYPES.INPUT_REG_READ, MODBUS_FCODE.READ_INPUT_REGS, { 1, #self.io_list.analog_in })
    end

    -- PUBLIC FUNCTIONS --

    -- handle a packet
    ---@param m_pkt modbus_frame
    public.handle_packet = function (m_pkt)
        local success = false

        if m_pkt.scada_frame.protocol() == PROTOCOLS.MODBUS_TCP then
            if m_pkt.unit_id == self.uid then
                local txn_type = self.transaction_controller.resolve(m_pkt.txn_id)
                if txn_type == TXN_TYPES.DI_READ then
                    -- discrete input read response
                    if m_pkt.length == #self.io_list.digital_in then
                        for i = 1, m_pkt.length do
                            local channel = self.io_list.digital_in[i]
                            local value = m_pkt.data[i]
                            self.db[channel] = value
                        end
                    else
                        log.debug(log_tag .. "MODBUS transaction reply length mismatch (redstone.discrete_input_read)")
                    end
                elseif txn_type == TXN_TYPES.INPUT_REG_READ then
                    -- input register read response
                    if m_pkt.length == #self.io_list.analog_in then
                        for i = 1, m_pkt.length do
                            local channel = self.io_list.analog_in[i]
                            local value = m_pkt.data[i]
                            self.db[channel] = value
                        end
                    else
                        log.debug(log_tag .. "MODBUS transaction reply length mismatch (redstone.input_reg_read)")
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
        if self.has_di then
            if self.periodics.next_di_req <= time_now then
                _request_discrete_inputs()
                self.periodics.next_di_req = time_now + PERIODICS.INPUT_READ
            end
        end

        if self.has_ai then
            if self.periodics.next_ir_req <= time_now then
                _request_input_registers()
                self.periodics.next_ir_req = time_now + PERIODICS.INPUT_READ
            end
        end
    end

    return public
end

return redstone
