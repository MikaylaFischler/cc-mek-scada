--
-- Communications
--

local log = require("scada-common.log")

local insert = table.insert

---@diagnostic disable-next-line: undefined-field
local COMPUTER_ID  = os.getComputerID() ---@type integer computer ID

local max_distance = nil                ---@type number|nil maximum acceptable transmission distance

---@class comms
local comms = {}

comms.version = "2.2.0"

---@enum PROTOCOL
local PROTOCOL = {
    MODBUS_TCP = 0,     -- our "MODBUS TCP"-esque protocol
    RPLC = 1,           -- reactor PLC protocol
    SCADA_MGMT = 2,     -- SCADA supervisor management, device advertisements, etc
    SCADA_CRDN = 3,     -- data/control packets for coordinators to/from supervisory controllers
    COORD_API = 4       -- data/control packets for pocket computers to/from coordinators
}

---@enum RPLC_TYPE
local RPLC_TYPE = {
    STATUS = 0,         -- reactor/system status
    MEK_STRUCT = 1,     -- mekanism build structure
    MEK_BURN_RATE = 2,  -- set burn rate
    RPS_ENABLE = 3,     -- enable reactor
    RPS_SCRAM = 4,      -- SCRAM reactor (manual request)
    RPS_ASCRAM = 5,     -- SCRAM reactor (automatic request)
    RPS_STATUS = 6,     -- RPS status
    RPS_ALARM = 7,      -- RPS alarm broadcast
    RPS_RESET = 8,      -- clear RPS trip (if in bad state, will trip immediately)
    RPS_AUTO_RESET = 9, -- clear RPS trip if it is just a timeout or auto scram
    AUTO_BURN_RATE = 10 -- set an automatic burn rate, PLC will respond with status, enable toggle speed limited
}

---@enum SCADA_MGMT_TYPE
local SCADA_MGMT_TYPE = {
    ESTABLISH = 0,      -- establish new connection
    KEEP_ALIVE = 1,     -- keep alive packet w/ RTT
    CLOSE = 2,          -- close a connection
    RTU_ADVERT = 3,     -- RTU capability advertisement
    RTU_DEV_REMOUNT = 4,-- RTU multiblock possbily changed (formed, unformed) due to PPM remount
    RTU_TONE_ALARM = 5  -- instruct RTUs to play specified alarm tones
}

---@enum SCADA_CRDN_TYPE
local SCADA_CRDN_TYPE = {
    INITIAL_BUILDS = 0, -- initial, complete builds packet to the coordinator
    FAC_BUILDS = 1,     -- facility RTU builds
    FAC_STATUS = 2,     -- state of facility and facility devices
    FAC_CMD = 3,        -- faility command
    UNIT_BUILDS = 4,    -- build of each reactor unit (reactor + RTUs)
    UNIT_STATUSES = 5,  -- state of each of the reactor units
    UNIT_CMD = 6        -- command a reactor unit
}

---@enum CAPI_TYPE
local CAPI_TYPE = {
}

---@enum ESTABLISH_ACK
local ESTABLISH_ACK = {
    ALLOW = 0,          -- link approved
    DENY = 1,           -- link denied
    COLLISION = 2,      -- link denied due to existing active link
    BAD_VERSION = 3     -- link denied due to comms version mismatch
}

---@enum DEVICE_TYPE
local DEVICE_TYPE = {
    PLC = 0,            -- PLC device type for establish
    RTU = 1,            -- RTU device type for establish
    SV = 2,             -- supervisor device type for establish
    CRDN = 3,           -- coordinator device type for establish
    PKT = 4             -- pocket device type for establish
}

---@enum PLC_AUTO_ACK
local PLC_AUTO_ACK = {
    FAIL = 0,           -- failed to set burn rate/burn rate invalid
    DIRECT_SET_OK = 1,  -- successfully set burn rate
    RAMP_SET_OK = 2,    -- successfully started burn rate ramping
    ZERO_DIS_OK = 3     -- successfully disabled reactor with < 0.01 burn rate
}

---@enum FAC_COMMAND
local FAC_COMMAND = {
    SCRAM_ALL = 0,      -- SCRAM all reactors
    STOP = 1,           -- stop automatic process control
    START = 2,          -- start automatic process control
    ACK_ALL_ALARMS = 3, -- acknowledge all alarms on all units
    SET_WASTE_MODE = 4, -- set automatic waste processing mode
    SET_PU_FB = 5       -- set plutonium fallback mode
}

