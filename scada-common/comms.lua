-- #REQUIRES modbus.lua

PROTOCOLS = {
    MODBUS_TCP = 0,     -- our "MODBUS TCP"-esque protocol
    RPLC = 1,           -- reactor PLC protocol
    SCADA_MGMT = 2,     -- SCADA supervisor intercommunication, device advertisements, etc
    COORD_DATA = 3      -- data packets for coordinators to/from supervisory controller
}

SCADA_SV_MODES = {
    ACTIVE = 0,         -- supervisor running as primary
    BACKUP = 1          -- supervisor running as hot backup
}

RPLC_TYPES = {
    KEEP_ALIVE = 0,     -- keep alive packets
    LINK_REQ = 1,       -- linking requests
    STATUS = 2,         -- reactor/system status
    MEK_STRUCT = 3,     -- mekanism build structure
    MEK_SCRAM = 4,      -- SCRAM reactor
    MEK_ENABLE = 5,     -- enable reactor
    MEK_BURN_RATE = 6,  -- set burn rate
    ISS_ALARM = 7,      -- ISS alarm broadcast
    ISS_GET = 8,        -- get ISS status
    ISS_CLEAR = 9       -- clear ISS trip (if in bad state, will trip immediately)
}

RPLC_LINKING = {
    ALLOW = 0,          -- link approved
    DENY = 1,           -- link denied
    COLLISION = 2       -- link denied due to existing active link
}

SCADA_MGMT_TYPES = {
    PING = 0,           -- generic ping
    SV_HEARTBEAT = 1,   -- supervisor heartbeat
    REMOTE_LINKED = 2,  -- remote device linked
    RTU_ADVERT = 3,     -- RTU capability advertisement
    RTU_HEARTBEAT = 4,  -- RTU heartbeat
}

RTU_ADVERT_TYPES = {
    BOILER = 0,         -- boiler
    TURBINE = 1,        -- turbine
    IMATRIX = 2,        -- induction matrix
    REDSTONE = 3        -- redstone I/O
}

-- generic SCADA packet object
function scada_packet()
    local self = {
        modem_msg_in = nil,
        valid = false,
        seq_num = nil,
        protocol = nil,
        length = nil,
        raw = nil
    }

    local make = function (seq_num, protocol, payload)
        self.valid = true
        self.seq_num = seq_num
        self.protocol = protocol
        self.length = #payload
        self.raw = { self.seq_num, self.protocol, self.length, payload }
    end

    local receive = function (side, sender, reply_to, message, distance)
        self.modem_msg_in = {
            iface = side,
            s_port = sender,
            r_port = reply_to,
            msg = message,
            dist = distance
        }

        self.raw = self.modem_msg_in.msg

        if #self.raw < 3 then
            -- malformed
            return false
        else
            self.valid = true
            self.seq_num = self.raw[1]
            self.protocol = self.raw[2]
            self.length = self.raw[3]
        end
    end

    local modem_event = function () return self.modem_msg_in end
    local raw = function () return self.raw end

    local is_valid = function () return self.valid end

    local seq_num = function () return self.seq_num  end
    local protocol = function () return self.protocol end
    local length = function () return self.length end

    local data = function ()
        local subset = nil
        if self.valid then
            subset = { table.unpack(self.raw, 4, 3 + self.length) }
        end
        return subset
    end

    return {
        make = make,
        receive = receive,
        modem_event = modem_event,
        raw = raw,
        is_valid = is_valid,
        seq_num = seq_num,
        protocol = protocol,
        length = length,
        data = data
    }
end

-- coordinator communications
function coord_comms()
    local self = {
        reactor_struct_cache = nil
    }
end

