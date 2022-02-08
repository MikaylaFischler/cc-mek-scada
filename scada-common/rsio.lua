RS_IO = {
    -- digital inputs --

    -- facility
    F_SCRAM,    -- active high, facility-wide scram
    F_AE2_LIVE, -- active high, indicates whether AE2 network is online (hint: use redstone P2P)

    -- reactor
    R_SCRAM,    -- active high, reactor scram
    R_ENABLE,   -- active high, reactor enable

    -- digital outputs --

    -- waste
    WASTE_PO,   -- active low, polonium routing
    WASTE_PU,   -- active low, plutonium routing
    WASTE_AM,   -- active low, antimatter routing

    -- reactor
    R_SCRAMMED,     -- if the reactor is scrammed
    R_AUTO_SCRAM,   -- if the reactor was automatically scrammed
    R_ACTIVE,       -- if the reactor is active
    R_AUTO_CTRL,    -- if the reactor burn rate is automatic
    R_DMG_CRIT,     -- if the reactor damage is critical
    R_HIGH_TEMP,    -- if the reactor is at a high temperature
    R_NO_COOLANT,   -- if the reactor has no coolant
    R_EXCESS_HC,    -- if the reactor has excess heated coolant
    R_EXCESS_WS,    -- if the reactor has excess waste
    R_INSUFF_FUEL,  -- if the reactor has insufficent fuel
    R_PLC_TIMEOUT,  -- if the reactor PLC has not been heard from

    -- analog outputs --

    A_R_BURN_RATE,  -- reactor burn rate percentage
    A_B_BOIL_RATE,  -- boiler boil rate percentage
    A_T_FLOW_RATE   -- turbine flow rate percentage
}
