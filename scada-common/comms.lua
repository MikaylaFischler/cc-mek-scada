--
-- Communications
--

local log = require("scada-common.log")
local types = require("scada-common.types")

---@class comms
local comms = {}

local rtu_t = types.rtu_t
local insert = table.insert

---@alias PROTOCOLS integer
local PROTOCOLS = {
    MODBUS_TCP = 0,     -- our "MODBUS TCP"-esque protocol
    RPLC = 1,           -- reactor PLC protocol
    SCADA_MGMT = 2,     -- SCADA supervisor management, device advertisements, etc
    COORD_DATA = 3,     -- data/control packets for coordinators to/from supervisory controllers
    COORD_API = 4       -- data/control packets for pocket computers to/from coordinators
}

---@alias RPLC_TYPES integer
local RPLC_TYPES = {
    LINK_REQ = 0,       -- linking requests
    STATUS = 1,         -- reactor/system status
    MEK_STRUCT = 2,     -- mekanism build structure
    MEK_BURN_RATE = 3,  -- set burn rate
    RPS_ENABLE = 4,     -- enable reactor
    RPS_SCRAM = 5,      -- SCRAM reactor
    RPS_STATUS = 6,     -- RPS status
    RPS_ALARM = 7,      -- RPS alarm broadcast
    RPS_RESET = 8       -- clear RPS trip (if in bad state, will trip immediately)
}

---@alias RPLC_LINKING integer
local RPLC_LINKING = {
    ALLOW = 0,          -- link approved
    DENY = 1,           -- link denied
    COLLISION = 2       -- link denied due to existing active link
}

---@alias SCADA_MGMT_TYPES integer
local SCADA_MGMT_TYPES = {
    KEEP_ALIVE = 0,     -- keep alive packet w/ RTT
    CLOSE = 1,          -- close a connection
    RTU_ADVERT = 2,     -- RTU capability advertisement
    REMOTE_LINKED = 3   -- remote device linked
}

---@alias RTU_UNIT_TYPES integer
local RTU_UNIT_TYPES = {
    REDSTONE = 0,       -- redstone I/O
    BOILER = 1,         -- boiler
    BOILER_VALVE = 2,   -- boiler mekanism 10.1+
    TURBINE = 3,        -- turbine
    TURBINE_VALVE = 4,  -- turbine, mekanism 10.1+
    EMACHINE = 5,       -- energy machine
    IMATRIX = 6         -- induction matrix
}

comms.PROTOCOLS = PROTOCOLS
comms.RPLC_TYPES = RPLC_TYPES
comms.RPLC_LINKING = RPLC_LINKING
comms.SCADA_MGMT_TYPES = SCADA_MGMT_TYPES
comms.RTU_UNIT_TYPES = RTU_UNIT_TYPES

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

    ---@class scada_packet
    local public = {}

    -- make a SCADA packet
    ---@param seq_num integer
    ---@param protocol PROTOCOLS
    ---@param payload table
    public.make = function (seq_num, protocol, payload)
        self.valid = true
        self.seq_num = seq_num
        self.protocol = protocol
        self.length = #payload
        self.payload = payload
        self.raw = { self.seq_num, self.protocol, self.payload }
    end

    -- parse in a modem message as a SCADA packet
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    public.receive = function (side, sender, reply_to, message, distance)
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

    public.modem_event = function () return self.modem_msg_in end
    public.raw_sendable = function () return self.raw end

    public.local_port = function () return self.modem_msg_in.s_port end
    public.remote_port = function () return self.modem_msg_in.r_port end

    public.is_valid = function () return self.valid end

    public.seq_num = function () return self.seq_num end
    public.protocol = function () return self.protocol end
    public.length = function () return self.length end
    public.data = function () return self.payload end

    return public
end

