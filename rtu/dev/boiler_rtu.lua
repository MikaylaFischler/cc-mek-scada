local rtu = require("rtu.rtu")

local boiler_rtu = {}

-- create new boiler (mek 10.0) device
---@param boiler table
boiler_rtu.new = function (boiler)
    local self = {
        rtu = rtu.init_unit(),
        boiler = boiler
    }

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

    return self.rtu.interface()
end

return boiler_rtu
