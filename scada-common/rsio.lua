--
-- Redstone I/O
--

local util = require("scada-common.util")

---@class rsio
local rsio = {}

--#region RS I/O Constants

---@enum IO_LVL I/O logic level
local IO_LVL = {
    DISCONNECT = -1, -- use for RTU session to indicate this RTU is not connected to this port
    LOW = 0,
    HIGH = 1,
    FLOATING = 2     -- use for RTU session to indicate this RTU is connected but not yet read
}

---@enum IO_DIR I/O direction
local IO_DIR = {
    IN = 0,
    OUT = 1
}

---@enum IO_MODE I/O mode (digital/analog input/output)
local IO_MODE = {
    DIGITAL_IN = 0,
    DIGITAL_OUT = 1,
    ANALOG_IN = 2,
    ANALOG_OUT = 3
}

---@enum IO_PORT redstone I/O logic port
local IO_PORT = {
    -- digital inputs --

    -- facility
    F_SCRAM       = 1,  -- active low, facility-wide scram
    F_ACK         = 2,  -- active high, facility alarm acknowledge

    -- reactor
    R_SCRAM       = 3,  -- active low, reactor scram
    R_RESET       = 4,  -- active high, reactor RPS reset
    R_ENABLE      = 5,  -- active high, reactor enable

    -- unit
    U_ACK         = 6,  -- active high, unit alarm acknowledge

    -- digital outputs --

    -- facility
    F_ALARM       = 7,  -- active high, facility-wide alarm (any high priority unit alarm)
    F_ALARM_ANY   = 8,  -- active high, any alarm regardless of priority

    -- waste
    WASTE_PU      = 9,  -- active low, waste -> plutonium -> pellets route
    WASTE_PO      = 10, -- active low, waste -> polonium route
    WASTE_POPL    = 11, -- active low, polonium -> pellets route
    WASTE_AM      = 12, -- active low, polonium -> anti-matter route

    -- reactor
    R_ACTIVE      = 13, -- active high, reactor is active
    R_AUTO_CTRL   = 14, -- active high, reactor burn rate is automatic
    R_SCRAMMED    = 15, -- active high, reactor is scrammed
    R_AUTO_SCRAM  = 16, -- active high, reactor was automatically scrammed
    R_HIGH_DMG    = 17, -- active high, reactor damage is high
    R_HIGH_TEMP   = 18, -- active high, reactor is at a high temperature
    R_LOW_COOLANT = 19, -- active high, reactor has very low coolant
    R_EXCESS_HC   = 20, -- active high, reactor has excess heated coolant
    R_EXCESS_WS   = 21, -- active high, reactor has excess waste
    R_INSUFF_FUEL = 22, -- active high, reactor has insufficent fuel
    R_PLC_FAULT   = 23, -- active high, reactor PLC reports a device access fault
    R_PLC_TIMEOUT = 24, -- active high, reactor PLC has not been heard from

    -- unit outputs
    U_ALARM       = 25, -- active high, unit alarm
    U_EMER_COOL   = 26  -- active low, emergency coolant control
}

rsio.IO_LVL = IO_LVL
rsio.IO_DIR = IO_DIR
rsio.IO_MODE = IO_MODE
rsio.IO = IO_PORT
rsio.NUM_PORTS = IO_PORT.U_EMER_COOL

-- self checks

local dup_chk = {}
for _, v in pairs(IO_PORT) do
    assert(dup_chk[v] ~= true, "duplicate in port list")
    dup_chk[v] = true
end

