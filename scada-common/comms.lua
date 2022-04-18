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

function mgmt_packet()
    local self = {
        frame = nil,
        type = nil,
        length = nil,
        data = nil
    }

    local _scada_type_valid = function ()
        return self.type == SCADA_MGMT_TYPES.PING or
                self.type == SCADA_MGMT_TYPES.SV_HEARTBEAT or
                self.type == SCADA_MGMT_TYPES.REMOTE_LINKED or
                self.type == SCADA_MGMT_TYPES.RTU_ADVERT or
                self.type == SCADA_MGMT_TYPES.RTU_HEARTBEAT
    end

    -- make a SCADA management packet
    local make = function (packet_type, length, data)
        self.type = packet_type
        self.length = length
        self.data = data
    end

    -- decode a SCADA management packet from a SCADA frame
    local decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == comms.PROTOCOLS.SCADA_MGMT then
                local data = frame.data()
                local ok = #data > 1
    
                if ok then
                    make(data[1], data[2], { table.unpack(data, 3, #data) })
                    ok = _scada_type_valid()
                end
    
                return ok
            else
                log._debug("attempted SCADA_MGMT parse of incorrect protocol " .. frame.protocol(), true)
                return false    
            end
        else
            log._debug("nil frame encountered", true)
            return false
        end
    end

    local get = function ()
        return {
            scada_frame = self.frame,
            type = self.type,
            length = self.length,
            data = self.data
        }
    end

    return {
        make = make,
        decode = decode,
        get = get
    }
end
