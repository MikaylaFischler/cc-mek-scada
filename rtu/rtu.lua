local comms  = require("scada-common.comms")
local ppm    = require("scada-common.ppm")
local log    = require("scada-common.log")
local types  = require("scada-common.types")
local util   = require("scada-common.util")

local modbus = require("rtu.modbus")

local rtu = {}

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local SCADA_MGMT_TYPE = comms.SCADA_MGMT_TYPE
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE

local println_ts = util.println_ts

-- create a new RTU unit
---@nodiscard
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
    function protected.interface() return public end

    return protected
end

-- RTU Communications
---@nodiscard
---@param version string RTU version
---@param modem table modem device
---@param local_port integer local listening port
---@param server_port integer remote server port
---@param range integer trusted device connection range
---@param conn_watchdog watchdog watchdog reference
function rtu.comms(version, modem, local_port, server_port, range, conn_watchdog)
    local self = {
        seq_num = 0,
        r_seq_num = nil,
        txn_id = 0,
        last_est_ack = ESTABLISH_ACK.ALLOW
    }

    local insert = table.insert

    comms.set_trusted_range(range)

    -- PRIVATE FUNCTIONS --

    -- configure modem channels
    local function _conf_channels()
        modem.closeAll()
        modem.open(local_port)
    end

    _conf_channels()

    -- send a scada management packet
    ---@param msg_type SCADA_MGMT_TYPE
    ---@param msg table
    local function _send(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOL.SCADA_MGMT, m_pkt.raw_sendable())

        modem.transmit(server_port, local_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- keep alive ack
    ---@param srv_time integer
    local function _send_keep_alive_ack(srv_time)
        _send(SCADA_MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- generate device advertisement table
    ---@nodiscard
    ---@param units table
    ---@return table advertisement
    local function _generate_advertisement(units)
        local advertisement = {}

        for i = 1, #units do
            local unit = units[i]   ---@type rtu_unit_registry_entry

            if unit.type ~= nil then
                local advert = { unit.type, unit.index, unit.reactor }

                if unit.type == RTU_UNIT_TYPE.REDSTONE then
                    insert(advert, unit.device)
                end

                insert(advertisement, advert)
            end
        end

        return advertisement
    end

    -- PUBLIC FUNCTIONS --

    ---@class rtu_comms
    local public = {}

    -- send a MODBUS TCP packet
    ---@param m_pkt modbus_packet
    function public.send_modbus(m_pkt)
        local s_pkt = comms.scada_packet()
        s_pkt.make(self.seq_num, PROTOCOL.MODBUS_TCP, m_pkt.raw_sendable())
        modem.transmit(server_port, local_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- reconnect a newly connected modem
    ---@param new_modem table
    function public.reconnect_modem(new_modem)
        modem = new_modem
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
        conn_watchdog.cancel()
        public.unlink(rtu_state)
        _send(SCADA_MGMT_TYPE.CLOSE, {})
    end

    -- send establish request (includes advertisement)
    ---@param units table
    function public.send_establish(units)
        _send(SCADA_MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.RTU, _generate_advertisement(units) })
    end

    -- send capability advertisement
    ---@param units table
    function public.send_advertisement(units)
        _send(SCADA_MGMT_TYPE.RTU_ADVERT, _generate_advertisement(units))
    end

    -- notify that a peripheral was remounted
    ---@param unit_index integer RTU unit ID
    function public.send_remounted(unit_index)
        _send(SCADA_MGMT_TYPE.RTU_DEV_REMOUNT, { unit_index })
    end

    -- parse a MODBUS/SCADA packet
    ---@nodiscard
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
            if s_pkt.protocol() == PROTOCOL.MODBUS_TCP then
                local m_pkt = comms.modbus_packet()
                if m_pkt.decode(s_pkt) then
                    pkt = m_pkt.get()
                end
            -- get as SCADA management packet
            elseif s_pkt.protocol() == PROTOCOL.SCADA_MGMT then
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
    ---@param units table RTU units
    ---@param rtu_state rtu_state
    function public.handle_packet(packet, units, rtu_state)
        if packet.scada_frame.local_port() == local_port then
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
            conn_watchdog.feed()

            local protocol = packet.scada_frame.protocol()

            if protocol == PROTOCOL.MODBUS_TCP then
                ---@cast packet modbus_frame
                if rtu_state.linked then
                    local return_code   ---@type boolean
                    local reply         ---@type modbus_packet

                    -- handle MODBUS instruction
                    if packet.unit_id <= #units then
                        local unit = units[packet.unit_id]  ---@type rtu_unit_registry_entry
                        local unit_dbg_tag = " (unit " .. packet.unit_id .. ")"

                        if unit.name == "redstone_io" then
                            -- immediately execute redstone RTU requests
                            return_code, reply = unit.modbus_io.handle_packet(packet)
                            if not return_code then
                                log.warning("requested MODBUS operation failed" .. unit_dbg_tag)
                            end
                        else
                            -- check validity then pass off to unit comms thread
                            return_code, reply = unit.modbus_io.check_request(packet)
                            if return_code then
                                -- check if there are more than 3 active transactions
                                -- still queue the packet, but this may indicate a problem
                                if unit.pkt_queue.length() > 3 then
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
                        reply = modbus.reply__gw_unavailable(packet)
                        log.error("received MODBUS packet for non-existent unit")
                    end

                    public.send_modbus(reply)
                else
                    log.debug("discarding MODBUS packet before linked")
                end
            elseif protocol == PROTOCOL.SCADA_MGMT then
                ---@cast packet mgmt_frame
                -- SCADA management packet
                if packet.type == SCADA_MGMT_TYPE.ESTABLISH then
                    if packet.length == 1 then
                        local est_ack = packet.data[1]

                        if est_ack == ESTABLISH_ACK.ALLOW then
                            -- establish allowed
                            rtu_state.linked = true
                            self.r_seq_num = nil
                            println_ts("supervisor connection established")
                            log.info("supervisor connection established")
                        else
                            -- establish denied
                            if est_ack ~= self.last_est_ack then
                                if est_ack == ESTABLISH_ACK.BAD_VERSION then
                                    -- version mismatch
                                    println_ts("supervisor comms version mismatch (try updating), retrying...")
                                    log.warning("supervisor connection denied due to comms version mismatch, retrying")
                                else
                                    println_ts("supervisor connection denied, retrying...")
                                    log.warning("supervisor connection denied, retrying")
                                end
                            end

                            public.unlink(rtu_state)
                        end

                        self.last_est_ack = est_ack
                    else
                        log.debug("SCADA_MGMT establish packet length mismatch")
                    end
                elseif rtu_state.linked then
                    if packet.type == SCADA_MGMT_TYPE.KEEP_ALIVE then
                        -- keep alive request received, echo back
                        if packet.length == 1 and type(packet.data[1]) == "number" then
                            local timestamp = packet.data[1]
                            local trip_time = util.time() - timestamp

                            if trip_time > 750 then
                                log.warning("RTU KEEP_ALIVE trip time > 750ms (" .. trip_time .. "ms)")
                            end

                            -- log.debug("RTU RTT = " .. trip_time .. "ms")

                            _send_keep_alive_ack(timestamp)
                        else
                            log.debug("SCADA_MGMT keep alive packet length/type mismatch")
                        end
                    elseif packet.type == SCADA_MGMT_TYPE.CLOSE then
                        -- close connection
                        conn_watchdog.cancel()
                        public.unlink(rtu_state)
                        println_ts("server connection closed by remote host")
                        log.warning("server connection closed by remote host")
                    elseif packet.type == SCADA_MGMT_TYPE.RTU_ADVERT then
                        -- request for capabilities again
                        public.send_advertisement(units)
                    else
                        -- not supported
                        log.warning("received unsupported SCADA_MGMT message type " .. packet.type)
                    end
                else
                    log.debug("discarding non-link SCADA_MGMT packet before linked")
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