-- MODBUS packet
-- modeled after MODBUS TCP packet
comms.modbus_packet = function ()
    local self = {
        frame = nil,
        raw = nil,
        txn_id = nil,
        length = nil,
        unit_id = nil,
        func_code = nil,
        data = nil
    }

    ---@class modbus_packet
    local public = {}

    -- make a MODBUS packet
    ---@param txn_id integer
    ---@param unit_id integer
    ---@param func_code MODBUS_FCODE
    ---@param data table
    public.make = function (txn_id, unit_id, func_code, data)
        self.txn_id = txn_id
        self.length = #data
        self.unit_id = unit_id
        self.func_code = func_code
        self.data = data

        -- populate raw array
        self.raw = { self.txn_id, self.unit_id, self.func_code }
        for i = 1, self.length do
            insert(self.raw, data[i])
        end
    end

    -- decode a MODBUS packet from a SCADA frame
    ---@param frame scada_packet
    ---@return boolean success
    public.decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOLS.MODBUS_TCP then
                local size_ok = frame.length() >= 3

                if size_ok then
                    local data = frame.data()
                    public.make(data[1], data[2], data[3], { table.unpack(data, 4, #data) })
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
    public.raw_sendable = function () return self.raw end

    -- get this packet as a frame with an immutable relation to this object
    public.get = function ()
        ---@class modbus_frame
        local frame = {
            scada_frame = self.frame,
            txn_id = self.txn_id,
            length = self.length,
            unit_id = self.unit_id,
            func_code = self.func_code,
            data = self.data
        }

        return frame
    end

    return public
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

    ---@class rplc_packet
    local public = {}

    -- check that type is known
    local _rplc_type_valid = function ()
        return self.type == RPLC_TYPES.LINK_REQ or
                self.type == RPLC_TYPES.STATUS or
                self.type == RPLC_TYPES.MEK_STRUCT or
                self.type == RPLC_TYPES.MEK_BURN_RATE or
                self.type == RPLC_TYPES.RPS_ENABLE or
                self.type == RPLC_TYPES.RPS_SCRAM or
                self.type == RPLC_TYPES.RPS_ALARM or
                self.type == RPLC_TYPES.RPS_STATUS or
                self.type == RPLC_TYPES.RPS_RESET
    end

    -- make an RPLC packet
    ---@param id integer
    ---@param packet_type RPLC_TYPES
    ---@param data table
    public.make = function (id, packet_type, data)
        -- packet accessor properties
        self.id = id
        self.type = packet_type
        self.length = #data
        self.data = data

        -- populate raw array
        self.raw = { self.id, self.type }
        for i = 1, #data do
            insert(self.raw, data[i])
        end
    end

    -- decode an RPLC packet from a SCADA frame
    ---@param frame scada_packet
    ---@return boolean success
    public.decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOLS.RPLC then
                local ok = frame.length() >= 2

                if ok then
                    local data = frame.data()
                    public.make(data[1], data[2], { table.unpack(data, 3, #data) })
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
    public.raw_sendable = function () return self.raw end

    -- get this packet as a frame with an immutable relation to this object
    public.get = function ()
        ---@class rplc_frame
        local frame = {
            scada_frame = self.frame,
            id = self.id,
            type = self.type,
            length = self.length,
            data = self.data
        }

        return frame
    end

    return public
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

    ---@class mgmt_packet
    local public = {}

    -- check that type is known
    local _scada_type_valid = function ()
        return self.type == SCADA_MGMT_TYPES.KEEP_ALIVE or
                self.type == SCADA_MGMT_TYPES.CLOSE or
                self.type == SCADA_MGMT_TYPES.REMOTE_LINKED or
                self.type == SCADA_MGMT_TYPES.RTU_ADVERT
    end

    -- make a SCADA management packet
    ---@param packet_type SCADA_MGMT_TYPES
    ---@param data table
    public.make = function (packet_type, data)
        -- packet accessor properties
        self.type = packet_type
        self.length = #data
        self.data = data

        -- populate raw array
        self.raw = { self.type }
        for i = 1, #data do
            insert(self.raw, data[i])
        end
    end

    -- decode a SCADA management packet from a SCADA frame
    ---@param frame scada_packet
    ---@return boolean success
    public.decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOLS.SCADA_MGMT then
                local ok = frame.length() >= 1

                if ok then
                    local data = frame.data()
                    public.make(data[1], { table.unpack(data, 2, #data) })
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
    public.raw_sendable = function () return self.raw end

    -- get this packet as a frame with an immutable relation to this object
    public.get = function ()
        ---@class mgmt_frame
        local frame = {
            scada_frame = self.frame,
            type = self.type,
            length = self.length,
            data = self.data
        }

        return frame
    end

    return public
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

    ---@class coord_packet
    local public = {}

    local _coord_type_valid = function ()
        -- @todo
        return false
    end

    -- make a coordinator packet
    ---@param packet_type any
    ---@param data table
    public.make = function (packet_type, data)
        -- packet accessor properties
        self.type = packet_type
        self.length = #data
        self.data = data

        -- populate raw array
        self.raw = { self.type }
        for i = 1, #data do
            insert(self.raw, data[i])
        end
    end

    -- decode a coordinator packet from a SCADA frame
    ---@param frame scada_packet
    ---@return boolean success
    public.decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOLS.COORD_DATA then
                local ok = frame.length() >= 1

                if ok then
                    local data = frame.data()
                    public.make(data[1], { table.unpack(data, 2, #data) })
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
    public.raw_sendable = function () return self.raw end

    -- get this packet as a frame with an immutable relation to this object
    public.get = function ()
        ---@class coord_frame
        local frame = {
            scada_frame = self.frame,
            type = self.type,
            length = self.length,
            data = self.data
        }

        return frame
    end

    return public
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

    ---@class capi_packet
    local public = {}

    local _coord_type_valid = function ()
        -- @todo
        return false
    end

    -- make a coordinator API packet
    ---@param packet_type any
    ---@param data table
    public.make = function (packet_type, data)
        -- packet accessor properties
        self.type = packet_type
        self.length = #data
        self.data = data

        -- populate raw array
        self.raw = { self.type }
        for i = 1, #data do
            insert(self.raw, data[i])
        end
    end

    -- decode a coordinator API packet from a SCADA frame
    ---@param frame scada_packet
    ---@return boolean success
    public.decode = function (frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOLS.COORD_API then
                local ok = frame.length() >= 1

                if ok then
                    local data = frame.data()
                    public.make(data[1], { table.unpack(data, 2, #data) })
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
    public.raw_sendable = function () return self.raw end

    -- get this packet as a frame with an immutable relation to this object
    public.get = function ()
        ---@class capi_frame
        local frame = {
            scada_frame = self.frame,
            type = self.type,
            length = self.length,
            data = self.data
        }

        return frame
    end

    return public
end

-- convert rtu_t to RTU unit type
---@param type rtu_t
---@return RTU_UNIT_TYPES|nil
comms.rtu_t_to_unit_type = function (type)
    if type == rtu_t.redstone then
        return RTU_UNIT_TYPES.REDSTONE
    elseif type == rtu_t.boiler then
        return RTU_UNIT_TYPES.BOILER
    elseif type == rtu_t.boiler_valve then
        return RTU_UNIT_TYPES.BOILER_VALVE
    elseif type == rtu_t.turbine then
        return RTU_UNIT_TYPES.TURBINE
    elseif type == rtu_t.turbine_valve then
        return RTU_UNIT_TYPES.TURBINE_VALVE
    elseif type == rtu_t.energy_machine then
        return RTU_UNIT_TYPES.EMACHINE
    elseif type == rtu_t.induction_matrix then
        return RTU_UNIT_TYPES.IMATRIX
    end

    return nil
end

-- convert RTU unit type to rtu_t
---@param utype RTU_UNIT_TYPES
---@return rtu_t|nil
comms.advert_type_to_rtu_t = function (utype)
    if utype == RTU_UNIT_TYPES.REDSTONE then
        return rtu_t.redstone
    elseif utype == RTU_UNIT_TYPES.BOILER then
        return rtu_t.boiler
    elseif utype == RTU_UNIT_TYPES.BOILER_VALVE then
        return rtu_t.boiler_valve
    elseif utype == RTU_UNIT_TYPES.TURBINE then
        return rtu_t.turbine
    elseif utype == RTU_UNIT_TYPES.TURBINE_VALVE then
        return rtu_t.turbine_valve
    elseif utype == RTU_UNIT_TYPES.EMACHINE then
        return rtu_t.energy_machine
    elseif utype == RTU_UNIT_TYPES.IMATRIX then
        return rtu_t.induction_matrix
    end

    return nil
end

return comms
