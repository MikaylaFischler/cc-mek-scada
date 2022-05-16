local comms = require("scada-common.comms")
local log = require("scada-common.log")
local mqueue= require("scada-common.mqueue")
local rsio = require("scada-common.rsio")
local types = require("scada-common.types")
local util  = require("scada-common.util")

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

local RS_RTU_S_CMDS = {
}

local RS_RTU_S_DATA = {
    RS_COMMAND = 1
}

redstone.RS_RTU_S_CMDS = RS_RTU_S_CMDS
redstone.RS_RTU_S_DATA = RS_RTU_S_DATA

local TXN_TYPES = {
    DI_READ = 0,
    COIL_WRITE = 1,
    INPUT_REG_READ = 2,
    HOLD_REG_WRITE = 3
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
        in_q = mqueue.new(),
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

    -- create all channels as disconnected
    for _ = 1, #RS_IO do
        table.insert(self.db, IO_LVL.DISCONNECT)
    end

    -- setup I/O
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

    local _send_request = function (txn_type, f_code, parameters)
        local m_pkt = comms.modbus_packet()
        local txn_id = self.transaction_controller.create(txn_type)

        m_pkt.make(txn_id, self.uid, f_code, parameters)

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

    -- write coil output
    local _write_coil = function (coil, value)
        _send_request(TXN_TYPES.COIL_WRITE, MODBUS_FCODE.WRITE_MUL_COILS, { coil, value })
    end

    -- write holding register output
    local _write_holding_register = function (reg, value)
        _send_request(TXN_TYPES.HOLD_REG_WRITE, MODBUS_FCODE.WRITE_MUL_HOLD_REGS, { reg, value })
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
        -- check command queue
        while self.in_q.ready() do
            -- get a new message to process
            local msg = self.in_q.pop()

            if msg ~= nil then
                if msg.qtype == mqueue.TYPE.DATA then
                    -- instruction with body
                    local cmd = msg.message     ---@type queue_data
                    if cmd.key == RS_RTU_S_DATA.RS_COMMAND then
                        local rs_cmd = cmd.val  ---@type rs_session_command

                        if self.db[rs_cmd.channel] ~= IO_LVL.DISCONNECT then
                            -- we have this as a connected channel
                            local mode = rsio.get_io_mode(rs_cmd.channel)
                            if mode == IO_MODE.DIGITAL_OUT then
                                -- record the value for retries
                                self.db[rs_cmd.channel] = rs_cmd.value

                                -- find the coil address then write to it
                                for i = 0, #self.digital_out do
                                    if self.digital_out[i] == rs_cmd.channel then
                                        _write_coil(i, rs_cmd.value)
                                        break
                                    end
                                end
                            elseif mode == IO_MODE.ANALOG_OUT then
                                -- record the value for retries
                                self.db[rs_cmd.channel] = rs_cmd.value

                                -- find the holding register address then write to it
                                for i = 0, #self.analog_out do
                                    if self.analog_out[i] == rs_cmd.channel then
                                        _write_holding_register(i, rs_cmd.value)
                                        break
                                    end
                                end
                            elseif mode ~= nil then
                                log.debug(log_tag .. "attemted write to non D/O or A/O mode " .. mode)
                            end
                        end
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

        -- poll digital inputs
        if self.has_di then
            if self.periodics.next_di_req <= time_now then
                _request_discrete_inputs()
                self.periodics.next_di_req = time_now + PERIODICS.INPUT_READ
            end
        end

        -- poll analog inputs
        if self.has_ai then
            if self.periodics.next_ir_req <= time_now then
                _request_input_registers()
                self.periodics.next_ir_req = time_now + PERIODICS.INPUT_READ
            end
        end
    end

    return public, self.in_q
end

return redstone
