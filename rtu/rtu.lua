local comms = require("scada-common.comms")
local ppm = require("scada-common.ppm")
local types = require("scada-common.types")

local modbus = require("modbus")

local rtu = {}

local rtu_t = types.rtu_t

local PROTOCOLS = comms.PROTOCOLS
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES
local RTU_ADVERT_TYPES = comms.RTU_ADVERT_TYPES

rtu.init_unit = function ()
    local self = {
        discrete_inputs = {},
        coils = {},
        input_regs = {},
        holding_regs = {},
        io_count_cache = { 0, 0, 0, 0 }
    }

    local insert = table.insert

    local _count_io = function ()
        self.io_count_cache = { #self.discrete_inputs, #self.coils, #self.input_regs, #self.holding_regs }
    end

    -- return : IO count table
    local io_count = function ()
        return self.io_count_cache[0], self.io_count_cache[1], self.io_count_cache[2], self.io_count_cache[3]
    end

    -- discrete inputs: single bit read-only

    -- return : count of discrete inputs
    local connect_di = function (f)
        insert(self.discrete_inputs, f)
        _count_io()
        return #self.discrete_inputs
    end

    -- return : value, access fault
    local read_di = function (di_addr)
        ppm.clear_fault()
        local value = self.discrete_inputs[di_addr]()
        return value, ppm.is_faulted()
    end

    -- coils: single bit read-write

    -- return : count of coils
    local connect_coil = function (f_read, f_write)
        insert(self.coils, { read = f_read, write = f_write })
        _count_io()
        return #self.coils
    end

    -- return : value, access fault
    local read_coil = function (coil_addr)
        ppm.clear_fault()
        local value = self.coils[coil_addr].read()
        return value, ppm.is_faulted()
    end

    -- return : access fault
    local write_coil = function (coil_addr, value)
        ppm.clear_fault()
        self.coils[coil_addr].write(value)
        return ppm.is_faulted()
    end

    -- input registers: multi-bit read-only

    -- return : count of input registers
    local connect_input_reg = function (f)
        insert(self.input_regs, f)
        _count_io()
        return #self.input_regs
    end

    -- return : value, access fault
    local read_input_reg = function (reg_addr)
        ppm.clear_fault()
        local value = self.coils[reg_addr]()
        return value, ppm.is_faulted()
    end

    -- holding registers: multi-bit read-write

    -- return : count of holding registers
    local connect_holding_reg = function (f_read, f_write)
        insert(self.holding_regs, { read = f_read, write = f_write })
        _count_io()
        return #self.holding_regs
    end

    -- return : value, access fault
    local read_holding_reg = function (reg_addr)
        ppm.clear_fault()
        local value = self.coils[reg_addr].read()
        return value, ppm.is_faulted()
    end

    -- return : access fault
    local write_holding_reg = function (reg_addr, value)
        ppm.clear_fault()
        self.coils[reg_addr].write(value)
        return ppm.is_faulted()
    end

    return {
        io_count = io_count,
        connect_di = connect_di,
        read_di = read_di,
        connect_coil = connect_coil,
        read_coil = read_coil,
        write_coil = write_coil,
        connect_input_reg = connect_input_reg,
        read_input_reg = read_input_reg,
        connect_holding_reg = connect_holding_reg,
        read_holding_reg = read_holding_reg,
        write_holding_reg = write_holding_reg
    }
end

rtu.comms = function (modem, local_port, server_port)
    local self = {
        seq_num = 0,
        r_seq_num = nil,
        txn_id = 0,
        modem = modem,
        s_port = server_port,
        l_port = local_port
    }

    -- open modem
    if not self.modem.isOpen(self.l_port) then
        self.modem.open(self.l_port)
    end

    -- PRIVATE FUNCTIONS --

    local _send = function (msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.SCADA_MGMT, m_pkt.raw_sendable())

        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- PUBLIC FUNCTIONS --

    -- reconnect a newly connected modem
    local reconnect_modem = function (modem)
        self.modem = modem

        -- open modem
        if not self.modem.isOpen(self.l_port) then
            self.modem.open(self.l_port)
        end
    end

    -- send a MODBUS TCP packet
    local send_modbus = function (m_pkt)
        local s_pkt = comms.scada_packet()
        s_pkt.make(self.seq_num, PROTOCOLS.MODBUS_TCP, m_pkt.raw_sendable())
        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- parse a MODBUS/SCADA packet
    local parse_packet = function(side, sender, reply_to, message, distance)
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
    local handle_packet = function(packet, units, rtu_state, conn_watchdog)
        if packet ~= nil then
            local seq_ok = true

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

            if protocol == PROTOCOLS.MODBUS_TCP then
                local reply = modbus.reply__neg_ack(packet)

                -- handle MODBUS instruction
                if packet.unit_id <= #units then
                    local unit = units[packet.unit_id]
                    if unit.name == "redstone_io" then
                        -- immediately execute redstone RTU requests
                        local return_code, reply = unit.modbus_io.handle_packet(packet)
                        if not return_code then
                            log.warning("requested MODBUS operation failed")
                        end
                    else
                        -- check validity then pass off to unit comms thread
                        local return_code, reply = unit.modbus_io.check_request(packet)
                        if return_code then
                            -- check if an operation is already in progress for this unit
                            if unit.modbus_busy then
                                reply = unit.modbus_io.reply__srv_device_busy(packet)
                            else
                                unit.pkt_queue.push(packet)
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

                send_modbus(reply)
            elseif protocol == PROTOCOLS.SCADA_MGMT then
                -- SCADA management packet
                if packet.type == SCADA_MGMT_TYPES.CLOSE then
                    -- close connection
                    conn_watchdog.cancel()
                    unlink(rtu_state)
                elseif packet.type == SCADA_MGMT_TYPES.REMOTE_LINKED then
                    -- acknowledgement
                    rtu_state.linked = true
                    self.r_seq_num = nil
                elseif packet.type == SCADA_MGMT_TYPES.RTU_ADVERT then
                    -- request for capabilities again
                    send_advertisement(units)
                else
                    -- not supported
                    log.warning("RTU got unexpected SCADA message type " .. packet.type, true)
                end
            else
                -- should be unreachable assuming packet is from parse_packet()
                log.error("illegal packet type " .. protocol, true)
            end
        end
    end

    -- send capability advertisement
    local send_advertisement = function (units)
        local advertisement = {}

        for i = 1, #units do
            local unit = units[i]
            local type = comms.rtu_t_to_advert_type(unit.type)

            if type ~= nil then
                if type == RTU_ADVERT_TYPES.REDSTONE then
                    insert(advertisement, {
                        type = type,
                        index = unit.index,
                        reactor = unit.for_reactor,
                        rsio = unit.device
                    })
                else
                    insert(advertisement, {
                        type = type,
                        index = unit.index,
                        reactor = unit.for_reactor,
                        rsio = nil
                    })
                end
            end
        end

        _send(SCADA_MGMT_TYPES.RTU_ADVERT, advertisement)
    end

    local send_heartbeat = function ()
        _send(SCADA_MGMT_TYPES.RTU_HEARTBEAT, {})
    end

    local unlink = function (rtu_state)
        rtu_state.linked = false
        self.r_seq_num = nil
    end

    local close = function (rtu_state)
        unlink(rtu_state)
        _send(SCADA_MGMT_TYPES.CLOSE, {})
    end

    return {
        send_modbus = send_modbus,
        reconnect_modem = reconnect_modem,
        parse_packet = parse_packet,
        handle_packet = handle_packet,
        send_advertisement = send_advertisement,
        send_heartbeat = send_heartbeat,
        unlink = unlink,
        close = close
    }
end

return rtu
