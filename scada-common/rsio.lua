IO_LVL = {
    LOW = 0,
    HIGH = 1
}

IO_DIR = {
    IN = 0,
    OUT = 1
}

IO_MODE = {
    DIGITAL_OUT = 0,
    DIGITAL_IN = 1,
    ANALOG_OUT = 2,
    ANALOG_IN = 3
}

RS_IO = {
    -- digital inputs --

    -- facility
    F_SCRAM       = 1,  -- active low, facility-wide scram
    F_AE2_LIVE    = 2,  -- active high, indicates whether AE2 network is online (hint: use redstone P2P)

    -- reactor
    R_SCRAM       = 3,  -- active low, reactor scram
    R_ENABLE      = 4,  -- active high, reactor enable

    -- digital outputs --

    -- waste
    WASTE_PO      = 5,  -- active low, polonium routing
    WASTE_PU      = 6,  -- active low, plutonium routing
    WASTE_AM      = 7,  -- active low, antimatter routing

    -- reactor
    R_SCRAMMED    = 8,  -- active high, if the reactor is scrammed
    R_AUTO_SCRAM  = 9,  -- active high, if the reactor was automatically scrammed
    R_ACTIVE      = 10, -- active high, if the reactor is active
    R_AUTO_CTRL   = 11, -- active high, if the reactor burn rate is automatic
    R_DMG_CRIT    = 12, -- active high, if the reactor damage is critical
    R_HIGH_TEMP   = 13, -- active high, if the reactor is at a high temperature
    R_NO_COOLANT  = 14, -- active high, if the reactor has no coolant
    R_EXCESS_HC   = 15, -- active high, if the reactor has excess heated coolant
    R_EXCESS_WS   = 16, -- active high, if the reactor has excess waste
    R_INSUFF_FUEL = 17, -- active high, if the reactor has insufficent fuel
    R_PLC_TIMEOUT = 18, -- active high, if the reactor PLC has not been heard from

    -- analog outputs --

    A_R_BURN_RATE = 19, -- reactor burn rate percentage
    A_B_BOIL_RATE = 20, -- boiler boil rate percentage
    A_T_FLOW_RATE = 21  -- turbine flow rate percentage
}

function to_string(channel)
    local names = {
        "F_SCRAM",
        "F_AE2_LIVE",
        "R_SCRAM",
        "R_ENABLE",
        "WASTE_PO",
        "WASTE_PU",
        "WASTE_AM",
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
        "R_PLC_TIMEOUT",
        "A_R_BURN_RATE",
        "A_B_BOIL_RATE",
        "A_T_FLOW_RATE"
    }

    if channel > 0 and channel <= #names then
        return names[channel]
    else
        return ""
    end
end

function is_valid_channel(channel)
    return channel > 0 and channel <= A_T_FLOW_RATE
end

function is_valid_side(side)
    for _, s in pairs(redstone.getSides()) do
        if s == side then return true end
    end
    return false
end

function is_color(color)
    return (color > 0) and (bit.band(color, (color - 1)) == 0);
end

local _TRINARY = function (cond, t, f) if cond then return t else return f end end

local _DI_ACTIVE_HIGH = function (level) return level == IO_LVL.HIGH end
local _DI_ACTIVE_LOW = function (level) return level == IO_LVL.LOW end
local _DO_ACTIVE_HIGH = function (on) return _TRINARY(on, IO_LVL.HIGH, IO_LVL.LOW) end
local _DO_ACTIVE_LOW = function (on) return _TRINARY(on, IO_LVL.LOW, IO_LVL.HIGH) end

-- I/O mappings to I/O function and I/O mode
local RS_DIO_MAP = {
    -- F_SCRAM
    { _f = _DI_ACTIVE_LOW,  mode = IO_DIR.IN },
    -- F_AE2_LIVE
    { _f = _DI_ACTIVE_HIGH, mode = IO_DIR.IN },
    -- R_SCRAM
    { _f = _DI_ACTIVE_LOW,  mode = IO_DIR.IN },
    -- R_ENABLE
    { _f = _DI_ACTIVE_HIGH, mode = IO_DIR.IN },
    -- WASTE_PO
    { _f = _DO_ACTIVE_LOW,  mode = IO_DIR.OUT },
    -- WASTE_PU
    { _f = _DO_ACTIVE_LOW,  mode = IO_DIR.OUT },
    -- WASTE_AM
    { _f = _DO_ACTIVE_LOW,  mode = IO_DIR.OUT },
    -- R_SCRAMMED
    { _f = _DO_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_AUTO_SCRAM
    { _f = _DO_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_ACTIVE
    { _f = _DO_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_AUTO_CTRL
    { _f = _DO_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_DMG_CRIT
    { _f = _DO_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_HIGH_TEMP
    { _f = _DO_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_NO_COOLANT
    { _f = _DO_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_EXCESS_HC
    { _f = _DO_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_EXCESS_WS
    { _f = _DO_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_INSUFF_FUEL
    { _f = _DO_ACTIVE_HIGH, mode = IO_DIR.OUT },
    -- R_PLC_TIMEOUT
    { _f = _DO_ACTIVE_HIGH, mode = IO_DIR.OUT }
}

function get_io_mode(channel)
    local modes = {
        IO_MODE.DIGITAL_IN,     -- F_SCRAM
        IO_MODE.DIGITAL_IN,     -- F_AE2_LIVE
        IO_MODE.DIGITAL_IN,     -- R_SCRAM
        IO_MODE.DIGITAL_IN,     -- R_ENABLE
        IO_MODE.DIGITAL_OUT,    -- WASTE_PO
        IO_MODE.DIGITAL_OUT,    -- WASTE_PU
        IO_MODE.DIGITAL_OUT,    -- WASTE_AM
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
        IO_MODE.DIGITAL_OUT,    -- R_PLC_TIMEOUT
        IO_MODE.ANALOG_OUT,     -- A_R_BURN_RATE
        IO_MODE.ANALOG_OUT,     -- A_B_BOIL_RATE
        IO_MODE.ANALOG_OUT      -- A_T_FLOW_RATE
    }

    if channel > 0 and channel <= #modes then
        return modes[channel]
    else
        return IO_MODE.ANALOG_IN
    end
end

-- get digital IO level reading
function digital_read(rs_value)
    if rs_value then
        return IO_LVL.HIGH
    else
        return IO_LVL.LOW
    end
end

-- returns the level corresponding to active
function digital_write(channel, active)
    if channel < RS_IO.WASTE_PO or channel > RS_IO.R_PLC_TIMEOUT then
        return IO_LVL.LOW
    else
        return RS_DIO_MAP[channel]._f(level)
    end
end

-- returns true if the level corresponds to active
function digital_is_active(channel, level)
    if channel > RS_IO.R_ENABLE or channel > RS_IO.R_PLC_TIMEOUT then
        return false
    else
        return RS_DIO_MAP[channel]._f(level)
    end
end
