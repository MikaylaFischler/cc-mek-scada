PROTOCOLS = {
    MODBUS_TCP = 0,     -- our "MODBUS TCP"-esque protocol
    RPLC = 1,           -- reactor PLC protocol
    SCADA_MGMT = 2,     -- SCADA supervisor management, device advertisements, etc
    COORD_DATA = 3      -- data packets for coordinators to/from supervisory controller
}

RPLC_TYPES = {
    KEEP_ALIVE = 0,     -- keep alive packets
    LINK_REQ = 1,       -- linking requests
    STATUS = 2,         -- reactor/system status
    MEK_STRUCT = 3,     -- mekanism build structure
    MEK_SCRAM = 4,      -- SCRAM reactor
    MEK_ENABLE = 5,     -- enable reactor
    MEK_BURN_RATE = 6,  -- set burn rate
    ISS_STATUS = 7,     -- ISS status
    ISS_ALARM = 8,      -- ISS alarm broadcast
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

    local sender = function () return self.s_port end
    local receiver = function () return self.r_port end

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
        sender = sender,
        receiver = receiver,
        is_valid = is_valid,
        seq_num = seq_num,
        protocol = protocol,
        length = length,
        data = data
    }
end

-- MODBUS packet
function modbus_packet()
    local self = {
        frame = nil,
        txn_id = txn_id,
        protocol = protocol,
        length = length,
        unit_id = unit_id,
        func_code = func_code,
        data = data
    }

    -- make a MODBUS packet
    local make = function (txn_id, protocol, length, unit_id, func_code, data)
        self.txn_id = txn_id
        self.protocol = protocol
        self.length = length
        self.unit_id = unit_id
        self.func_code = func_code
        self.data = data
    end

    -- decode a MODBUS packet from a SCADA frame
    local decode = function (frame)
        if frame then
            self.frame = frame

            local data = frame.data()
            local size_ok = #data ~= 6

            if size_ok then
                make(data[1], data[2], data[3], data[4], data[5], data[6])
            end

            return size_ok and self.protocol == comms.PROTOCOLS.MODBUS_TCP
        else
            log._debug("nil frame encountered", true)
            return false
        end
    end

    -- get this packet
    local get = function ()
        return {
            scada_frame = self.frame,
            txn_id = self.txn_id,
            protocol = self.protocol,
            length = self.length,
            unit_id = self.unit_id,
            func_code = self.func_code,
            data = self.data
        }
    end

    return {
        make = make,
        decode = decode,
        get = get
    }
end

-- reactor PLC packet
function rplc_packet()
    local self = {
        frame = nil,
        id = nil,
        type = nil,
        length = nil,
        body = nil
    }

    local _rplc_type_valid = function ()
        return self.type == RPLC_TYPES.KEEP_ALIVE or
                self.type == RPLC_TYPES.LINK_REQ or
                self.type == RPLC_TYPES.STATUS or
                self.type == RPLC_TYPES.MEK_STRUCT or
                self.type == RPLC_TYPES.MEK_SCRAM or
                self.type == RPLC_TYPES.MEK_ENABLE or
                self.type == RPLC_TYPES.MEK_BURN_RATE or
                self.type == RPLC_TYPES.ISS_ALARM or
                self.type == RPLC_TYPES.ISS_STATUS or
                self.type == RPLC_TYPES.ISS_CLEAR
    end

    -- make an RPLC packet
    local make = function (id, packet_type, length, data)
        self.id = id
        self.type = packet_type
        self.length = length
        self.data = data
    end

    -- decode an RPLC packet from a SCADA frame
    local decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == comms.PROTOCOLS.RPLC then
                local data = frame.data()
                local ok = #data > 2

                if ok then
                    make(data[1], data[2], data[3], { table.unpack(data, 4, #data) })
                    ok = _rplc_type_valid()
                end

                return ok
            else
                log._debug("attempted RPLC parse of incorrect protocol " .. frame.protocol(), true)
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
            id = self.id,
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

-- SCADA management packet
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

-- SCADA coordinator packet
-- @todo
function coord_packet()
    local self = {
        frame = nil,
        type = nil,
        length = nil,
        data = nil
    }

    local _coord_type_valid = function ()
        -- @todo
        return false
    end

    -- make a coordinator packet
    local make = function (packet_type, length, data)
        self.type = packet_type
        self.length = length
        self.data = data
    end

    -- decode a coordinator packet from a SCADA frame
    local decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == comms.PROTOCOLS.COORD_DATA then
                local data = frame.data()
                local ok = #data > 1

                if ok then
                    make(data[1], data[2], { table.unpack(data, 3, #data) })
                    ok = _coord_type_valid()
                end

                return ok
            else
                log._debug("attempted COORD_DATA parse of incorrect protocol " .. frame.protocol(), true)
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
