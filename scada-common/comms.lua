--
-- SCADA Network Communications Objects
--

local log = require("scada-common.log")

-- basic acceleration aliases

local type     = type
local insert   = table.insert

local TYPE_NUM = "number"
local TYPE_STR = "string"
local TYPE_TBL = "table"

-- comms settings/attributes

---@type integer computer ID
---@diagnostic disable-next-line: undefined-field
local COMPUTER_ID = os.getComputerID()

---@type number|nil maximum acceptable transmission distance
local max_distance = nil

---@class comms
local comms = {}

-- protocol/data versions (protocol/data independent changes tracked by util.lua version)
comms.version = "3.1.0"
comms.api_version = "0.0.10"

---@alias frame scada_frame|authd_frame
---@alias packet_container modbus_container|rplc_container|mgmt_container|crdn_container
---@alias packet modbus_adu|rplc_packet|mgmt_packet|crdn_packet

--#region Protocol Definitions

---@enum PROTOCOL
local PROTOCOL = {
    MODBUS_TCP = 0,      -- the "MODBUS TCP"-esque protocol
    RPLC = 1,            -- reactor PLC protocol
    SCADA_MGMT = 2,      -- SCADA supervisor management, device advertisements, etc
    SCADA_CRDN = 3       -- data/control packets for coordinators to/from supervisory controllers
}

---@enum RPLC_TYPE
local RPLC_TYPE = {
    STATUS = 0,          -- reactor/system status
    MEK_STRUCT = 1,      -- mekanism build structure
    MEK_BURN_RATE = 2,   -- set burn rate
    RPS_ENABLE = 3,      -- enable reactor
    RPS_DISABLE = 4,     -- disable the reactor
    RPS_SCRAM = 5,       -- SCRAM reactor (manual request)
    RPS_ASCRAM = 6,      -- SCRAM reactor (automatic request)
    RPS_STATUS = 7,      -- RPS status
    RPS_ALARM = 8,       -- RPS alarm broadcast
    RPS_RESET = 9,       -- clear RPS trip (if in bad state, will trip immediately)
    RPS_AUTO_RESET = 10, -- clear RPS trip if it is just a timeout or auto scram
    AUTO_BURN_RATE = 11  -- set an automatic burn rate, PLC will respond with status, enable toggle speed limited
}

---@enum MGMT_TYPE
local MGMT_TYPE = {
    -- connection
    ESTABLISH = 0,       -- establish new connection
    KEEP_ALIVE = 1,      -- keep alive packet w/ RTT
    CLOSE = 2,           -- close a connection
    SWITCH_NET = 3,
    -- RTU
    RTU_ADVERT = 4,      -- RTU capability advertisement
    RTU_DEV_REMOUNT = 5, -- RTU multiblock possbily changed (formed, unformed) due to PPM remount
    RTU_TONE_ALARM = 6,  -- instruct RTUs to play specified alarm tones
    -- API
    DIAG_TONE_GET = 7,   -- diagnostic - get alarm tones
    DIAG_TONE_SET = 8,   -- diagnostic - set alarm tones
    DIAG_ALARM_SET = 9,  -- diagnostic - set alarm to simulate audio for
    INFO_LIST_CMP = 10   -- info - list all computers on the network
}

---@enum CRDN_TYPE
local CRDN_TYPE = {
    INITIAL_BUILDS = 0,  -- initial, complete builds packet to the coordinator
    PROCESS_READY = 1,   -- process init is complete + last set of info for supervisor startup recovery
    FAC_BUILDS = 2,      -- facility RTU builds
    FAC_STATUS = 3,      -- state of facility and facility devices
    FAC_CMD = 4,         -- faility command
    UNIT_BUILDS = 5,     -- build of each reactor unit (reactor + RTUs)
    UNIT_STATUSES = 6,   -- state of each of the reactor units
    UNIT_CMD = 7,        -- command a reactor unit
    API_GET_FAC = 8,     -- API: get the facility general data
    API_GET_FAC_DTL = 9, -- API: get (detailed) data for the facility app
    API_GET_UNIT = 10,   -- API: get reactor unit data
    API_GET_CTRL = 11,   -- API: get data for the control app
    API_GET_PROC = 12,   -- API: get data for the process app
    API_GET_WASTE = 13,  -- API: get data for the waste app
    API_GET_RAD = 14     -- API: get data for the radiation monitor app
}