---@enum UNIT_COMMAND
local UNIT_COMMAND = {
    SCRAM = 0,          -- SCRAM the reactor
    START = 1,          -- start the reactor
    RESET_RPS = 2,      -- reset the RPS
    SET_BURN = 3,       -- set the burn rate
    SET_WASTE = 4,      -- set the waste processing mode
    ACK_ALL_ALARMS = 5, -- ack all active alarms
    ACK_ALARM = 6,      -- ack a particular alarm
    RESET_ALARM = 7,    -- reset a particular alarm
    SET_GROUP = 8       -- assign this unit to a group
}

comms.PROTOCOL = PROTOCOL

comms.RPLC_TYPE = RPLC_TYPE
comms.SCADA_MGMT_TYPE = SCADA_MGMT_TYPE
comms.SCADA_CRDN_TYPE = SCADA_CRDN_TYPE
comms.CAPI_TYPE = CAPI_TYPE

comms.ESTABLISH_ACK = ESTABLISH_ACK
comms.DEVICE_TYPE = DEVICE_TYPE

comms.PLC_AUTO_ACK = PLC_AUTO_ACK

comms.UNIT_COMMAND = UNIT_COMMAND
comms.FAC_COMMAND = FAC_COMMAND

-- destination broadcast address (to all devices)
comms.BROADCAST = -1

---@alias packet scada_packet|modbus_packet|rplc_packet|mgmt_packet|crdn_packet|capi_packet
---@alias frame modbus_frame|rplc_frame|mgmt_frame|crdn_frame|capi_frame

-- configure the maximum allowable message receive distance<br>
-- packets received with distances greater than this will be silently discarded
---@param distance integer max modem message distance (0 disables the limit)
function comms.set_trusted_range(distance)
    if distance == 0 then max_distance = nil else max_distance = distance end
end

-- generic SCADA packet object
---@nodiscard
function comms.scada_packet()
    local self = {
        modem_msg_in = nil, ---@type modem_message|nil
        valid = false,
        raw = {},
        src_addr = comms.BROADCAST,
        dest_addr = comms.BROADCAST,
        seq_num = -1,
        protocol = PROTOCOL.SCADA_MGMT,
        length = 0,
        payload = {}
    }

    ---@class scada_packet
    local public = {}

    -- make a SCADA packet
    ---@param dest_addr integer destination computer address (ID)
    ---@param seq_num integer sequence number
    ---@param protocol PROTOCOL
    ---@param payload table
    function public.make(dest_addr, seq_num, protocol, payload)
        self.valid = true
        self.src_addr = COMPUTER_ID
        self.dest_addr = dest_addr
        self.seq_num = seq_num
        self.protocol = protocol
        self.length = #payload
        self.payload = payload
        self.raw = { self.src_addr, self.dest_addr, self.seq_num, self.protocol, self.payload }
    end

    -- parse in a modem message as a SCADA packet
    ---@param side string modem side
    ---@param sender integer sender channel
    ---@param reply_to integer reply channel
    ---@param message any message body
    ---@param distance integer transmission distance
    ---@return boolean valid valid message received
    function public.receive(side, sender, reply_to, message, distance)
        ---@class modem_message
        self.modem_msg_in = {
            iface = side,
            s_channel = sender,
            r_channel = reply_to,
            msg = message,
            dist = distance
        }

        self.valid = false
        self.raw = self.modem_msg_in.msg

        if (type(max_distance) == "number") and (distance > max_distance) then
            -- outside of maximum allowable transmission distance
            -- log.debug("comms.scada_packet.receive(): discarding packet with distance " .. distance .. " outside of trusted range")
        else
            if type(self.raw) == "table" then
                if #self.raw == 5 then
                    self.src_addr = self.raw[1]
                    self.dest_addr = self.raw[2]
                    self.seq_num = self.raw[3]
                    self.protocol = self.raw[4]

                    -- element 5 must be a table
                    if type(self.raw[5]) == "table" then
                        self.length = #self.raw[5]
                        self.payload = self.raw[5]
                    end
                else
                    self.src_addr = nil
                    self.dest_addr = nil
                    self.seq_num = nil
                    self.protocol = nil
                    self.length = 0
                    self.payload = {}
                end

                -- check if this packet is destined for this device
                local is_destination = (self.dest_addr == comms.BROADCAST) or (self.dest_addr == COMPUTER_ID)

                self.valid = is_destination and
                                type(self.src_addr)  == "number" and
                                type(self.dest_addr) == "number" and
                                type(self.seq_num)   == "number" and
                                type(self.protocol)  == "number" and
                                type(self.payload)   == "table"
            end
        end

        return self.valid
    end

    -- public accessors --

    ---@nodiscard
    function public.modem_event() return self.modem_msg_in end
    ---@nodiscard
    function public.raw_sendable() return self.raw end

    ---@nodiscard
    function public.local_channel() return self.modem_msg_in.s_channel end
    ---@nodiscard
    function public.remote_channel() return self.modem_msg_in.r_channel end

    ---@nodiscard
    function public.is_valid() return self.valid end

    ---@nodiscard
    function public.src_addr() return self.src_addr end
    ---@nodiscard
    function public.dest_addr() return self.dest_addr end
    ---@nodiscard
    function public.seq_num() return self.seq_num end
    ---@nodiscard
    function public.protocol() return self.protocol end
    ---@nodiscard
    function public.length() return self.length end
    ---@nodiscard
    function public.data() return self.payload end

    return public