-- supervisory controller communications
function superv_comms(mode, num_reactors, modem, dev_listen, fo_channel, sv_channel)
    local self = {
        mode = mode,
        seq_num = 0,
        num_reactors = num_reactors,
        modem = modem,
        dev_listen = dev_listen,
        fo_channel = fo_channel,
        sv_channel = sv_channel,
        reactor_struct_cache = nil
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

-- reactor PLC communications
function rplc_comms(id, modem, local_port, server_port, reactor)
    local self = {
        id = id,
        seq_num = 0,
        modem = modem,
        s_port = server_port,
        l_port = local_port,
        reactor = reactor,
        status_cache = nil
    }

    -- PRIVATE FUNCTIONS --

    local _send = function (msg)
        local packet = scada_packet()
        packet.make(self.seq_num, PROTOCOLS.RPLC, msg)
        self.modem.transmit(self.s_port, self.l_port, packet.raw())
        self.seq_num = self.seq_num + 1
    end

    -- variable reactor status information, excluding heating rate
    local _reactor_status = function ()
        return {
            status     = self.reactor.getStatus(),
            burn_rate  = self.reactor.getBurnRate(),
            act_burn_r = self.reactor.getActualBurnRate(),
            temp       = self.reactor.getTemperature(),
            damage     = self.reactor.getDamagePercent(),
            boil_eff   = self.reactor.getBoilEfficiency(),
            env_loss   = self.reactor.getEnvironmentalLoss(),

            fuel       = self.reactor.getFuel(),
            fuel_need  = self.reactor.getFuelNeeded(),
            fuel_fill  = self.reactor.getFuelFilledPercentage(),
            waste      = self.reactor.getWaste(),
            waste_need = self.reactor.getWasteNeeded(),
            waste_fill = self.reactor.getWasteFilledPercentage(),
            cool_type  = self.reactor.getCoolant()['name'],
            cool_amnt  = self.reactor.getCoolant()['amount'],
            cool_need  = self.reactor.getCoolantNeeded(),
            cool_fill  = self.reactor.getCoolantFilledPercentage(),
            hcool_type = self.reactor.getHeatedCoolant()['name'],
            hcool_amnt = self.reactor.getHeatedCoolant()['amount'],
            hcool_need = self.reactor.getHeatedCoolantNeeded(),
            hcool_fill = self.reactor.getHeatedCoolantFilledPercentage()
        }
    end

    local _update_status_cache = function ()
        local status = _reactor_status()
        local changed = false

        for key, value in pairs(status) do
            if value ~= self.status_cache[key] then
                changed = true
                break
            end
        end

        if changed then
            self.status_cache = status
        end

        return changed
    end

    -- PUBLIC FUNCTIONS --

    -- parse an RPLC packet
    local parse_packet = function(side, sender, reply_to, message, distance)
        local pkt = nil
        local s_pkt = scada_packet()

        -- parse packet as generic SCADA packet
        s_pkt.recieve(side, sender, reply_to, message, distance)

        -- get using RPLC protocol format
        if s_pkt.is_valid() and s_pkt.protocol() == PROTOCOLS.RPLC then
            local body = s_pkt.data()
            if #body > 2 then
                pkt = {
                    scada_frame = s_pkt,
                    id = body[1],
                    type = body[2],
                    length = #body - 2,
                    body = { table.unpack(body, 3, 2 + #body) }
                }
            end
        end

        return pkt
    end

    -- handle a linking packet
    local handle_link = function (packet)
        if packet.type == RPLC_TYPES.LINK_REQ then
            return packet.data[1] == RPLC_LINKING.ALLOW
        else
            return nil
        end
    end

    -- handle an RPLC packet
    local handle_packet = function (packet)
        if packet.type == RPLC_TYPES.KEEP_ALIVE then
            -- keep alive request received, nothing to do except feed watchdog
        elseif packet.type == RPLC_TYPES.MEK_STRUCT then
            -- request for physical structure
            send_struct()
        elseif packet.type == RPLC_TYPES.RS_IO_CONNS then
            -- request for redstone connections
            send_rs_io_conns()
        elseif packet.type == RPLC_TYPES.RS_IO_GET then
        elseif packet.type == RPLC_TYPES.RS_IO_SET then
        elseif packet.type == RPLC_TYPES.MEK_SCRAM then
        elseif packet.type == RPLC_TYPES.MEK_ENABLE then
        elseif packet.type == RPLC_TYPES.MEK_BURN_RATE then
        elseif packet.type == RPLC_TYPES.ISS_GET then
        elseif packet.type == RPLC_TYPES.ISS_CLEAR then
        end
    end

    -- attempt to establish link with supervisor
    local send_link_req = function ()
        local linking_data = {
            id = self.id,
            type = RPLC_TYPES.LINK_REQ
        }

        _send(linking_data)
    end

    -- send structure properties (these should not change)
    -- (server will cache these)
    local send_struct = function ()
        local mek_data = {
            heat_cap  = self.reactor.getHeatCapacity(),
            fuel_asm  = self.reactor.getFuelAssemblies(),
            fuel_sa   = self.reactor.getFuelSurfaceArea(),
            fuel_cap  = self.reactor.getFuelCapacity(),
            waste_cap = self.reactor.getWasteCapacity(),
            cool_cap  = self.reactor.getCoolantCapacity(),
            hcool_cap = self.reactor.getHeatedCoolantCapacity(),
            max_burn  = self.reactor.getMaxBurnRate()
        }

        local struct_packet = {
            id = self.id,
            type = RPLC_TYPES.MEK_STRUCT,
            mek_data = mek_data
        }

        _send(struct_packet)
    end

    -- send live status information
    -- control_state : acknowledged control state from supervisor
    -- overridden    : if ISS force disabled reactor
    local send_status = function (control_state, overridden)
        local mek_data = nil

        if _update_status_cache() then
            mek_data = self.status_cache
        end

        local sys_status = {
            id = self.id,
            type = RPLC_TYPES.STATUS,
            timestamp = os.time(),
            control_state = control_state,
            overridden = overridden,
            heating_rate = self.reactor.getHeatingRate(),
            mek_data = mek_data
        }

        _send(sys_status)
    end

    return {
        parse_packet = parse_packet,
        handle_link = handle_link,
        handle_packet = handle_packet,
        send_link_req = send_link_req,
        send_struct = send_struct,
        send_status = send_status
    }
end
