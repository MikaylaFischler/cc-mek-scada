local rtu = require("rtu.rtu")

local boilerv_rtu = {}

-- create new boiler (mek 10.1+) device
---@nodiscard
---@param boiler table
function boilerv_rtu.new(boiler)
    local unit = rtu.init_unit()

    -- discrete inputs --
    unit.connect_di(boiler.isFormed)

    -- coils --
    -- none

    -- input registers --
    -- multiblock properties
    unit.connect_input_reg(boiler.getLength)
    unit.connect_input_reg(boiler.getWidth)
    unit.connect_input_reg(boiler.getHeight)
    unit.connect_input_reg(boiler.getMinPos)
    unit.connect_input_reg(boiler.getMaxPos)
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
    unit.connect_input_reg(boiler.getEnvironmentalLoss)
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

return boilerv_rtu
