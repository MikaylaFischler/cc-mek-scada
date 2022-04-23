-- #REQUIRES comms.lua
-- #REQUIRES modbus.lua
-- #REQUIRES ppm.lua

local PROTOCOLS = comms.PROTOCOLS
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES
local RTU_ADVERT_TYPES = comms.RTU_ADVERT_TYPES

function rtu_init()
    local self = {
        discrete_inputs = {},
        coils = {},
        input_regs = {},
        holding_regs = {},
        io_count_cache = { 0, 0, 0, 0 }
    }

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
        table.insert(self.discrete_inputs, f)
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
        table.insert(self.coils, { read = f_read, write = f_write })
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
        table.insert(self.input_regs, f)
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
        table.insert(self.holding_regs, { read = f_read, write = f_write })
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

function rtu_comms(modem, local_port, server_port)
    local self = {
        seq_num = 0,
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

    local _send_modbus = function (m_pkt)
        local s_pkt = comms.scada_packet()
        s_pkt.make(self.seq_num, PROTOCOLS.MODBUS_TCP, m_pkt.raw_sendable())
        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- PUBLIC FUNCTIONS --

    -- parse a MODBUS/SCADA packet
    local parse_packet = function(side, sender, reply_to, message, distance)
        local pkt = nil
        local s_pkt = comms.scada_packet()

        -- parse packet as generic SCADA packet
        s_pkt.recieve(side, sender, reply_to, message, distance)

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
                    pkt = mgmt_packet.get()
                end
            else
                log._error("illegal packet type " .. s_pkt.protocol(), true)
            end
        end

        return pkt
    end

    -- handle a MODBUS/SCADA packet
    local handle_packet = function(packet, units, ref)
        if packet ~= nil then
            local protocol = packet.scada_frame.protocol()

            if protocol == PROTOCOLS.MODBUS_TCP then
                local reply = modbus.reply__neg_ack(packet)

                -- MODBUS instruction
                if packet.unit_id <= #units then
                    local unit = units[packet.unit_id]
                    local return_code, reply = unit.modbus_io.handle_packet(packet)

                    if not return_code then
                        log._warning("MODBUS operation failed")
                    end
                else
                    -- unit ID out of range?
                    reply = modbus.reply__gw_unavailable(packet)
                    log._error("MODBUS packet requesting non-existent unit")
                end

                _send_modbus(reply)
            elseif protocol == PROTOCOLS.SCADA_MGMT then
                -- SCADA management packet
                if packet.type == SCADA_MGMT_TYPES.REMOTE_LINKED then
                    -- acknowledgement
                    ref.linked = true
                elseif packet.type == SCADA_MGMT_TYPES.RTU_ADVERT then
                    -- request for capabilities again
                    send_advertisement(units)
                else
                    -- not supported
                    log._warning("RTU got unexpected SCADA message type " .. packet.type, true)
                end
            else
                -- should be unreachable assuming packet is from parse_packet()
                log._error("illegal packet type " .. protocol, true)
            end
        end
    end

    -- send capability advertisement
    local send_advertisement = function (units)
        local advertisement = {}

        for i = 1, #units do
            local type = nil

            if units[i].type == "boiler" then
                type = RTU_ADVERT_TYPES.BOILER
            elseif units[i].type == "turbine" then
                type = RTU_ADVERT_TYPES.TURBINE
            elseif units[i].type == "imatrix" then
                type = RTU_ADVERT_TYPES.IMATRIX
            elseif units[i].type == "redstone" then
                type = RTU_ADVERT_TYPES.REDSTONE
            end

            if type ~= nil then
                if type == RTU_ADVERT_TYPES.REDSTONE then
                    table.insert(advertisement, {
                        unit = i,
                        type = type,
                        index = units[i].index,
                        reactor = units[i].for_reactor,
                        rsio = units[i].device
                    })
                else
                    table.insert(advertisement, {
                        unit = i,
                        type = type,
                        index = units[i].index,
                        reactor = units[i].for_reactor,
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

    return {
        parse_packet = parse_packet,
        handle_packet = handle_packet,
        send_advertisement = send_advertisement,
        send_heartbeat = send_heartbeat
    }
end
