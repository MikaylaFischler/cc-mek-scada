-- #REQUIRES comms.lua
-- #REQUIRES modbus.lua

function rtu_init()
    local self = {
        discrete_inputs = {},
        coils = {},
        input_regs = {},
        holding_regs = {},
        io_count_cache = { 0, 0, 0, 0 }
    }

    local __count_io = function ()
        self.io_count_cache = { #self.discrete_inputs, #self.coils, #self.input_regs, #self.holding_regs }
    end

    local io_count = function ()
        return self.io_count_cache[0], self.io_count_cache[1], self.io_count_cache[2], self.io_count_cache[3]
    end

    -- discrete inputs: single bit read-only

    local connect_di = function (f)
        table.insert(self.discrete_inputs, f)
        __count_io()
        return #self.discrete_inputs
    end

    local read_di = function (di_addr)
        return self.discrete_inputs[di_addr]()
    end

    -- coils: single bit read-write

    local connect_coil = function (f_read, f_write)
        table.insert(self.coils, { read = f_read, write = f_write })
        __count_io()
        return #self.coils
    end

    local read_coil = function (coil_addr)
        return self.coils[coil_addr].read()
    end

    local write_coil = function (coil_addr, value)
        self.coils[coil_addr].write(value)
    end

    -- input registers: multi-bit read-only

    local connect_input_reg = function (f)
        table.insert(self.input_regs, f)
        __count_io()
        return #self.input_regs
    end

    local read_input_reg = function (reg_addr)
        return self.coils[reg_addr]()
    end

    -- holding registers: multi-bit read-write

    local connect_holding_reg = function (f_read, f_write)
        table.insert(self.holding_regs, { read = f_read, write = f_write })
        __count_io()
        return #self.holding_regs
    end

    local read_holding_reg = function (reg_addr)
        return self.coils[reg_addr].read()
    end

    local write_holding_reg = function (reg_addr, value)
        self.coils[reg_addr].write(value)
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

    -- PRIVATE FUNCTIONS --

    local _send = function (protocol, msg)
        local packet = scada_packet()
        packet.make(self.seq_num, protocol, msg)
        self.modem.transmit(self.s_port, self.l_port, packet.raw())
        self.seq_num = self.seq_num + 1
    end

    -- PUBLIC FUNCTIONS --

    -- parse a MODBUS/SCADA packet
    local parse_packet = function(side, sender, reply_to, message, distance)
        local pkt = nil
        local s_pkt = scada_packet()

        -- parse packet as generic SCADA packet
        s_pkt.recieve(side, sender, reply_to, message, distance)

        if s_pkt.is_valid() then
            -- get as MODBUS TCP packet
            if s_pkt.protocol() == PROTOCOLS.MODBUS_TCP then
                local m_pkt = modbus_packet()
                m_pkt.receive(s_pkt.data())

                pkt = {
                    scada_frame = s_pkt,
                    modbus_frame = m_pkt
                }
            -- get as SCADA management packet
            elseif s_pkt.protocol() == PROTOCOLS.SCADA_MGMT then
                local body = s_pkt.data()
                if #body > 1 then
                    pkt = {
                        scada_frame = s_pkt,
                        type = body[1],
                        length = #body - 1,
                        body = { table.unpack(body, 2, 1 + #body) }
                    }
                elseif #body == 1 then
                    pkt = {
                        scada_frame = s_pkt,
                        type = body[1],
                        length = #body - 1,
                        body = nil
                    }
                else
                    log._error("Malformed SCADA packet has no length field")
                end
            else
                log._error("Illegal packet type " .. s_pkt.protocol(), true)
            end
        end

        return pkt
    end

    local handle_packet = function(packet, units, ref)
        if packet ~= nil then
            local protocol = packet.scada_frame.protocol()

            if protocol == PROTOCOLS.MODBUS_TCP then
                -- MODBUS instruction
                if packet.modbus_frame.unit_id <= #units then
                    local return_code, response = units.modbus_io.handle_packet(packet.modbus_frame)
                    _send(response, PROTOCOLS.MODBUS_TCP)

                    if not return_code then
                        log._warning("MODBUS operation failed")
                    end
                else
                    -- unit ID out of range?
                    log._error("MODBUS packet requesting non-existent unit")
                end
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
                log._error("Illegal packet type " .. protocol, true)
            end
        end
    end

    -- send capability advertisement
    local send_advertisement = function (units)
        local advertisement = {
            type = SCADA_MGMT_TYPES.RTU_ADVERT,
            units = {}
        }

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
                    table.insert(advertisement.units, {
                        unit = i,
                        type = type,
                        index = units[i].index,
                        reactor = units[i].for_reactor,
                        rsio = units[i].device
                    })
                else
                    table.insert(advertisement.units, {
                        unit = i,
                        type = type,
                        index = units[i].index,
                        reactor = units[i].for_reactor,
                        rsio = nil
                    })
                end
            end
        end

        _send(advertisement, PROTOCOLS.SCADA_MGMT)
    end

    local send_heartbeat = function ()
        local heartbeat = {
            type = SCADA_MGMT_TYPES.RTU_HEARTBEAT
        }

        _send(heartbeat, PROTOCOLS.SCADA_MGMT)
    end

    return {
        parse_packet = parse_packet,
        handle_packet = handle_packet,
        send_advertisement = send_advertisement,
        send_heartbeat = send_heartbeat
    }
end
