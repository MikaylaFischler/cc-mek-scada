local rtu = require("rtu.rtu")

local boiler_rtu = {}

-- create new boiler (mek 10.0) device
---@param boiler table
function boiler_rtu.new(boiler)
    local unit = rtu.init_unit()

    -- discrete inputs --
    -- none

    -- coils --
    -- none

    -- input registers --
    -- build properties
    unit.connect_input_reg(boiler.getBoilCapacity)
    unit.connect_input_reg(boiler.getSteamCapacity)
    unit.connect_input_reg(boiler.getWaterCapacity)
    unit.connect_input_reg(boiler.getHeatedCoolantCapacity)
    unit.connect_input_reg(boiler.getCooledCoolantCapacity)
    unit.connect_input_reg(boiler.getSuperheaters)
    unit.connect_input_reg(boiler.getMaxBoilRate)
    -- current state
    unit.connect_input_reg(boiler.getTemperature)
    unit.connect_input_reg(boiler.getBoilRate)
    -- tanks
    unit.connect_input_reg(boiler.getSteam)
    unit.connect_input_reg(boiler.getSteamNeeded)
    unit.connect_input_reg(boiler.getSteamFilledPercentage)
    unit.connect_input_reg(boiler.getWater)
    unit.connect_input_reg(boiler.getWaterNeeded)
    unit.connect_input_reg(boiler.getWaterFilledPercentage)
    unit.connect_input_reg(boiler.getHeatedCoolant)
    unit.connect_input_reg(boiler.getHeatedCoolantNeeded)
    unit.connect_input_reg(boiler.getHeatedCoolantFilledPercentage)
    unit.connect_input_reg(boiler.getCooledCoolant)
    unit.connect_input_reg(boiler.getCooledCoolantNeeded)
    unit.connect_input_reg(boiler.getCooledCoolantFilledPercentage)

    -- holding registers --
    -- none

    return unit.interface()
end

return boiler_rtu