---@enum ESTABLISH_ACK
local ESTABLISH_ACK = {
    ALLOW = 0,           -- link approved
    DENY = 1,            -- link denied
    COLLISION = 2,       -- link denied due to existing active link
    BAD_VERSION = 3,     -- link denied due to comms version mismatch
    BAD_API_VERSION = 4  -- link denied due to api version mismatch
}

---@enum DEVICE_TYPE device types for establish messages
local DEVICE_TYPE = { PLC = 0, RTU = 1, SVR = 2, CRD = 3, PKT = 4 }

---@enum PLC_AUTO_ACK
local PLC_AUTO_ACK = {
    FAIL = 0,            -- failed to set burn rate/burn rate invalid
    DIRECT_SET_OK = 1,   -- successfully set burn rate
    RAMP_SET_OK = 2,     -- successfully started burn rate ramping
    ZERO_DIS_OK = 3      -- successfully disabled reactor with < 0.01 burn rate
}

---@enum FAC_COMMAND
local FAC_COMMAND = {
    SCRAM_ALL = 0,       -- SCRAM all reactors
    STOP = 1,            -- stop automatic process control
    START = 2,           -- start automatic process control
    ACK_ALL_ALARMS = 3,  -- acknowledge all alarms on all units
    SET_WASTE_MODE = 4,  -- set automatic waste processing mode
    SET_PU_FB = 5,       -- set plutonium fallback mode
    SET_SPS_LP = 6       -- set SPS at low power mode
}

---@enum UNIT_COMMAND
local UNIT_COMMAND = {
    SCRAM = 0,           -- SCRAM the reactor
    START = 1,           -- start the reactor
    RESET_RPS = 2,       -- reset the RPS
    SET_BURN = 3,        -- set the burn rate
    SET_WASTE = 4,       -- set the waste processing mode
    ACK_ALL_ALARMS = 5,  -- ack all active alarms
    ACK_ALARM = 6,       -- ack a particular alarm
    RESET_ALARM = 7,     -- reset a particular alarm
    SET_GROUP = 8        -- assign this unit to a group
}

comms.PROTOCOL = PROTOCOL

comms.RPLC_TYPE = RPLC_TYPE
comms.MGMT_TYPE = MGMT_TYPE
comms.CRDN_TYPE = CRDN_TYPE

comms.ESTABLISH_ACK = ESTABLISH_ACK
comms.DEVICE_TYPE = DEVICE_TYPE

comms.PLC_AUTO_ACK = PLC_AUTO_ACK

comms.UNIT_COMMAND = UNIT_COMMAND
comms.FAC_COMMAND = FAC_COMMAND

--#endregion

-- destination broadcast address (to all devices)
comms.BROADCAST = -1

-- firmware version used to indicate an establish packet is a connection test
comms.CONN_TEST_FWV = "CONN_TEST"

-- configure the maximum allowable message receive distance<br>
-- packets received with distances greater than this will be silently discarded
---@param distance integer max modem message distance (0 disables the limit)
function comms.set_trusted_range(distance)
    if distance == 0 then max_distance = nil else max_distance = distance end
end

--#region Network Frames (Layer 2)