assert(#dup_chk == rsio.NUM_PORTS, "port list malformed")

--#endregion

--#region Utility Functions

local PORT_NAMES = {
    "F_SCRAM",
    "F_ACK",
    "R_SCRAM",
    "R_RESET",
    "R_ENABLE",
    "U_ACK",
    "F_ALARM",
    "F_ALARM_ANY",
    "WASTE_PU",
    "WASTE_PO",
    "WASTE_POPL",
    "WASTE_AM",
    "R_ACTIVE",
    "R_AUTO_CTRL",
    "R_SCRAMMED",
    "R_AUTO_SCRAM",
    "R_HIGH_DMG",
    "R_HIGH_TEMP",
    "R_LOW_COOLANT",
    "R_EXCESS_HC",
    "R_EXCESS_WS",
    "R_INSUFF_FUEL",
    "R_PLC_FAULT",
    "R_PLC_TIMEOUT",
    "U_ALARM",
    "U_EMER_COOL"
}

local MODES = {
    IO_MODE.DIGITAL_IN,  -- F_SCRAM
    IO_MODE.DIGITAL_IN,  -- F_ACK
    IO_MODE.DIGITAL_IN,  -- R_SCRAM
    IO_MODE.DIGITAL_IN,  -- R_RESET
    IO_MODE.DIGITAL_IN,  -- R_ENABLE
    IO_MODE.DIGITAL_IN,  -- U_ACK
    IO_MODE.DIGITAL_OUT, -- F_ALARM
    IO_MODE.DIGITAL_OUT, -- F_ALARM_ANY
    IO_MODE.DIGITAL_OUT, -- WASTE_PU
    IO_MODE.DIGITAL_OUT, -- WASTE_PO
    IO_MODE.DIGITAL_OUT, -- WASTE_POPL
    IO_MODE.DIGITAL_OUT, -- WASTE_AM
    IO_MODE.DIGITAL_OUT, -- R_ACTIVE
    IO_MODE.DIGITAL_OUT, -- R_AUTO_CTRL
    IO_MODE.DIGITAL_OUT, -- R_SCRAMMED
    IO_MODE.DIGITAL_OUT, -- R_AUTO_SCRAM
    IO_MODE.DIGITAL_OUT, -- R_HIGH_DMG
    IO_MODE.DIGITAL_OUT, -- R_HIGH_TEMP
    IO_MODE.DIGITAL_OUT, -- R_LOW_COOLANT
    IO_MODE.DIGITAL_OUT, -- R_EXCESS_HC
    IO_MODE.DIGITAL_OUT, -- R_EXCESS_WS
    IO_MODE.DIGITAL_OUT, -- R_INSUFF_FUEL
    IO_MODE.DIGITAL_OUT, -- R_PLC_FAULT
    IO_MODE.DIGITAL_OUT, -- R_PLC_TIMEOUT
    IO_MODE.DIGITAL_OUT, -- U_ALARM
    IO_MODE.DIGITAL_OUT  -- U_EMER_COOL
}

assert(rsio.NUM_PORTS == #PORT_NAMES, "port names length incorrect")
assert(rsio.NUM_PORTS == #MODES, "modes length incorrect")

-- port to string
---@nodiscard
---@param port IO_PORT
function rsio.to_string(port)
    if util.is_int(port) and port > 0 and port <= #PORT_NAMES then
        return PORT_NAMES[port]
    else
        return "UNKNOWN"
    end
end

local _B_AND = bit.band

local function _I_ACTIVE_HIGH(level) return level == IO_LVL.HIGH end
local function _I_ACTIVE_LOW(level) return level == IO_LVL.LOW end
local function _O_ACTIVE_HIGH(active) if active then return IO_LVL.HIGH else return IO_LVL.LOW end end
local function _O_ACTIVE_LOW(active) if active then return IO_LVL.LOW else return IO_LVL.HIGH end end

-- I/O mappings to I/O function and I/O mode
local RS_DIO_MAP = {
    -- F_SCRAM
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.IN  },
    -- F_ACK
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.IN  },

    -- R_SCRAM
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.IN  },
    -- R_RESET
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.IN  },
    -- R_ENABLE
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.IN  },

    -- U_ACK
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.IN  },

    -- F_ALARM
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- F_ALARM_ANY
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },

    -- WASTE_PU
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
    -- WASTE_PO
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
    -- WASTE_POPL
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
    -- WASTE_AM
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },

    -- R_ACTIVE
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_AUTO_CTRL
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_SCRAMMED
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_AUTO_SCRAM
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_HIGH_DMG
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_HIGH_TEMP
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_LOW_COOLANT
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_EXCESS_HC
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_EXCESS_WS
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_INSUFF_FUEL
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_PLC_FAULT
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_PLC_TIMEOUT
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },

    -- U_ALARM
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- U_EMER_COOL
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT }
}

