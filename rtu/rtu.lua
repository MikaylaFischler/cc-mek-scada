local comms  = require("scada-common.comms")
local ppm    = require("scada-common.ppm")
local log    = require("scada-common.log")
local util   = require("scada-common.util")

local modbus = require("rtu.modbus")

local rtu = {}

local PROTOCOLS = comms.PROTOCOLS
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES
local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

-- create a new RTU
function rtu.init_unit()
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
    local function _count_io()
        self.io_count_cache = { #self.discrete_inputs, #self.coils, #self.input_regs, #self.holding_regs }
    end

    -- return IO count
    ---@return integer discrete_inputs, integer coils, integer input_regs, integer holding_regs
    function public.io_count()
        return self.io_count_cache[1], self.io_count_cache[2], self.io_count_cache[3], self.io_count_cache[4]
    end

    -- discrete inputs: single bit read-only

    -- connect discrete input
    ---@param f function
    ---@return integer count count of discrete inputs
    function protected.connect_di(f)
        insert(self.discrete_inputs, { read = f })
        _count_io()
        return #self.discrete_inputs
    end

    -- read discrete input
    ---@param di_addr integer
    ---@return any value, boolean access_fault
    function public.read_di(di_addr)
        ppm.clear_fault()
        local value = self.discrete_inputs[di_addr].read()
        return value, ppm.is_faulted()
    end

    -- coils: single bit read-write

    -- connect coil
    ---@param f_read function
    ---@param f_write function
    ---@return integer count count of coils
    function protected.connect_coil(f_read, f_write)
        insert(self.coils, { read = f_read, write = f_write })
        _count_io()
        return #self.coils
    end

    -- read coil
    ---@param coil_addr integer
    ---@return any value, boolean access_fault
    function public.read_coil(coil_addr)
        ppm.clear_fault()
        local value = self.coils[coil_addr].read()
        return value, ppm.is_faulted()
    end

    -- write coil
    ---@param coil_addr integer
    ---@param value any
    ---@return boolean access_fault
    function public.write_coil(coil_addr, value)
        ppm.clear_fault()
        self.coils[coil_addr].write(value)
        return ppm.is_faulted()
    end

    -- input registers: multi-bit read-only

    -- connect input register
    ---@param f function
    ---@return integer count count of input registers
    function protected.connect_input_reg(f)
        insert(self.input_regs, { read = f })
        _count_io()
        return #self.input_regs
    end

    -- read input register
    ---@param reg_addr integer
    ---@return any value, boolean access_fault
    function public.read_input_reg(reg_addr)
        ppm.clear_fault()
        local value = self.input_regs[reg_addr].read()
        return value, ppm.is_faulted()
    end

    -- holding registers: multi-bit read-write

    -- connect holding register
    ---@param f_read function
    ---@param f_write function
    ---@return integer count count of holding registers
    function protected.connect_holding_reg(f_read, f_write)
        insert(self.holding_regs, { read = f_read, write = f_write })
        _count_io()
        return #self.holding_regs
    end

    -- read holding register
    ---@param reg_addr integer
    ---@return any value, boolean access_fault
    function public.read_holding_reg(reg_addr)
        ppm.clear_fault()
        local value = self.holding_regs[reg_addr].read()
        return value, ppm.is_faulted()
    end

    -- write holding register
    ---@param reg_addr integer
    ---@param value any
    ---@return boolean access_fault
    function public.write_holding_reg(reg_addr, value)
        ppm.clear_fault()
        self.holding_regs[reg_addr].write(value)
        return ppm.is_faulted()
    end

    -- public RTU device access

    -- get the public interface to this RTU
    function protected.interface()
        return public
    end

    return protected
end

-- RTU Communications
---@param version string
---@param modem table
---@param local_port integer
---@param server_port integer
---@param conn_watchdog watchdog
function rtu.comms(version, modem, local_port, server_port, conn_watchdog)
    local self = {
        version = version,
        seq_num = 0,
        r_seq_num = nil,
        txn_id = 0,
        modem = modem,
        s_port = server_port,
        l_port = local_port,
        conn_watchdog = conn_watchdog
    }

    -- configure modem channels
    local function _conf_channels()
        self.modem.closeAll()
        self.modem.open(self.l_port)
    end

    _conf_channels()

    ---@class rtu_comms
    local public = {}

    local insert = table.insert

    -- PRIVATE FUNCTIONS --

    -- send a scada management packet
    ---@param msg_type SCADA_MGMT_TYPES
    ---@param msg table
    local function _send(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.SCADA_MGMT, m_pkt.raw_sendable())

        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- keep alive ack
    ---@param srv_time integer
    local function _send_keep_alive_ack(srv_time)
        _send(SCADA_MGMT_TYPES.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- PUBLIC FUNCTIONS --

    -- send a MODBUS TCP packet
    ---@param m_pkt modbus_packet
    function public.send_modbus(m_pkt)
        local s_pkt = comms.scada_packet()
        s_pkt.make(self.seq_num, PROTOCOLS.MODBUS_TCP, m_pkt.raw_sendable())
        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- reconnect a newly connected modem
    ---@param modem table
---@diagnostic disable-next-line: redefined-local
    function public.reconnect_modem(modem)
        self.modem = modem
        _conf_channels()
    end

    -- unlink from the server
    ---@param rtu_state rtu_state
    function public.unlink(rtu_state)
        rtu_state.linked = false
        self.r_seq_num = nil
    end

    -- close the connection to the server
    ---@param rtu_state rtu_state
    function public.close(rtu_state)
        self.conn_watchdog.cancel()
        public.unlink(rtu_state)
        _send(SCADA_MGMT_TYPES.CLOSE, {})
    end

    -- send capability advertisement
    ---@param units table
    function public.send_advertisement(units)
        local advertisement = { self.version }

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

    -- notify that a peripheral was remounted
    ---@param unit_index integer RTU unit ID
    function public.send_remounted(unit_index)
        _send(SCADA_MGMT_TYPES.RTU_DEV_REMOUNT, { unit_index })
    end

    -- parse a MODBUS/SCADA packet
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return modbus_frame|mgmt_frame|nil packet
    function public.parse_packet(side, sender, reply_to, message, distance)
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
    function public.handle_packet(packet, units, rtu_state)
        if packet ~= nil and packet.scada_frame.local_port() == self.l_port then
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
---@diagnostic disable-next-line: param-type-mismatch
                local reply = modbus.reply__neg_ack(packet)

                -- handle MODBUS instruction
                if packet.unit_id <= #units then
                    local unit = units[packet.unit_id]  ---@type rtu_unit_registry_entry
                    local unit_dbg_tag = " (unit " .. packet.unit_id .. ")"

                    if unit.name == "redstone_io" then
                        -- immediately execute redstone RTU requests
---@diagnostic disable-next-line: param-type-mismatch
                        return_code, reply = unit.modbus_io.handle_packet(packet)
                        if not return_code then
                            log.warning("requested MODBUS operation failed" .. unit_dbg_tag)
                        end
                    else
                        -- check validity then pass off to unit comms thread
---@diagnostic disable-next-line: param-type-mismatch
                        return_code, reply = unit.modbus_io.check_request(packet)
                        if return_code then
                            -- check if there are more than 3 active transactions
                            -- still queue the packet, but this may indicate a problem
                            if unit.pkt_queue.length() > 3 then
---@diagnostic disable-next-line: param-type-mismatch
                                reply = modbus.reply__srv_device_busy(packet)
                                log.debug("queueing new request with " .. unit.pkt_queue.length() ..
                                    " transactions already in the queue" .. unit_dbg_tag)
                            end

                            -- always queue the command even if busy
                            unit.pkt_queue.push_packet(packet)
                        else
                            log.warning("cannot perform requested MODBUS operation" .. unit_dbg_tag)
                        end
                    end
                else
                    -- unit ID out of range?
---@diagnostic disable-next-line: param-type-mismatch
                    reply = modbus.reply__gw_unavailable(packet)
                    log.error("received MODBUS packet for non-existent unit")
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

                        -- log.debug("RTU RTT = " .. trip_time .. "ms")

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
                    println_ts("supervisor connection established")
                    log.info("supervisor connection established")
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
