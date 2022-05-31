local rtu = require("rtu.rtu")

local turbine_rtu = {}

-- create new turbine (mek 10.0) device
---@param turbine table
function turbine_rtu.new(turbine)
    local unit = rtu.init_unit()

    -- discrete inputs --
    -- none

    -- coils --
    -- none

    -- input registers --
    -- build properties
    unit.connect_input_reg(turbine.getBlades)
    unit.connect_input_reg(turbine.getCoils)
    unit.connect_input_reg(turbine.getVents)
    unit.connect_input_reg(turbine.getDispersers)
    unit.connect_input_reg(turbine.getCondensers)
    unit.connect_input_reg(turbine.getSteamCapacity)
    unit.connect_input_reg(turbine.getMaxFlowRate)
    unit.connect_input_reg(turbine.getMaxProduction)
    unit.connect_input_reg(turbine.getMaxWaterOutput)
    -- current state
    unit.connect_input_reg(turbine.getFlowRate)
    unit.connect_input_reg(turbine.getProductionRate)
    unit.connect_input_reg(turbine.getLastSteamInputRate)
    unit.connect_input_reg(turbine.getDumpingMode)
    -- tanks
    unit.connect_input_reg(turbine.getSteam)
    unit.connect_input_reg(turbine.getSteamNeeded)
    unit.connect_input_reg(turbine.getSteamFilledPercentage)

    -- holding registers --
    -- none

    return unit.interface()
end

return turbine_rtu