-- SCADA link-layer discovery frame
---@nodiscard
function comms.lld_frame()
    local self = {
        modem_frame = nil, ---@type modem_frame|nil

        valid = false,

        raw = {},

        src_addr  = nil, ---@type integer|nil
        dest_addr = nil, ---@type integer|nil
        ack       = false
    }

    ---@class lld_frame
    local public = {}

    -- make a link-layer discovery frame
    ---@param dest_addr integer destination computer address (ID)
    ---@param ack boolean if this is an acknowledgement
    function public.make(dest_addr, ack)
        self.valid = true

        self.src_addr  = COMPUTER_ID
        self.dest_addr = dest_addr
        self.ack       = ack

        self.raw = { COMPUTER_ID, dest_addr, ack }
    end

    -- parse in modem frame fields as a link-layer discovery frame
    ---@param side string modem side
    ---@param sender integer sender channel
    ---@param reply_to integer reply channel
    ---@param message any message body
    ---@param distance integer transmission distance
    ---@return boolean valid valid frame received
    function public.receive(side, sender, reply_to, message, distance)
        ---@class modem_frame
        self.modem_frame = {
            iface = side, s_chan = sender, r_chan = reply_to, dist = distance, data = message
        }

        self.valid = false
        self.raw   = self.modem_frame.data

        if (type(max_distance) == TYPE_NUM) and (type(distance) == TYPE_NUM) and (distance > max_distance) then
            -- outside of maximum allowable transmission distance
            -- log.debug("COMMS: lld_frame.receive(): discarding frame with distance " .. distance .. " (outside trusted range)")
        elseif type(self.raw) == TYPE_TBL then
            self.src_addr  = self.raw[1]
            self.dest_addr = self.raw[2]
            self.ack       = self.raw[3] == true

            -- check if this frame is destined for this device, otherwise discard ASAP
            if (self.dest_addr == COMPUTER_ID) or (self.dest_addr == comms.BROADCAST) then
                self.valid = type(self.src_addr) == TYPE_NUM and type(self.dest_addr) == TYPE_NUM
            end
        end

        return self.valid
    end

    -- public accessors --

    ---@nodiscard
    function public.modem_event() return self.modem_frame end
    ---@nodiscard
    function public.raw_frame() return self.raw end

    ---@nodiscard
    function public.interface() return self.modem_frame.iface end
    ---@nodiscard
    function public.local_channel() return self.modem_frame.s_chan end
    ---@nodiscard
    function public.remote_channel() return self.modem_frame.r_chan end

    ---@nodiscard
    function public.is_valid() return self.valid end

    ---@nodiscard
    function public.src_addr() return self.src_addr or comms.BROADCAST end
    ---@nodiscard
    function public.dest_addr() return self.dest_addr or comms.BROADCAST end
    ---@nodiscard
    function public.is_ack() return self.ack end

    return public
end

-- SCADA network frame
---@nodiscard
function comms.scada_frame()
    local self = {
        modem_frame = nil, ---@type modem_frame|nil

        valid         = false,
        authenticated = false,

        raw = {},

        src_addr  = nil, ---@type integer|nil
        dest_addr = nil, ---@type integer|nil
        seq_num   = nil, ---@type integer|nil
        protocol  = nil, ---@type PROTOCOL|nil
        length    = 0,
        payload   = {}
    }

    ---@class scada_frame
    local public = {}

    -- make a SCADA frame
    ---@param dest_addr integer destination computer address (ID)
    ---@param seq_num integer sequence number
    ---@param protocol PROTOCOL
    ---@param payload table
    function public.make(dest_addr, seq_num, protocol, payload)
        self.valid = true

        self.src_addr  = COMPUTER_ID
        self.dest_addr = dest_addr
        self.seq_num   = seq_num
        self.protocol  = protocol
        self.length    = #payload
        self.payload   = payload

        self.raw = { COMPUTER_ID, dest_addr, seq_num, protocol, payload }
    end

    -- parse in modem frame fields as a SCADA frame
    ---@param side string modem side
    ---@param sender integer sender channel
    ---@param reply_to integer reply channel
    ---@param message any message body
    ---@param distance integer transmission distance
    ---@return boolean valid valid frame received
    function public.receive(side, sender, reply_to, message, distance)
        ---@class modem_frame
        self.modem_frame = {
            iface = side, s_chan = sender, r_chan = reply_to, dist = distance, data = message
        }

        self.valid = false
        self.raw   = self.modem_frame.data

        if (type(max_distance) == TYPE_NUM) and (type(distance) == TYPE_NUM) and (distance > max_distance) then
            -- outside of maximum allowable transmission distance
            -- log.debug("COMMS: scada_frame.receive(): discarding frame with distance " .. distance .. " (outside trusted range)")
        elseif type(self.raw) == TYPE_TBL then
            self.src_addr  = self.raw[1]
            self.dest_addr = self.raw[2]

            -- check if this frame is destined for this device, otherwise discard ASAP
            -- if it is, check that the payload is a table and continue
            if ((self.dest_addr == COMPUTER_ID) or (self.dest_addr == comms.BROADCAST)) and (type(self.raw[5]) == TYPE_TBL) then
                self.seq_num  = self.raw[3]
                self.protocol = self.raw[4]
                self.length   = #self.raw[5]
                self.payload  = self.raw[5]

                self.valid = type(self.src_addr) == TYPE_NUM and type(self.dest_addr) == TYPE_NUM and
                             type(self.seq_num) == TYPE_NUM and type(self.protocol) == TYPE_NUM
            end
        end

        return self.valid
    end

    -- report that this packet has been authenticated (was received with a valid HMAC)
    function public.stamp_authenticated() self.authenticated = true end

    -- public accessors --

    ---@nodiscard
    function public.modem_event() return self.modem_frame end
    ---@nodiscard
    function public.raw_header() return { self.src_addr, self.dest_addr, self.seq_num, self.protocol } end
    ---@nodiscard
    function public.raw_frame() return self.raw end

    ---@nodiscard
    function public.interface() return self.modem_frame.iface end
    ---@nodiscard
    function public.local_channel() return self.modem_frame.s_chan end
    ---@nodiscard
    function public.remote_channel() return self.modem_frame.r_chan end

    ---@nodiscard
    function public.is_valid() return self.valid end
    ---@nodiscard
    function public.is_authenticated() return self.authenticated end

    ---@nodiscard
    function public.src_addr() return self.src_addr or comms.BROADCAST end
    ---@nodiscard
    function public.dest_addr() return self.dest_addr or comms.BROADCAST end
    ---@nodiscard
    function public.seq_num() return self.seq_num or -1 end
    ---@nodiscard
    function public.protocol() return self.protocol or PROTOCOL.SCADA_MGMT end
    ---@nodiscard
    function public.length() return self.length or 0 end
    ---@nodiscard
    function public.data() return self.payload or {} end

    return public
