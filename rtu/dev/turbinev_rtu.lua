local rtu = require("rtu.rtu")

local turbinev_rtu = {}

-- create new turbine (mek 10.1+) device
---@nodiscard
---@param turbine table
---@return rtu_device interface, boolean faulted
function turbinev_rtu.new(turbine)
    local unit = rtu.init_unit()

    -- disable auto fault clearing
    turbine.__p_clear_fault()
    turbine.__p_disable_afc()

    -- discrete inputs --
    unit.connect_di(turbine.isFormed)

    -- coils --
    unit.connect_coil(function () turbine.incrementDumpingMode() end, function () end)
    unit.connect_coil(function () turbine.decrementDumpingMode() end, function () end)

    -- input registers --
    -- multiblock properties
    unit.connect_input_reg(turbine.getLength)
    unit.connect_input_reg(turbine.getWidth)
    unit.connect_input_reg(turbine.getHeight)
    unit.connect_input_reg(turbine.getMinPos)
    unit.connect_input_reg(turbine.getMaxPos)
    -- build properties
    unit.connect_input_reg(turbine.getBlades)
    unit.connect_input_reg(turbine.getCoils)
    unit.connect_input_reg(turbine.getVents)
    unit.connect_input_reg(turbine.getDispersers)
    unit.connect_input_reg(turbine.getCondensers)
    unit.connect_input_reg(turbine.getSteamCapacity)
    unit.connect_input_reg(turbine.getMaxEnergy)
    unit.connect_input_reg(turbine.getMaxFlowRate)
    unit.connect_input_reg(turbine.getMaxProduction)
    unit.connect_input_reg(turbine.getMaxWaterOutput)
    -- current state
    unit.connect_input_reg(turbine.getFlowRate)
    unit.connect_input_reg(turbine.getProductionRate)
    unit.connect_input_reg(turbine.getLastSteamInputRate)
    unit.connect_input_reg(turbine.getDumpingMode)
    -- tanks/containers
    unit.connect_input_reg(turbine.getSteam)
    unit.connect_input_reg(turbine.getSteamNeeded)
    unit.connect_input_reg(turbine.getSteamFilledPercentage)
    unit.connect_input_reg(turbine.getEnergy)
    unit.connect_input_reg(turbine.getEnergyNeeded)
    unit.connect_input_reg(turbine.getEnergyFilledPercentage)

    -- holding registers --
    unit.connect_holding_reg(turbine.getDumpingMode, turbine.setDumpingMode)

    -- check if any calls faulted
    local faulted = turbine.__p_is_faulted()
    turbine.__p_clear_fault()
    turbine.__p_enable_afc()

    return unit.interface(), faulted
end

return turbinev_rtu
