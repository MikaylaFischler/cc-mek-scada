--
-- Communications
--

local comms = {}

local PROTOCOLS = {
    MODBUS_TCP = 0,     -- our "MODBUS TCP"-esque protocol
    RPLC = 1,           -- reactor PLC protocol
    SCADA_MGMT = 2,     -- SCADA supervisor management, device advertisements, etc
    COORD_DATA = 3,     -- data/control packets for coordinators to/from supervisory controllers
    COORD_API = 4       -- data/control packets for pocket computers to/from coordinators
}

local RPLC_TYPES = {
    KEEP_ALIVE = 0,     -- keep alive packets
    LINK_REQ = 1,       -- linking requests
    STATUS = 2,         -- reactor/system status
    MEK_STRUCT = 3,     -- mekanism build structure
    MEK_SCRAM = 4,      -- SCRAM reactor
    MEK_ENABLE = 5,     -- enable reactor
    MEK_BURN_RATE = 6,  -- set burn rate
    RPS_STATUS = 7,     -- RPS status
    RPS_ALARM = 8,      -- RPS alarm broadcast
    RPS_RESET = 9       -- clear RPS trip (if in bad state, will trip immediately)
}

local RPLC_LINKING = {
    ALLOW = 0,          -- link approved
    DENY = 1,           -- link denied
    COLLISION = 2       -- link denied due to existing active link
}

local SCADA_MGMT_TYPES = {
    PING = 0,           -- generic ping
    CLOSE = 1,          -- close a connection
    REMOTE_LINKED = 2,  -- remote device linked
    RTU_ADVERT = 3,     -- RTU capability advertisement
    RTU_HEARTBEAT = 4   -- RTU heartbeat
}

local RTU_ADVERT_TYPES = {
    BOILER = 0,         -- boiler
    TURBINE = 1,        -- turbine
    IMATRIX = 2,        -- induction matrix
    REDSTONE = 3        -- redstone I/O
}

comms.PROTOCOLS = PROTOCOLS
comms.RPLC_TYPES = RPLC_TYPES
comms.RPLC_LINKING = RPLC_LINKING
comms.SCADA_MGMT_TYPES = SCADA_MGMT_TYPES
comms.RTU_ADVERT_TYPES = RTU_ADVERT_TYPES

-- generic SCADA packet object
comms.scada_packet = function ()
    local self = {
        modem_msg_in = nil,
        valid = false,
        raw = nil,
        seq_num = nil,
        protocol = nil,
        length = nil,
        payload = nil
    }

    -- make a SCADA packet
    local make = function (seq_num, protocol, payload)
        self.valid = true
        self.seq_num = seq_num
        self.protocol = protocol
        self.length = #payload
        self.payload = payload
        self.raw = { self.seq_num, self.protocol, self.payload }
    end

    -- parse in a modem message as a SCADA packet
    local receive = function (side, sender, reply_to, message, distance)
        self.modem_msg_in = {
            iface = side,
            s_port = sender,
            r_port = reply_to,
            msg = message,
            dist = distance
        }

        self.raw = self.modem_msg_in.msg

        if type(self.raw) == "table" then
            if #self.raw >= 3 then
                self.valid = true
                self.seq_num = self.raw[1]
                self.protocol = self.raw[2]
                self.length = #self.raw[3]
                self.payload = self.raw[3]
            end
        end

        return self.valid
    end

    -- public accessors --

    local modem_event = function () return self.modem_msg_in end
    local raw_sendable = function () return self.raw end

    local local_port = function () return self.modem_msg_in.s_port end
    local remote_port = function () return self.modem_msg_in.r_port end

    local is_valid = function () return self.valid end

    local seq_num = function () return self.seq_num end
    local protocol = function () return self.protocol end
    local length = function () return self.length end
    local data = function () return self.payload end

    return {
        -- construct
        make = make,
        receive = receive,
        -- raw access
        modem_event = modem_event,
        raw_sendable = raw_sendable,
        -- ports
        local_port = local_port,
        remote_port = remote_port,
        -- well-formed
        is_valid = is_valid,
        -- packet properties
        seq_num = seq_num,
        protocol = protocol,
        length = length,
        data = data
    }
end