end

-- authenticated SCADA frame
---@nodiscard
function comms.authd_frame()
    local self = {
        modem_frame = nil, ---@type modem_frame|nil

        valid = false,

        raw = {},

        src_addr  = nil, ---@type integer|nil
        dest_addr = nil, ---@type integer|nil
        mac       = "",
        payload   = {}
    }

    ---@class authd_frame
    local public = {}

    -- make an authenticated SCADA frame
    ---@param s_frame scada_frame scada frame to authenticate
    ---@param mac function message authentication hash function
    function public.make(s_frame, mac)
        self.valid = true

        self.src_addr  = s_frame.src_addr()
        self.dest_addr = s_frame.dest_addr()
        self.mac       = mac(textutils.serialize(s_frame.raw_header(), { allow_repetitions = true, compact = true }))

        self.raw = { self.src_addr, self.dest_addr, self.mac, s_frame.raw_frame() }
    end

    -- parse in modem frame fields as an authenticated SCADA frame
    ---@param side string modem side
    ---@param sender integer sender channel
    ---@param reply_to integer reply channel
    ---@param message any message body
    ---@param distance integer transmission distance
    ---@return boolean valid valid frame received
    function public.receive(side, sender, reply_to, message, distance)
        ---@class modem_frame
        self.modem_frame = {
            iface = side, s_chan = sender, r_chan = reply_to, data = message, dist = distance
        }

        self.valid = false
        self.raw   = self.modem_frame.data

        if (type(max_distance) == TYPE_NUM) and ((type(distance) ~= TYPE_NUM) or (distance > max_distance)) then
            -- outside of maximum allowable transmission distance
            -- log.debug("COMMS: authd_frame.receive(): discarding frame with distance " .. distance .. " (outside trusted range)")
        elseif type(self.raw) == TYPE_TBL then
            self.src_addr  = self.raw[1]
            self.dest_addr = self.raw[2]

            -- check if this packet is destined for this device, otherwise discard ASAP
            if (self.dest_addr == COMPUTER_ID) or (self.dest_addr == comms.BROADCAST) then
                self.mac     = self.raw[3]
                self.payload = self.raw[4]

                self.valid = type(self.src_addr) == TYPE_NUM and type(self.dest_addr) == TYPE_NUM and
                             type(self.mac) == TYPE_STR and type(self.payload) == TYPE_TBL
            end
        end

        return self.valid
    end

    -- public accessors --

    ---@nodiscard
    function public.modem_event() return self.modem_frame end
    ---@nodiscard
    function public.raw_frame() return self.raw end

    ---@nodiscard
    function public.local_channel() return self.modem_frame.s_chan end
    ---@nodiscard
    function public.remote_channel() return self.modem_frame.r_chan end

    ---@nodiscard
    function public.is_valid() return self.valid end

    ---@nodiscard
    function public.src_addr() return self.src_addr or comms.BROADCAST end
    ---@nodiscard
    function public.dest_addr() return self.dest_addr or comms.BROADCAST end
    ---@nodiscard
    function public.mac() return self.mac or "" end
    ---@nodiscard
    function public.data() return self.payload or {} end

    return public