end

-- authenticated SCADA packet object
---@nodiscard
function comms.authd_packet()
    local self = {
        modem_msg_in = nil, ---@type modem_message|nil
        valid = false,
        raw = {},
        src_addr = comms.BROADCAST,
        dest_addr = comms.BROADCAST,
        mac = "",
        payload = ""
    }

    ---@class authd_packet
    local public = {}

    -- make an authenticated SCADA packet
    ---@param s_packet scada_packet scada packet to authenticate
    ---@param mac function message authentication function
    function public.make(s_packet, mac)
        self.valid = true
        self.src_addr = s_packet.src_addr()
        self.dest_addr = s_packet.dest_addr()
        self.payload = textutils.serialize(s_packet.raw_sendable(), { allow_repetitions = true, compact = true })
        self.mac = mac(self.payload)
        self.raw = { self.src_addr, self.dest_addr, self.mac, self.payload }
    end

    -- parse in a modem message as an authenticated SCADA packet
    ---@param side string modem side
    ---@param sender integer sender channel
    ---@param reply_to integer reply channel
    ---@param message any message body
    ---@param distance integer transmission distance
    ---@return boolean valid valid message received
    function public.receive(side, sender, reply_to, message, distance)
        ---@class modem_message
        self.modem_msg_in = {
            iface = side,
            s_channel = sender,
            r_channel = reply_to,
            msg = message,
            dist = distance
        }

        self.valid = false
        self.raw = self.modem_msg_in.msg

        if (type(max_distance) == "number") and (distance > max_distance) then
            -- outside of maximum allowable transmission distance
            -- log.debug("comms.authd_packet.receive(): discarding packet with distance " .. distance .. " outside of trusted range")
        else
            if type(self.raw) == "table" then
                if #self.raw == 4 then
                    self.src_addr = self.raw[1]
                    self.dest_addr = self.raw[2]
                    self.mac = self.raw[3]
                    self.payload = self.raw[4]
                else
                    self.src_addr = nil
                    self.dest_addr = nil
                    self.mac = ""
                    self.payload = ""
                end

                -- check if this packet is destined for this device
                local is_destination = (self.dest_addr == comms.BROADCAST) or (self.dest_addr == COMPUTER_ID)

                self.valid = is_destination and
                                type(self.src_addr)  == "number" and
                                type(self.dest_addr) == "number" and
                                type(self.mac)       == "string" and
                                type(self.payload)   == "string"
            end
        end

        return self.valid
    end

    -- public accessors --

    ---@nodiscard
    function public.modem_event() return self.modem_msg_in end
    ---@nodiscard
    function public.raw_sendable() return self.raw end

    ---@nodiscard
    function public.local_channel() return self.modem_msg_in.s_channel end
    ---@nodiscard
    function public.remote_channel() return self.modem_msg_in.r_channel end

    ---@nodiscard
    function public.is_valid() return self.valid end

    ---@nodiscard
    function public.src_addr() return self.src_addr end
    ---@nodiscard
    function public.dest_addr() return self.dest_addr end
    ---@nodiscard
    function public.mac() return self.mac end
    ---@nodiscard
    function public.data() return self.payload end

    return public
