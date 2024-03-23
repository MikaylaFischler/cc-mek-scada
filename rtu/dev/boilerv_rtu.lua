local rtu = require("rtu.rtu")

local boilerv_rtu = {}

-- create new boiler device
---@nodiscard
---@param boiler table
---@return rtu_device interface, boolean faulted
function boilerv_rtu.new(boiler)
    local unit = rtu.init_unit(boiler)

    -- discrete inputs --
    unit.connect_di("isFormed")

    -- coils --
    -- none

    -- input registers --
    -- multiblock properties
    unit.connect_input_reg("getLength")
    unit.connect_input_reg("getWidth")
    unit.connect_input_reg("getHeight")
    unit.connect_input_reg("getMinPos")
    unit.connect_input_reg("getMaxPos")
    -- build properties
    unit.connect_input_reg("getBoilCapacity")
    unit.connect_input_reg("getSteamCapacity")
    unit.connect_input_reg("getWaterCapacity")
    unit.connect_input_reg("getHeatedCoolantCapacity")
    unit.connect_input_reg("getCooledCoolantCapacity")
    unit.connect_input_reg("getSuperheaters")
    unit.connect_input_reg("getMaxBoilRate")
    -- current state
    unit.connect_input_reg("getTemperature")
    unit.connect_input_reg("getBoilRate")
    unit.connect_input_reg("getEnvironmentalLoss")
    -- tanks
    unit.connect_input_reg("getSteam")
    unit.connect_input_reg("getSteamNeeded")
    unit.connect_input_reg("getSteamFilledPercentage")
    unit.connect_input_reg("getWater")
    unit.connect_input_reg("getWaterNeeded")
    unit.connect_input_reg("getWaterFilledPercentage")
    unit.connect_input_reg("getHeatedCoolant")
    unit.connect_input_reg("getHeatedCoolantNeeded")
    unit.connect_input_reg("getHeatedCoolantFilledPercentage")
    unit.connect_input_reg("getCooledCoolant")
    unit.connect_input_reg("getCooledCoolantNeeded")
    unit.connect_input_reg("getCooledCoolantFilledPercentage")

    -- holding registers --
    -- none

    return unit.interface(), false
end

return boilerv_rtu