end

--#endregion

--#region Network Packets (Layer 3)

-- MODBUS packet container, modeled after MODBUS TCP
---@nodiscard
function comms.modbus_container()
    local self = {
        frame = nil,      ---@type scada_frame

        raw = {},

        txn_id    = -1,
        length    = 0,
        unit_id   = -1,
        func_code = 0x80, ---@type MODBUS_FCODE
        data      = {}
    }

    ---@class modbus_container
    local public = {}

    -- make a MODBUS packet
    ---@param txn_id integer
    ---@param unit_id integer
    ---@param func_code MODBUS_FCODE
    ---@param data table
    ---@return boolean success
    function public.make(txn_id, unit_id, func_code, data)
        if type(data) == TYPE_TBL then
            self.txn_id    = txn_id
            self.length    = #data
            self.unit_id   = unit_id
            self.func_code = func_code
            self.data      = data

            -- populate raw array
            self.raw = { self.txn_id, self.unit_id, self.func_code }
            for i = 1, self.length do insert(self.raw, data[i]) end

            return true
        end

        log.error("COMMS: [modbus_make] data not a table")
        return false
    end

    -- decode a MODBUS packet from a SCADA frame
    ---@param frame scada_frame
    ---@return modbus_adu|nil packet the decoded packet, if valid
    function public.decode(frame)
        if frame then
            local data = frame.data()

            self.frame = frame
            self.raw   = data

            if frame.protocol() == PROTOCOL.MODBUS_TCP then
                self.txn_id    = data[1]
                self.unit_id   = data[2]
                self.func_code = data[3]
                self.data      = { table.unpack(data, 4, #data) }
                self.length    = #self.data

                if type(self.txn_id) == TYPE_NUM and type(self.unit_id) == TYPE_NUM and type(self.func_code) == TYPE_NUM then
                    return public.get()
                end
            else log.debug("COMMS: [modbus_decode] attempted parse of incorrect protocol " .. frame.protocol(), true) end
        else log.debug("COMMS: [modbus_decode] discarding nil frame", true) end

        return nil
    end

    -- get the raw packet table for transmission
    ---@nodiscard
    function public.raw_packet() return self.raw end

    -- create a new packet (ADU) from this container's contents
    ---@nodiscard
    function public.get()
        ---@class modbus_adu
        local adu = {
            scada_frame = self.frame,
            txn_id = self.txn_id,
            length = self.length,
            unit_id = self.unit_id,
            func_code = self.func_code,
            data = self.data
        }

        return adu
    end

    return public
end

-- reactor PLC packet container
---@nodiscard
function comms.rplc_container()
    local self = {
        frame = nil, ---@type scada_frame

        raw   = {},

        id     = 0,
        type   = 0,  ---@type RPLC_TYPE
        length = 0,
        data   = {}
    }

    ---@class rplc_container
    local public = {}

    -- make an RPLC packet
    ---@param id integer
    ---@param packet_type RPLC_TYPE
    ---@param data table
    ---@return boolean success
    function public.make(id, packet_type, data)
        if type(data) == TYPE_TBL then
            -- packet accessor properties
            self.id     = id
            self.type   = packet_type
            self.length = #data
            self.data   = data

            -- populate raw array
            self.raw = { self.id, self.type }
            for i = 1, #data do insert(self.raw, data[i]) end

            return true
        end

        log.error("COMMS: [rplc_make] data not a table")
        return false
    end

    -- decode an RPLC packet from a SCADA frame
    ---@param frame scada_frame
    ---@return rplc_packet|nil packet the decoded packet, if valid
    function public.decode(frame)
        if frame then
            local data = frame.data()

            self.frame = frame
            self.raw   = data

            if frame.protocol() == PROTOCOL.RPLC then
                self.id     = data[1]
                self.type   = data[2]
                self.data   = { table.unpack(data, 3, #data) }
                self.length = #self.data

                if type(self.id) == TYPE_NUM and type(self.type) == TYPE_NUM then
                    return public.get()
                end
            else log.debug("COMMS: [rplc_decode] attempted parse of incorrect protocol " .. frame.protocol(), true) end
        else log.debug("COMMS: [rplc_decode] nil frame encountered", true) end

        return nil
    end

    -- get the raw packet table for transmission
    ---@nodiscard
    function public.raw_packet() return self.raw end

    -- create a new packet from this container's contents
    ---@nodiscard
    function public.get()
        ---@class rplc_packet
        local packet = {
            scada_frame = self.frame,
            id = self.id,
            type = self.type,
            length = self.length,
            data = self.data
        }

        return packet
    end

    return public
end

-- SCADA management packet container
---@nodiscard
function comms.mgmt_container()
    local self = {
        frame = nil, ---@type scada_frame

        raw = {},

        type   = 0,  ---@type MGMT_TYPE
        length = 0,
        data   = {}
    }

    ---@class mgmt_container
    local public = {}

    -- make a SCADA management packet
    ---@param packet_type MGMT_TYPE
    ---@param data table
    ---@return boolean success
    function public.make(packet_type, data)
        if type(data) == TYPE_TBL then
            -- packet accessor properties
            self.type   = packet_type
            self.length = #data
            self.data   = data

            -- populate raw array
            self.raw = { self.type }
            for i = 1, #data do insert(self.raw, data[i]) end

            return true
        end

        log.error("COMMS: [mgmt_make] data not a table")
        return false
    end

    -- decode a SCADA management packet from a SCADA frame
    ---@param frame scada_frame
    ---@return mgmt_packet|nil packet the decoded packet, if valid
    function public.decode(frame)
        if frame then
            local data = frame.data()

            self.frame = frame
            self.raw   = data

            if frame.protocol() == PROTOCOL.SCADA_MGMT then
                self.type   = data[1]
                self.data   = { table.unpack(data, 2, #data) }
                self.length = #self.data

                if type(self.type) == TYPE_NUM then
                    return public.get()
                end
            else log.debug("COMMS: [mgmt_decode] attempted parse of incorrect protocol " .. frame.protocol(), true) end
        else log.debug("COMMS: [mgmt_decode] nil frame encountered", true) end

        return nil
    end

    -- get the raw packet table for transmission
    ---@nodiscard
    function public.raw_packet() return self.raw end

    -- create a new packet from this container's contents
    ---@nodiscard
    function public.get()
        ---@class mgmt_packet
        local packet = {
            scada_frame = self.frame,
            type = self.type,
            length = self.length,
            data = self.data
        }

        return packet
    end

    return public
end

-- SCADA coordinator packet container
---@nodiscard
function comms.crdn_container()
    local self = {
        frame = nil, ---@type scada_frame

        raw = {},

        type   = 0,  ---@type CRDN_TYPE
        length = 0,
        data   = {}
    }

    ---@class crdn_container
    local public = {}

    -- make a coordinator packet
    ---@param packet_type CRDN_TYPE
    ---@param data table
    ---@return boolean success
    function public.make(packet_type, data)
        if type(data) == TYPE_TBL then
            -- packet accessor properties
            self.type   = packet_type
            self.length = #data
            self.data   = data

            -- populate raw array
            self.raw = { self.type }
            for i = 1, #data do insert(self.raw, data[i]) end

            return true
        end

        log.error("COMMS: [crdn_make] data not a table")
        return false
    end

    -- decode a coordinator packet from a SCADA frame
    ---@param frame scada_frame
    ---@return crdn_packet|nil packet the decoded packet, if valid
    function public.decode(frame)
        if frame then
            local data = frame.data()

            self.frame = frame
            self.raw   = data

            if frame.protocol() == PROTOCOL.SCADA_CRDN then
                self.type   = data[1]
                self.data   = { table.unpack(data, 2, #data) }
                self.length = #self.data

                if type(self.type) == TYPE_NUM then
                    return public.get()
                end
            else log.debug("COMMS: [crdn_decode] attempted parse of incorrect protocol " .. frame.protocol(), true) end
        else log.debug("COMMS: [crdn_decode] nil frame encountered", true) end

        return nil
    end

    -- get the raw packet table for transmission
    ---@nodiscard
    function public.raw_packet() return self.raw end

    -- create a new packet from this container's contents
    ---@nodiscard
    function public.get()
        ---@class crdn_packet
        local packet = {
            scada_frame = self.frame,
            type = self.type,
            length = self.length,
            data = self.data
        }

        return packet
    end

    return public
end

--#endregion

return comms
