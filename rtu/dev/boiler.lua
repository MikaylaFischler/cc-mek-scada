-- #REQUIRES rtu.lua

function boiler_rtu(boiler)
    local self = {
        rtu = rtu_init(),
        boiler = boiler
    }

    local rtu_interface = function ()
        return self.rtu
    end

    -- discrete inputs --
    -- none

    -- coils --
    -- none

    -- input registers --
    -- build properties
    self.rtu.connect_input_reg(self.boiler.getBoilCapacity)
    self.rtu.connect_input_reg(self.boiler.getSteamCapacity)
    self.rtu.connect_input_reg(self.boiler.getWaterCapacity)
    self.rtu.connect_input_reg(self.boiler.getHeatedCoolantCapacity)
    self.rtu.connect_input_reg(self.boiler.getCooledCoolantCapacity)
    self.rtu.connect_input_reg(self.boiler.getSuperheaters)
    self.rtu.connect_input_reg(self.boiler.getMaxBoilRate)
    -- current state
    self.rtu.connect_input_reg(self.boiler.getTemperature)
    self.rtu.connect_input_reg(self.boiler.getBoilRate)
    -- tanks
    self.rtu.connect_input_reg(self.boiler.getSteam)
    self.rtu.connect_input_reg(self.boiler.getSteamNeeded)
    self.rtu.connect_input_reg(self.boiler.getSteamFilledPercentage)
    self.rtu.connect_input_reg(self.boiler.getWater)
    self.rtu.connect_input_reg(self.boiler.getWaterNeeded)
    self.rtu.connect_input_reg(self.boiler.getWaterFilledPercentage)
    self.rtu.connect_input_reg(self.boiler.getHeatedCoolant)
    self.rtu.connect_input_reg(self.boiler.getHeatedCoolantNeeded)
    self.rtu.connect_input_reg(self.boiler.getHeatedCoolantFilledPercentage)
    self.rtu.connect_input_reg(self.boiler.getCooledCoolant)
    self.rtu.connect_input_reg(self.boiler.getCooledCoolantNeeded)
    self.rtu.connect_input_reg(self.boiler.getCooledCoolantFilledPercentage)

    -- holding registers --
    -- none

    return {
        rtu_interface = rtu_interface
    }
end