assert(rsio.NUM_PORTS == #RS_DIO_MAP, "RS_DIO_MAP length incorrect")

-- get the I/O direction of a port
---@nodiscard
---@param port IO_PORT
---@return IO_DIR
function rsio.get_io_dir(port)
    if rsio.is_valid_port(port) then return RS_DIO_MAP[port].mode
    else return IO_DIR.IN end
end

-- get the mode of a port
---@nodiscard
---@param port IO_PORT
---@return IO_MODE
function rsio.get_io_mode(port)
    if rsio.is_valid_port(port) then return MODES[port]
    else return IO_MODE.ANALOG_IN end
end

--#endregion

--#region Generic Checks

local RS_SIDES = rs.getSides()

-- check if a port is valid
---@nodiscard
---@param port IO_PORT
---@return boolean valid
function rsio.is_valid_port(port)
    return util.is_int(port) and port > 0 and port <= rsio.NUM_PORTS
end

-- check if a side is valid
---@nodiscard
---@param side string
---@return boolean valid
function rsio.is_valid_side(side)
    if side ~= nil then
        for i = 0, #RS_SIDES do
            if RS_SIDES[i] == side then return true end
        end
    end
    return false
end

-- check if a color is a valid single color
---@nodiscard
---@param color any
---@return boolean valid
function rsio.is_color(color)
    return util.is_int(color) and (color > 0) and (_B_AND(color, (color - 1)) == 0)
end

-- color to string
---@nodiscard
---@param color color
---@return string
function rsio.color_name(color)
    local color_name_map = { [colors.red] = "red", [colors.orange] = "orange", [colors.yellow] = "yellow", [colors.lime] = "lime", [colors.green] = "green", [colors.cyan] = "cyan", [colors.lightBlue] = "lightBlue", [colors.blue] = "blue", [colors.purple] = "purple", [colors.magenta] = "magenta", [colors.pink] = "pink", [colors.white] = "white", [colors.lightGray] = "lightGray", [colors.gray] = "gray", [colors.black] = "black", [colors.brown] = "brown" }

    if rsio.is_color(color) then
        return color_name_map[color]
    else return "unknown" end
end

--#endregion

--#region Digital I/O

-- get digital I/O level reading from a redstone boolean input value
---@nodiscard
---@param rs_value boolean raw value from redstone
---@return IO_LVL
function rsio.digital_read(rs_value)
    if rs_value then return IO_LVL.HIGH else return IO_LVL.LOW end
end

-- get redstone boolean output value corresponding to a digital I/O level
---@nodiscard
---@param level IO_LVL logic level
---@return boolean
function rsio.digital_write(level) return level == IO_LVL.HIGH end

-- returns the level corresponding to active
---@nodiscard
---@param port IO_PORT port (to determine active high/low)
---@param active boolean state to convert to logic level
---@return IO_LVL|false
function rsio.digital_write_active(port, active)
    if (not util.is_int(port)) or (port < IO_PORT.F_ALARM) or (port > IO_PORT.U_EMER_COOL) then
        return false
    else
        return RS_DIO_MAP[port]._out(active)
    end
end

-- returns true if the level corresponds to active
---@nodiscard
---@param port IO_PORT port (to determine active low/high)
---@param level IO_LVL logic level
---@return boolean|nil state true for active, false for inactive, or nil if invalid port or level provided
function rsio.digital_is_active(port, level)
    if not util.is_int(port) then
        return nil
    elseif level == IO_LVL.FLOATING or level == IO_LVL.DISCONNECT then
        return nil
    else
        return RS_DIO_MAP[port]._in(level)
    end
end

--#endregion

--#region Analog I/O

-- read an analog value scaled from min to max
---@nodiscard
---@param rs_value number redstone reading (0 to 15)
---@param min number minimum of range
---@param max number maximum of range
---@return number value scaled reading (min to max)
function rsio.analog_read(rs_value, min, max)
    local value = rs_value / 15
    return (value * (max - min)) + min
end

-- write an analog value from the provided scale range
---@nodiscard
---@param value number value to write (from min to max range)
---@param min number minimum of range
---@param max number maximum of range
---@return number rs_value scaled redstone reading (0 to 15)
function rsio.analog_write(value, min, max)
    local scaled_value = (value - min) / (max - min)
    return math.floor(scaled_value * 15)
end

--#endregion

return rsio
