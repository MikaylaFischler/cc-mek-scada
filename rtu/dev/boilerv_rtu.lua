local rtu = require("rtu.rtu")

local boilerv_rtu = {}

-- create new boiler device
---@nodiscard
---@param boiler table
---@return rtu_device interface, boolean faulted
function boilerv_rtu.new(boiler)
    local unit = rtu.init_unit()

    -- disable auto fault clearing
    boiler.__p_clear_fault()
    boiler.__p_disable_afc()

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

    -- check if any calls faulted
    local faulted = boiler.__p_is_faulted()
    boiler.__p_clear_fault()
    boiler.__p_enable_afc()

    return unit.interface(), faulted
end

return boilerv_rtu