-- MODBUS packet 
-- modeled after MODBUS TCP packet
comms.modbus_packet = function ()
    local self = {
        frame = nil,
        raw = nil,
        txn_id = txn_id,
        length = length,
        unit_id = unit_id,
        func_code = func_code,
        data = data
    }

    -- make a MODBUS packet
    local make = function (txn_id, unit_id, func_code, data)
        self.txn_id = txn_id
        self.length = #data
        self.unit_id = unit_id
        self.func_code = func_code
        self.data = data

        -- populate raw array
        self.raw = { self.txn_id, self.unit_id, self.func_code }
        for i = 1, self.length do
            table.insert(self.raw, data[i])
        end
    end

    -- decode a MODBUS packet from a SCADA frame
    local decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOLS.MODBUS_TCP then
                local size_ok = frame.length() >= 3
    
                if size_ok then
                    local data = frame.data()
                    make(data[1], data[2], data[3], { table.unpack(data, 4, #data) })
                end
    
                return size_ok
            else
                log.debug("attempted MODBUS_TCP parse of incorrect protocol " .. frame.protocol(), true)
                return false
            end
        else
            log.debug("nil frame encountered", true)
            return false
        end
    end

    -- get raw to send
    local raw_sendable = function () return self.raw end

    -- get this packet
    local get = function ()
        return {
            scada_frame = self.frame,
            txn_id = self.txn_id,
            length = self.length,
            unit_id = self.unit_id,
            func_code = self.func_code,
            data = self.data
        }
    end

    return {
        -- construct
        make = make,
        decode = decode,
        -- raw access
        raw_sendable = raw_sendable,
        -- formatted access
        get = get
    }
end

-- reactor PLC packet
comms.rplc_packet = function ()
    local self = {
        frame = nil,
        raw = nil,
        id = nil,
        type = nil,
        length = nil,
        body = nil
    }

    -- check that type is known
    local _rplc_type_valid = function ()
        return self.type == RPLC_TYPES.KEEP_ALIVE or
                self.type == RPLC_TYPES.LINK_REQ or
                self.type == RPLC_TYPES.STATUS or
                self.type == RPLC_TYPES.MEK_STRUCT or
                self.type == RPLC_TYPES.MEK_SCRAM or
                self.type == RPLC_TYPES.MEK_ENABLE or
                self.type == RPLC_TYPES.MEK_BURN_RATE or
                self.type == RPLC_TYPES.RPS_ALARM or
                self.type == RPLC_TYPES.RPS_STATUS or
                self.type == RPLC_TYPES.RPS_RESET
    end

    -- make an RPLC packet
    local make = function (id, packet_type, data)
        -- packet accessor properties
        self.id = id
        self.type = packet_type
        self.length = #data
        self.data = data

        -- populate raw array
        self.raw = { self.id, self.type }
        for i = 1, #data do
            table.insert(self.raw, data[i])
        end
    end

    -- decode an RPLC packet from a SCADA frame
    local decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOLS.RPLC then
                local ok = frame.length() >= 2

                if ok then
                    local data = frame.data()
                    make(data[1], data[2], { table.unpack(data, 3, #data) })
                    ok = _rplc_type_valid()
                end

                return ok
            else
                log.debug("attempted RPLC parse of incorrect protocol " .. frame.protocol(), true)
                return false
            end
        else
            log.debug("nil frame encountered", true)
            return false
        end
    end

    -- get raw to send
    local raw_sendable = function () return self.raw end

    -- get this packet
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
        -- construct
        make = make,
        decode = decode,
        -- raw access
        raw_sendable = raw_sendable,
        -- formatted access
        get = get
    }
end

-- SCADA management packet
comms.mgmt_packet = function ()
    local self = {
        frame = nil,
        raw = nil,
        type = nil,
        length = nil,
        data = nil
    }

    -- check that type is known
    local _scada_type_valid = function ()
        return self.type == SCADA_MGMT_TYPES.PING or
                self.type == SCADA_MGMT_TYPES.CLOSE or
                self.type == SCADA_MGMT_TYPES.REMOTE_LINKED or
                self.type == SCADA_MGMT_TYPES.RTU_ADVERT or
                self.type == SCADA_MGMT_TYPES.RTU_HEARTBEAT
    end

    -- make a SCADA management packet
    local make = function (packet_type, data)
        -- packet accessor properties
        self.type = packet_type
        self.length = #data
        self.data = data

        -- populate raw array
        self.raw = { self.type }
        for i = 1, #data do
            table.insert(self.raw, data[i])
        end
    end

    -- decode a SCADA management packet from a SCADA frame
    local decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOLS.SCADA_MGMT then
                local ok = frame.length() >= 1
    
                if ok then
                    local data = frame.data()
                    make(data[1], { table.unpack(data, 2, #data) })
                    ok = _scada_type_valid()
                end
    
                return ok
            else
                log.debug("attempted SCADA_MGMT parse of incorrect protocol " .. frame.protocol(), true)
                return false    
            end
        else
            log.debug("nil frame encountered", true)
            return false
        end
    end

    -- get raw to send
    local raw_sendable = function () return self.raw end

    -- get this packet
    local get = function ()
        return {
            scada_frame = self.frame,
            type = self.type,
            length = self.length,
            data = self.data
        }
    end

    return {
        -- construct
        make = make,
        decode = decode,
        -- raw access
        raw_sendable = raw_sendable,
        -- formatted access
        get = get
    }
end

-- SCADA coordinator packet
-- @todo
comms.coord_packet = function ()
    local self = {
        frame = nil,
        raw = nil,
        type = nil,
        length = nil,
        data = nil
    }

    local _coord_type_valid = function ()
        -- @todo
        return false
    end

    -- make a coordinator packet
    local make = function (packet_type, data)
        -- packet accessor properties
        self.type = packet_type
        self.length = #data
        self.data = data

        -- populate raw array
        self.raw = { self.type }
        for i = 1, #data do
            table.insert(self.raw, data[i])
        end
    end

    -- decode a coordinator packet from a SCADA frame
    local decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOLS.COORD_DATA then
                local ok = frame.length() >= 1

                if ok then
                    local data = frame.data()
                    make(data[1], { table.unpack(data, 2, #data) })
                    ok = _coord_type_valid()
                end

                return ok
            else
                log.debug("attempted COORD_DATA parse of incorrect protocol " .. frame.protocol(), true)
                return false
            end
        else
            log.debug("nil frame encountered", true)
            return false
        end
    end

    -- get raw to send
    local raw_sendable = function () return self.raw end

    -- get this packet
    local get = function ()
        return {
            scada_frame = self.frame,
            type = self.type,
            length = self.length,
            data = self.data
        }
    end

    return {
        -- construct
        make = make,
        decode = decode,
        -- raw access
        raw_sendable = raw_sendable,
        -- formatted access
        get = get
    }
end

-- coordinator API (CAPI) packet
-- @todo
comms.capi_packet = function ()
    local self = {
        frame = nil,
        raw = nil,
        type = nil,
        length = nil,
        data = nil
    }

    local _coord_type_valid = function ()
        -- @todo
        return false
    end

    -- make a coordinator packet
    local make = function (packet_type, data)
        -- packet accessor properties
        self.type = packet_type
        self.length = #data
        self.data = data

        -- populate raw array
        self.raw = { self.type }
        for i = 1, #data do
            table.insert(self.raw, data[i])
        end
    end

    -- decode a coordinator packet from a SCADA frame
    local decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOLS.COORD_API then
                local ok = frame.length() >= 1

                if ok then
                    local data = frame.data()
                    make(data[1], { table.unpack(data, 2, #data) })
                    ok = _coord_type_valid()
                end

                return ok
            else
                log.debug("attempted COORD_API parse of incorrect protocol " .. frame.protocol(), true)
                return false
            end
        else
            log.debug("nil frame encountered", true)
            return false
        end
    end

    -- get raw to send
    local raw_sendable = function () return self.raw end

    -- get this packet
    local get = function ()
        return {
            scada_frame = self.frame,
            type = self.type,
            length = self.length,
            data = self.data
        }
    end

    return {
        -- construct
        make = make,
        decode = decode,
        -- raw access
        raw_sendable = raw_sendable,
        -- formatted access
        get = get
    }
end

return comms
