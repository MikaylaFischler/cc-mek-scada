local comms = require("scada-common.comms")
local ppm = require("scada-common.ppm")
local log = require("scada-common.log")
local types = require("scada-common.types")
local util = require("scada-common.util")

local modbus = require("rtu.modbus")

local rtu = {}

local rtu_t = types.rtu_t

local PROTOCOLS = comms.PROTOCOLS
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES
local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

-- create a new RTU
rtu.init_unit = function ()
    local self = {
        discrete_inputs = {},
        coils = {},
        input_regs = {},
        holding_regs = {},
        io_count_cache = { 0, 0, 0, 0 }
    }

    local insert = table.insert

    ---@class rtu_device
    local public = {}

    ---@class rtu
    local protected = {}

    -- refresh IO count
    local _count_io = function ()
        self.io_count_cache = { #self.discrete_inputs, #self.coils, #self.input_regs, #self.holding_regs }
    end

    -- return IO count
    ---@return integer discrete_inputs, integer coils, integer input_regs, integer holding_regs
    public.io_count = function ()
        return self.io_count_cache[1], self.io_count_cache[2], self.io_count_cache[3], self.io_count_cache[4]
    end

    -- discrete inputs: single bit read-only

    -- connect discrete input
    ---@param f function
    ---@return integer count count of discrete inputs
    protected.connect_di = function (f)
        insert(self.discrete_inputs, f)
        _count_io()
        return #self.discrete_inputs
    end

    -- read discrete input
    ---@param di_addr integer
    ---@return any value, boolean access_fault
    public.read_di = function (di_addr)
        ppm.clear_fault()
        local value = self.discrete_inputs[di_addr]()
        return value, ppm.is_faulted()
    end

    -- coils: single bit read-write

    -- connect coil
    ---@param f_read function
    ---@param f_write function
    ---@return integer count count of coils
    protected.connect_coil = function (f_read, f_write)
        insert(self.coils, { read = f_read, write = f_write })
        _count_io()
        return #self.coils
    end

    -- read coil
    ---@param coil_addr integer
    ---@return any value, boolean access_fault
    public.read_coil = function (coil_addr)
        ppm.clear_fault()
        local value = self.coils[coil_addr].read()
        return value, ppm.is_faulted()
    end

    -- write coil
    ---@param coil_addr integer
    ---@param value any
    ---@return boolean access_fault
    public.write_coil = function (coil_addr, value)
        ppm.clear_fault()
        self.coils[coil_addr].write(value)
        return ppm.is_faulted()
    end

    -- input registers: multi-bit read-only

    -- connect input register
    ---@param f function
    ---@return integer count count of input registers
    protected.connect_input_reg = function (f)
        insert(self.input_regs, f)
        _count_io()
        return #self.input_regs
    end

    -- read input register
    ---@param reg_addr integer
    ---@return any value, boolean access_fault
    public.read_input_reg = function (reg_addr)
        ppm.clear_fault()
        local value = self.coils[reg_addr]()
        return value, ppm.is_faulted()
    end

    -- holding registers: multi-bit read-write

    -- connect holding register
    ---@param f_read function
    ---@param f_write function
    ---@return integer count count of holding registers
    protected.connect_holding_reg = function (f_read, f_write)
        insert(self.holding_regs, { read = f_read, write = f_write })
        _count_io()
        return #self.holding_regs
    end

    -- read holding register
    ---@param reg_addr integer
    ---@return any value, boolean access_fault
    public.read_holding_reg = function (reg_addr)
        ppm.clear_fault()
        local value = self.coils[reg_addr].read()
        return value, ppm.is_faulted()
    end

    -- write holding register
    ---@param reg_addr integer
    ---@param value any
    ---@return boolean access_fault
    public.write_holding_reg = function (reg_addr, value)
        ppm.clear_fault()
        self.coils[reg_addr].write(value)
        return ppm.is_faulted()
    end

    -- public RTU device access

    -- get the public interface to this RTU
    protected.interface = function ()
        return public
    end

    return protected
end

-- RTU Communications
---@param modem table
---@param local_port integer
---@param server_port integer
---@param conn_watchdog watchdog
rtu.comms = function (modem, local_port, server_port, conn_watchdog)
    local self = {
        seq_num = 0,
        r_seq_num = nil,
        txn_id = 0,
        modem = modem,
        s_port = server_port,
        l_port = local_port,
        conn_watchdog = conn_watchdog
    }

    ---@class rtu_comms
    local public = {}

    local insert = table.insert

    -- open modem
    if not self.modem.isOpen(self.l_port) then
        self.modem.open(self.l_port)
    end

    -- PRIVATE FUNCTIONS --

    -- send a scada management packet
    ---@param msg_type SCADA_MGMT_TYPES
    ---@param msg table
    local _send = function (msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.SCADA_MGMT, m_pkt.raw_sendable())

        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- keep alive ack
    ---@param srv_time integer
    local _send_keep_alive_ack = function (srv_time)
        _send(SCADA_MGMT_TYPES.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- PUBLIC FUNCTIONS --

    -- send a MODBUS TCP packet
    ---@param m_pkt modbus_packet
    public.send_modbus = function (m_pkt)
        local s_pkt = comms.scada_packet()
        s_pkt.make(self.seq_num, PROTOCOLS.MODBUS_TCP, m_pkt.raw_sendable())
        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- reconnect a newly connected modem
    ---@param modem table
---@diagnostic disable-next-line: redefined-local
    public.reconnect_modem = function (modem)
        self.modem = modem

        -- open modem
        if not self.modem.isOpen(self.l_port) then
            self.modem.open(self.l_port)
        end
    end

    -- unlink from the server
    ---@param rtu_state rtu_state
    public.unlink = function (rtu_state)
        rtu_state.linked = false
        self.r_seq_num = nil
    end

    -- close the connection to the server
    ---@param rtu_state rtu_state
    public.close = function (rtu_state)
        self.conn_watchdog.cancel()
        public.unlink(rtu_state)
        _send(SCADA_MGMT_TYPES.CLOSE, {})
    end

    -- send capability advertisement
    ---@param units table
    public.send_advertisement = function (units)
        local advertisement = {}

        for i = 1, #units do
            local unit = units[i]   --@type rtu_unit_registry_entry
            local type = comms.rtu_t_to_unit_type(unit.type)

            if type ~= nil then
                local advert = {
                    type,
                    unit.index,
                    unit.reactor
                }

                if type == RTU_UNIT_TYPES.REDSTONE then
                    insert(advert, unit.device)
                end

                insert(advertisement, advert)
            end
        end

        _send(SCADA_MGMT_TYPES.RTU_ADVERT, advertisement)
    end

    -- parse a MODBUS/SCADA packet
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return modbus_frame|mgmt_frame|nil packet
    public.parse_packet = function(side, sender, reply_to, message, distance)
        local pkt = nil
        local s_pkt = comms.scada_packet()

        -- parse packet as generic SCADA packet
        s_pkt.receive(side, sender, reply_to, message, distance)

        if s_pkt.is_valid() then
            -- get as MODBUS TCP packet
            if s_pkt.protocol() == PROTOCOLS.MODBUS_TCP then
                local m_pkt = comms.modbus_packet()
                if m_pkt.decode(s_pkt) then
                    pkt = m_pkt.get()
                end
            -- get as SCADA management packet
            elseif s_pkt.protocol() == PROTOCOLS.SCADA_MGMT then
                local mgmt_pkt = comms.mgmt_packet()
                if mgmt_pkt.decode(s_pkt) then
                    pkt = mgmt_pkt.get()
                end
            else
                log.error("illegal packet type " .. s_pkt.protocol(), true)
            end
        end

        return pkt
    end

    -- handle a MODBUS/SCADA packet
    ---@param packet modbus_frame|mgmt_frame
    ---@param units table
    ---@param rtu_state rtu_state
    public.handle_packet = function(packet, units, rtu_state)
        if packet ~= nil then
            -- check sequence number
            if self.r_seq_num == nil then
                self.r_seq_num = packet.scada_frame.seq_num()
            elseif rtu_state.linked and self.r_seq_num >= packet.scada_frame.seq_num() then
                log.warning("sequence out-of-order: last = " .. self.r_seq_num .. ", new = " .. packet.scada_frame.seq_num())
                return
            else
                self.r_seq_num = packet.scada_frame.seq_num()
            end

            -- feed watchdog on valid sequence number
            self.conn_watchdog.feed()

            local protocol = packet.scada_frame.protocol()

            if protocol == PROTOCOLS.MODBUS_TCP then
                local return_code = false
                local reply = modbus.reply__neg_ack(packet)

                -- handle MODBUS instruction
                if packet.unit_id <= #units then
                    local unit = units[packet.unit_id]  ---@type rtu_unit_registry_entry
                    if unit.name == "redstone_io" then
                        -- immediately execute redstone RTU requests
                        return_code, reply = unit.modbus_io.handle_packet(packet)
                        if not return_code then
                            log.warning("requested MODBUS operation failed")
                        end
                    else
                        -- check validity then pass off to unit comms thread
                        return_code, reply = unit.modbus_io.check_request(packet)
                        if return_code then
                            -- check if an operation is already in progress for this unit
                            if unit.modbus_busy then
                                reply = unit.modbus_io.reply__srv_device_busy(packet)
                            else
                                unit.pkt_queue.push_packet(packet)
                            end
                        else
                            log.warning("cannot perform requested MODBUS operation")
                        end
                    end
                else
                    -- unit ID out of range?
                    reply = modbus.reply__gw_unavailable(packet)
                    log.error("MODBUS packet requesting non-existent unit")
                end

                public.send_modbus(reply)
            elseif protocol == PROTOCOLS.SCADA_MGMT then
                -- SCADA management packet
                if packet.type == SCADA_MGMT_TYPES.KEEP_ALIVE then
                    -- keep alive request received, echo back
                    if packet.length == 1 then
                        local timestamp = packet.data[1]
                        local trip_time = util.time() - timestamp

                        if trip_time > 500 then
                            log.warning("RTU KEEP_ALIVE trip time > 500ms (" .. trip_time .. "ms)")
                        end

                        -- log.debug("RTU RTT = ".. trip_time .. "ms")

                        _send_keep_alive_ack(timestamp)
                    else
                        log.debug("SCADA keep alive packet length mismatch")
                    end
                elseif packet.type == SCADA_MGMT_TYPES.CLOSE then
                    -- close connection
                    self.conn_watchdog.cancel()
                    public.unlink(rtu_state)
                    println_ts("server connection closed by remote host")
                    log.warning("server connection closed by remote host")
                elseif packet.type == SCADA_MGMT_TYPES.REMOTE_LINKED then
                    -- acknowledgement
                    rtu_state.linked = true
                    self.r_seq_num = nil
                elseif packet.type == SCADA_MGMT_TYPES.RTU_ADVERT then
                    -- request for capabilities again
                    public.send_advertisement(units)
                else
                    -- not supported
                    log.warning("RTU got unexpected SCADA message type " .. packet.type)
                end
            else
                -- should be unreachable assuming packet is from parse_packet()
                log.error("illegal packet type " .. protocol, true)
            end
        end
    end

    return public
end

return rtu