end

-- MODBUS packet<br>
-- modeled after MODBUS TCP packet
---@nodiscard
function comms.modbus_packet()
    local self = {
        frame = nil,
        raw = {},
        txn_id = -1,
        length = 0,
        unit_id = -1,
        func_code = 0x80,
        data = {}
    }

    ---@class modbus_packet
    local public = {}

    -- make a MODBUS packet
    ---@param txn_id integer
    ---@param unit_id integer
    ---@param func_code MODBUS_FCODE
    ---@param data table
    function public.make(txn_id, unit_id, func_code, data)
        if type(data) == "table" then
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
        else
            log.error("comms.modbus_packet.make(): data not table")
        end
    end

    -- decode a MODBUS packet from a SCADA frame
    ---@param frame scada_packet
    ---@return boolean success
    function public.decode(frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOL.MODBUS_TCP then
                local size_ok = frame.length() >= 3

                if size_ok then
                    local data = frame.data()
                    public.make(data[1], data[2], data[3], { table.unpack(data, 4, #data) })
                end

                local valid = type(self.txn_id) == "number" and
                              type(self.unit_id) == "number" and
                              type(self.func_code) == "number"

                return size_ok and valid
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
    ---@nodiscard
    function public.raw_sendable() return self.raw end

    -- get this packet as a frame with an immutable relation to this object
    ---@nodiscard
    function public.get()
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
---@nodiscard
function comms.rplc_packet()
    local self = {
        frame = nil,
        raw = {},
        id = 0,
        type = 0,   ---@type RPLC_TYPE
        length = 0,
        data = {}
    }

    ---@class rplc_packet
    local public = {}

    -- check that type is known
    local function _rplc_type_valid()
        return self.type == RPLC_TYPE.STATUS or
                self.type == RPLC_TYPE.MEK_STRUCT or
                self.type == RPLC_TYPE.MEK_BURN_RATE or
                self.type == RPLC_TYPE.RPS_ENABLE or
                self.type == RPLC_TYPE.RPS_SCRAM or
                self.type == RPLC_TYPE.RPS_ASCRAM or
                self.type == RPLC_TYPE.RPS_STATUS or
                self.type == RPLC_TYPE.RPS_ALARM or
                self.type == RPLC_TYPE.RPS_RESET or
                self.type == RPLC_TYPE.RPS_AUTO_RESET or
                self.type == RPLC_TYPE.AUTO_BURN_RATE
    end

    -- make an RPLC packet
    ---@param id integer
    ---@param packet_type RPLC_TYPE
    ---@param data table
    function public.make(id, packet_type, data)
        if type(data) == "table" then
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
        else
            log.error("comms.rplc_packet.make(): data not table")
        end
    end

    -- decode an RPLC packet from a SCADA frame
    ---@param frame scada_packet
    ---@return boolean success
    function public.decode(frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOL.RPLC then
                local ok = frame.length() >= 2

                if ok then
                    local data = frame.data()
                    public.make(data[1], data[2], { table.unpack(data, 3, #data) })
                    ok = _rplc_type_valid()
                end

                ok = ok and type(self.id) == "number"

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
    ---@nodiscard
    function public.raw_sendable() return self.raw end

    -- get this packet as a frame with an immutable relation to this object
    ---@nodiscard
    function public.get()
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
---@nodiscard
function comms.mgmt_packet()
    local self = {
        frame = nil,
        raw = {},
        type = 0,   ---@type SCADA_MGMT_TYPE
        length = 0,
        data = {}
    }

    ---@class mgmt_packet
    local public = {}

    -- check that type is known
    local function _scada_type_valid()
        return self.type == SCADA_MGMT_TYPE.ESTABLISH or
                self.type == SCADA_MGMT_TYPE.KEEP_ALIVE or
                self.type == SCADA_MGMT_TYPE.CLOSE or
                self.type == SCADA_MGMT_TYPE.REMOTE_LINKED or
                self.type == SCADA_MGMT_TYPE.RTU_ADVERT or
                self.type == SCADA_MGMT_TYPE.RTU_DEV_REMOUNT
    end

    -- make a SCADA management packet
    ---@param packet_type SCADA_MGMT_TYPE
    ---@param data table
    function public.make(packet_type, data)
        if type(data) == "table" then
            -- packet accessor properties
            self.type = packet_type
            self.length = #data
            self.data = data

            -- populate raw array
            self.raw = { self.type }
            for i = 1, #data do
                insert(self.raw, data[i])
            end
        else
            log.error("comms.mgmt_packet.make(): data not table")
        end
    end

    -- decode a SCADA management packet from a SCADA frame
    ---@param frame scada_packet
    ---@return boolean success
    function public.decode(frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOL.SCADA_MGMT then
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
    ---@nodiscard
    function public.raw_sendable() return self.raw end

    -- get this packet as a frame with an immutable relation to this object
    ---@nodiscard
    function public.get()
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
---@nodiscard
function comms.crdn_packet()
    local self = {
        frame = nil,
        raw = {},
        type = 0,   ---@type SCADA_CRDN_TYPE
        length = 0,
        data = {}
    }

    ---@class crdn_packet
    local public = {}

    -- check that type is known
    ---@nodiscard
    local function _crdn_type_valid()
        return self.type == SCADA_CRDN_TYPE.INITIAL_BUILDS or
                self.type == SCADA_CRDN_TYPE.FAC_BUILDS or
                self.type == SCADA_CRDN_TYPE.FAC_STATUS or
                self.type == SCADA_CRDN_TYPE.FAC_CMD or
                self.type == SCADA_CRDN_TYPE.UNIT_BUILDS or
                self.type == SCADA_CRDN_TYPE.UNIT_STATUSES or
                self.type == SCADA_CRDN_TYPE.UNIT_CMD
    end

    -- make a coordinator packet
    ---@param packet_type SCADA_CRDN_TYPE
    ---@param data table
    function public.make(packet_type, data)
        if type(data) == "table" then
            -- packet accessor properties
            self.type = packet_type
            self.length = #data
            self.data = data

            -- populate raw array
            self.raw = { self.type }
            for i = 1, #data do
                insert(self.raw, data[i])
            end
        else
            log.error("comms.crdn_packet.make(): data not table")
        end
    end

    -- decode a coordinator packet from a SCADA frame
    ---@param frame scada_packet
    ---@return boolean success
    function public.decode(frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOL.SCADA_CRDN then
                local ok = frame.length() >= 1

                if ok then
                    local data = frame.data()
                    public.make(data[1], { table.unpack(data, 2, #data) })
                    ok = _crdn_type_valid()
                end

                return ok
            else
                log.debug("attempted SCADA_CRDN parse of incorrect protocol " .. frame.protocol(), true)
                return false
            end
        else
            log.debug("nil frame encountered", true)
            return false
        end
    end

    -- get raw to send
    ---@nodiscard
    function public.raw_sendable() return self.raw end

    -- get this packet as a frame with an immutable relation to this object
    ---@nodiscard
    function public.get()
        ---@class crdn_frame
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
---@todo implement for pocket access, set enum type for self.type
---@nodiscard
function comms.capi_packet()
    local self = {
        frame = nil,
        raw = {},
        type = 0,
        length = 0,
        data = {}
    }

    ---@class capi_packet
    local public = {}

    local function _capi_type_valid()
        ---@todo
        return false
    end

    -- make a coordinator API packet
    ---@param packet_type CAPI_TYPE
    ---@param data table
    function public.make(packet_type, data)
        if type(data) == "table" then
            -- packet accessor properties
            self.type = packet_type
            self.length = #data
            self.data = data

            -- populate raw array
            self.raw = { self.type }
            for i = 1, #data do
                insert(self.raw, data[i])
            end
        else
            log.error("comms.capi_packet.make(): data not table")
        end
    end

    -- decode a coordinator API packet from a SCADA frame
    ---@param frame scada_packet
    ---@return boolean success
    function public.decode(frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOL.COORD_API then
                local ok = frame.length() >= 1

                if ok then
                    local data = frame.data()
                    public.make(data[1], { table.unpack(data, 2, #data) })
                    ok = _capi_type_valid()
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
    ---@nodiscard
    function public.raw_sendable() return self.raw end

    -- get this packet as a frame with an immutable relation to this object
    ---@nodiscard
    function public.get()
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

return comms
