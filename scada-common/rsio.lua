--
-- Redstone I/O
--

local util = require("scada-common.util")

---@class rsio
local rsio = {}

----------------------
-- RS I/O CONSTANTS --
----------------------

---@alias IO_LVL integer
local IO_LVL = {
    DISCONNECT = -1, -- use for RTU session to indicate this RTU is not connected to this port
    LOW = 0,
    HIGH = 1,
    FLOATING = 2     -- use for RTU session to indicate this RTU is connected but not yet read
}

---@alias IO_DIR integer
local IO_DIR = {
    IN = 0,
    OUT = 1
}

---@alias IO_MODE integer
local IO_MODE = {
    DIGITAL_IN = 0,
    DIGITAL_OUT = 1,
    ANALOG_IN = 2,
    ANALOG_OUT = 3
}

---@alias IO_PORT integer
local IO_PORT = {
    -- digital inputs --

    -- facility
    F_SCRAM       = 1,  -- active low, facility-wide scram

    -- reactor
    R_SCRAM       = 2,  -- active low, reactor scram
    R_ENABLE      = 3,  -- active high, reactor enable

    -- digital outputs --

    -- facility
    F_ALARM       = 4,  -- active high, facility safety alarm

    -- waste
    WASTE_PU      = 5,  -- active low, waste -> plutonium -> pellets route
    WASTE_PO      = 6,  -- active low, waste -> polonium route
    WASTE_POPL    = 7,  -- active low, polonium -> pellets route
    WASTE_AM      = 8,  -- active low, polonium -> anti-matter route

    -- reactor
    R_ALARM       = 9,  -- active high, reactor safety alarm
    R_SCRAMMED    = 10, -- active high, if the reactor is scrammed
    R_AUTO_SCRAM  = 11, -- active high, if the reactor was automatically scrammed
    R_ACTIVE      = 12, -- active high, if the reactor is active
    R_AUTO_CTRL   = 13, -- active high, if the reactor burn rate is automatic
    R_DMG_CRIT    = 14, -- active high, if the reactor damage is critical
    R_HIGH_TEMP   = 15, -- active high, if the reactor is at a high temperature
    R_NO_COOLANT  = 16, -- active high, if the reactor has no coolant
    R_EXCESS_HC   = 17, -- active high, if the reactor has excess heated coolant
    R_EXCESS_WS   = 18, -- active high, if the reactor has excess waste
    R_INSUFF_FUEL = 19, -- active high, if the reactor has insufficent fuel
    R_PLC_FAULT   = 20, -- active high, if the reactor PLC reports a device access fault
    R_PLC_TIMEOUT = 21  -- active high, if the reactor PLC has not been heard from
}

rsio.IO_LVL = IO_LVL
rsio.IO_DIR = IO_DIR
rsio.IO_MODE = IO_MODE
rsio.IO = IO_PORT

-----------------------
-- UTILITY FUNCTIONS --
-----------------------

-- port to string
---@param port IO_PORT
function rsio.to_string(port)
    local names = {
        "F_SCRAM",
        "R_SCRAM",
        "R_ENABLE",
        "F_ALARM",
        "WASTE_PU",
        "WASTE_PO",
        "WASTE_POPL",
        "WASTE_AM",
        "R_ALARM",
        "R_SCRAMMED",
        "R_AUTO_SCRAM",
        "R_ACTIVE",
        "R_AUTO_CTRL",
        "R_DMG_CRIT",
        "R_HIGH_TEMP",
        "R_NO_COOLANT",
        "R_EXCESS_HC",
        "R_EXCESS_WS",
        "R_INSUFF_FUEL",
        "R_PLC_FAULT",
        "R_PLC_TIMEOUT"
    }

    if util.is_int(port) and port > 0 and port <= #names then
        return names[port]
    else
        return ""
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
    -- R_SCRAM
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.IN  },
    -- R_ENABLE
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.IN  },
    -- F_ALARM
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- WASTE_PU
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
    -- WASTE_PO
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
    -- WASTE_POPL
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
    -- WASTE_AM
    { _in = _I_ACTIVE_LOW,  _out = _O_ACTIVE_LOW,  mode = IO_DIR.OUT },
    -- R_ALARM
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_SCRAMMED
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_AUTO_SCRAM
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_ACTIVE
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_AUTO_CTRL
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_DMG_CRIT
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_HIGH_TEMP
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_NO_COOLANT
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
    { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT }
}

