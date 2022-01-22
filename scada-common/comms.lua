PROTOCOLS = {
    MODBUS_TCP = 0, -- our "modbus tcp"-esque protocol
    RPLC = 1,       -- reactor plc protocol
    SCADA_MGMT = 2, -- SCADA supervisor intercommunication
    COORD_DATA = 3  -- data packets for coordinators to/from supervisory controller
}

RPLC_TYPES = {
    KEEP_ALIVE = 0,     -- keep alive packets
    LINK_REQ = 1,       -- linking requests
    STATUS = 2,         -- reactor/system status
    MEK_STRUCT = 3,     -- mekanism build structure
    RS_IO_CONNS = 4,    -- redstone I/O connections
    RS_IO_SET = 5,      -- set redstone outputs
    RS_IO_GET = 6,      -- get redstone inputs
    MEK_SCRAM = 7,      -- SCRAM reactor
    MEK_ENABLE = 8,     -- enable reactor
    MEK_BURN_RATE = 9,  -- set burn rate
    ISS_ALARM = 10,     -- ISS alarm broadcast
    ISS_GET = 11,       -- get ISS status
    ISS_CLEAR = 12      -- clear ISS trip (if in bad state, will trip immideatly)
}

RPLC_LINKING = {
    ALLOW = 0,
    DENY = 1,
    COLLISION = 2
}

-- generic SCADA packet object
function scada_packet()
    local self = {
        modem_msg_in = nil,
        valid = false,
        seq_id = nil,
        protocol = nil,
        length = nil,
        raw = nil
    }

    local make = function (seq_id, protocol, payload)
        self.valid = true
        self.seq_id = seq_id
        self.protocol = protocol
        self.length = #payload
        self.raw = { self.seq_id, self.protocol, self.length, payload }
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
            self.seq_id = self.raw[1]
            self.protocol = self.raw[2]
            self.length = self.raw[3]
        end
    end

    local seq_id = function (packet)
        return self.seq_id
    end

    local protocol = function (packet)
        return self.protocol
    end

    local length = function (packet)
        return self.length
    end

    local data = function (packet)
        local subset = nil
        if self.valid then
            subset = { table.unpack(self.raw, 4, 3 + self.length) }
        end
        return subset
    end

    local raw = function (packet)
        return self.raw
    end

    local modem_event = function (packet)
        return self.modem_msg_in
    end

    local as_rplc = function ()
        local pkt = nil
        if self.valid and self.protocol == PROTOCOLS.RPLC then
            local body = data()
            if #body > 2 then
                pkt = {
                    id = body[1],
                    type = body[2],
                    length = #body - 2,
                    body = { table.unpack(body, 3, 2 + #body) }
                }
            end
        end
        return pkt
    end

    return {
        make = make,
        receive = receive,
        seq_id = seq_id,
        protocol = protocol,
        length = length,
        raw = raw,
        modem_event = modem_event
    }
end

-- coordinator communications
function coord_comms()
    local self = {
        reactor_struct_cache = nil
    }
end

-- supervisory controller communications
function superv_comms()
    local self = {
        reactor_struct_cache = nil
    }
end

-- reactor PLC communications
function rplc_comms(id, modem, local_port, server_port, reactor)
    local self = {
        id = id,
        seq_id = 0,
        modem = modem,
        s_port = server_port,
        l_port = local_port,
        reactor = reactor,
        status_cache = nil
    }

    -- PRIVATE FUNCTIONS --

    local _send = function (msg)
        local packet = scada_packet()
        packet.make(self.seq_id, PROTOCOLS.RPLC, msg)
        self.modem.transmit(self.s_port, self.l_port, packet.raw())
        self.seq_id = self.seq_id + 1
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

    -- attempt to establish link with supervisor
    local send_link_req = function ()
        local linking_data = {
            id = self.id,
            type = RPLC_TYPES.LINK_REQ
        }

        _send(linking_data)
    end

    -- send structure properties (these should not change)
    -- server will cache these
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
    -- control_state: acknowledged control state from supervisor
    -- overridden: if ISS force disabled reactor
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

    local send_rs_io_conns = function ()
    end

    local handle_link = function (packet)
        if packet.type == RPLC_TYPES.LINK_REQ then
            return packet.data[1] == RPLC_LINKING.ALLOW
        else
            return nil
        end
    end

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

    return {
        send_link_req = send_link_req,
        send_struct = send_struct,
        send_status = send_status,
        send_rs_io_conns = send_rs_io_conns,
        handle_link = handle_link
    }
end
