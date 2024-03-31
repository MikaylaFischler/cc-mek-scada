local rtu = require("rtu.rtu")

local turbinev_rtu = {}

-- create new turbine device
---@nodiscard
---@param turbine table
---@return rtu_device interface, boolean faulted
function turbinev_rtu.new(turbine)
    local unit = rtu.init_unit(turbine)

    -- discrete inputs --
    unit.connect_di("isFormed")

    -- coils --
    unit.connect_coil(function () turbine.incrementDumpingMode() end, function () end)
    unit.connect_coil(function () turbine.decrementDumpingMode() end, function () end)

    -- input registers --
    -- multiblock properties
    unit.connect_input_reg("getLength")
    unit.connect_input_reg("getWidth")
    unit.connect_input_reg("getHeight")
    unit.connect_input_reg("getMinPos")
    unit.connect_input_reg("getMaxPos")
    -- build properties
    unit.connect_input_reg("getBlades")
    unit.connect_input_reg("getCoils")
    unit.connect_input_reg("getVents")
    unit.connect_input_reg("getDispersers")
    unit.connect_input_reg("getCondensers")
    unit.connect_input_reg("getSteamCapacity")
    unit.connect_input_reg("getMaxEnergy")
    unit.connect_input_reg("getMaxFlowRate")
    unit.connect_input_reg("getMaxProduction")
    unit.connect_input_reg("getMaxWaterOutput")
    -- current state
    unit.connect_input_reg("getFlowRate")
    unit.connect_input_reg("getProductionRate")
    unit.connect_input_reg("getLastSteamInputRate")
    unit.connect_input_reg("getDumpingMode")
    -- tanks/containers
    unit.connect_input_reg("getSteam")
    unit.connect_input_reg("getSteamNeeded")
    unit.connect_input_reg("getSteamFilledPercentage")
    unit.connect_input_reg("getEnergy")
    unit.connect_input_reg("getEnergyNeeded")
    unit.connect_input_reg("getEnergyFilledPercentage")

    -- holding registers --
    unit.connect_holding_reg("getDumpingMode", "setDumpingMode")

    return unit.interface(), false
end

return turbinev_rtu