-- get the mode of a port
---@param port IO_PORT
---@return IO_MODE
function rsio.get_io_mode(port)
    local modes = {
        IO_MODE.DIGITAL_IN,     -- F_SCRAM
        IO_MODE.DIGITAL_IN,     -- R_SCRAM
        IO_MODE.DIGITAL_IN,     -- R_ENABLE
        IO_MODE.DIGITAL_OUT,    -- F_ALARM
        IO_MODE.DIGITAL_OUT,    -- WASTE_PU
        IO_MODE.DIGITAL_OUT,    -- WASTE_PO
        IO_MODE.DIGITAL_OUT,    -- WASTE_POPL
        IO_MODE.DIGITAL_OUT,    -- WASTE_AM
        IO_MODE.DIGITAL_OUT,    -- R_ALARM
        IO_MODE.DIGITAL_OUT,    -- R_SCRAMMED
        IO_MODE.DIGITAL_OUT,    -- R_AUTO_SCRAM
        IO_MODE.DIGITAL_OUT,    -- R_ACTIVE
        IO_MODE.DIGITAL_OUT,    -- R_AUTO_CTRL
        IO_MODE.DIGITAL_OUT,    -- R_DMG_CRIT
        IO_MODE.DIGITAL_OUT,    -- R_HIGH_TEMP
        IO_MODE.DIGITAL_OUT,    -- R_NO_COOLANT
        IO_MODE.DIGITAL_OUT,    -- R_EXCESS_HC
        IO_MODE.DIGITAL_OUT,    -- R_EXCESS_WS
        IO_MODE.DIGITAL_OUT,    -- R_INSUFF_FUEL
        IO_MODE.DIGITAL_OUT,    -- R_PLC_FAULT
        IO_MODE.DIGITAL_OUT     -- R_PLC_TIMEOUT
    }

    if util.is_int(port) and port > 0 and port <= #modes then
        return modes[port]
    else
        return IO_MODE.ANALOG_IN
    end
end

--------------------
-- GENERIC CHECKS --
--------------------

local RS_SIDES = rs.getSides()

-- check if a port is valid
---@param port IO_PORT
---@return boolean valid
function rsio.is_valid_port(port)
    return util.is_int(port) and (port > 0) and (port <= IO_PORT.R_PLC_TIMEOUT)
end

-- check if a side is valid
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
---@param color integer
---@return boolean valid
function rsio.is_color(color)
    return util.is_int(color) and (color > 0) and (_B_AND(color, (color - 1)) == 0)
end

-----------------
-- DIGITAL I/O --
-----------------

-- get digital I/O level reading from a redstone boolean input value
---@param rs_value boolean
---@return IO_LVL
function rsio.digital_read(rs_value)
    if rs_value then
        return IO_LVL.HIGH
    else
        return IO_LVL.LOW
    end
end

-- get redstone boolean output value corresponding to a digital I/O level
---@param level IO_LVL
---@return boolean
function rsio.digital_write(level)
    return level == IO_LVL.HIGH
end

-- returns the level corresponding to active
---@param port IO_PORT
---@param active boolean
---@return IO_LVL|false
function rsio.digital_write_active(port, active)
    if (not util.is_int(port)) or (port < IO_PORT.F_ALARM) or (port > IO_PORT.R_PLC_TIMEOUT) then
        return false
    else
        return RS_DIO_MAP[port]._out(active)
    end
end

-- returns true if the level corresponds to active
---@param port IO_PORT
---@param level IO_LVL
---@return boolean|nil
function rsio.digital_is_active(port, level)
    if (not util.is_int(port)) or (port > IO_PORT.R_ENABLE) then
        return nil
    elseif level == IO_LVL.FLOATING or level == IO_LVL.DISCONNECT then
        return nil
    else
        return RS_DIO_MAP[port]._in(level)
    end
end

----------------
-- ANALOG I/O --
----------------

-- read an analog value scaled from min to max
---@param rs_value number redstone reading (0 to 15)
---@param min number minimum of range
---@param max number maximum of range
---@return number value scaled reading (min to max)
function rsio.analog_read(rs_value, min, max)
    local value = rs_value / 15
    return (value * (max - min)) + min
end

-- write an analog value from the provided scale range
---@param value number value to write (from min to max range)
---@param min number minimum of range
---@param max number maximum of range
---@return number rs_value scaled redstone reading (0 to 15)
function rsio.analog_write(value, min, max)
    local scaled_value = (value - min) / (max - min)
    return scaled_value * 15
end

return rsio
