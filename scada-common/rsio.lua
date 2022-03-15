IO_LVL = {
    LOW = 0,
    HIGH = 1
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

local _TRINARY = function (cond, t, f) if cond then return t else return f end end

local _DI_ACTIVE_HIGH = function (level) return level == IO_LVL.HIGH end
local _DI_ACTIVE_LOW = function (level) return level == IO_LVL.LOW end
local _DO_ACTIVE_HIGH = function (on) return _TRINARY(on, IO_LVL.HIGH, IO_LVL.LOW) end
local _DO_ACTIVE_LOW = function (on) return _TRINARY(on, IO_LVL.LOW, IO_LVL.HIGH) end

local RS_DIO_MAP = {
    -- F_SCRAM
    _DI_ACTIVE_LOW,
    -- F_AE2_LIVE
    _DI_ACTIVE_HIGH,
    -- R_SCRAM
    _DI_ACTIVE_LOW,
    -- R_ENABLE
    _DI_ACTIVE_HIGH,
    -- WASTE_PO
    _DO_ACTIVE_LOW,
    -- WASTE_PU
    _DO_ACTIVE_LOW,
    -- WASTE_AM
    _DO_ACTIVE_LOW,
    -- R_SCRAMMED
    _DO_ACTIVE_HIGH,
    -- R_AUTO_SCRAM
    _DO_ACTIVE_HIGH,
    -- R_ACTIVE
    _DO_ACTIVE_HIGH,
    -- R_AUTO_CTRL
    _DO_ACTIVE_HIGH,
    -- R_DMG_CRIT
    _DO_ACTIVE_HIGH,
    -- R_HIGH_TEMP
    _DO_ACTIVE_HIGH,
    -- R_NO_COOLANT
    _DO_ACTIVE_HIGH,
    -- R_EXCESS_HC
    _DO_ACTIVE_HIGH,
    -- R_EXCESS_WS
    _DO_ACTIVE_HIGH,
    -- R_INSUFF_FUEL
    _DO_ACTIVE_HIGH,
    -- R_PLC_TIMEOUT
    _DO_ACTIVE_HIGH
}

-- get digital IO level reading
function digital_input_read(rs_value)
    if rs_value then
        return IO_LVL.HIGH
    else
        return IO_LVL.LOW
    end
end

-- returns true if the level corresponds to active
function digital_input_is_active(channel, level)
    if channel > RS_IO.R_ENABLE then
        return false
    else
        return RS_DIO_MAP[channel](level)
    end
end

-- returns the level corresponding to active
function digital_output_write(channel, active)
    if channel < RS_IO.WASTE_PO or channel > RS_IO.R_PLC_TIMEOUT then
        return IO_LVL.LOW
    else
        return RS_DIO_MAP[channel](level)
    end
end
