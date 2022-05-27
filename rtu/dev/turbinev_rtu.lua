local rtu = require("rtu.rtu")

local turbinev_rtu = {}

-- create new turbine (mek 10.1+) device
---@param turbine table
turbinev_rtu.new = function (turbine)
    local self = {
        rtu = rtu.init_unit(),
        turbine = turbine
    }

    -- discrete inputs --
    self.rtu.connect_di(self.boiler.isFormed)

    -- coils --
    self.rtu.connect_coil(function () self.turbine.incrementDumpingMode() end, function () end)
    self.rtu.connect_coil(function () self.turbine.decrementDumpingMode() end, function () end)

    -- input registers --
    -- multiblock properties
    self.rtu.connect_input_reg(self.boiler.getLength)
    self.rtu.connect_input_reg(self.boiler.getWidth)
    self.rtu.connect_input_reg(self.boiler.getHeight)
    self.rtu.connect_input_reg(self.boiler.getMinPos)
    self.rtu.connect_input_reg(self.boiler.getMaxPos)
    -- build properties
    self.rtu.connect_input_reg(self.turbine.getBlades)
    self.rtu.connect_input_reg(self.turbine.getCoils)
    self.rtu.connect_input_reg(self.turbine.getVents)
    self.rtu.connect_input_reg(self.turbine.getDispersers)
    self.rtu.connect_input_reg(self.turbine.getCondensers)
    self.rtu.connect_input_reg(self.turbine.getDumpingMode)
    self.rtu.connect_input_reg(self.turbine.getSteamCapacity)
    self.rtu.connect_input_reg(self.turbine.getMaxEnergy)
    self.rtu.connect_input_reg(self.turbine.getMaxFlowRate)
    self.rtu.connect_input_reg(self.turbine.getMaxWaterOutput)
    self.rtu.connect_input_reg(self.turbine.getMaxProduction)
    -- current state
    self.rtu.connect_input_reg(self.turbine.getFlowRate)
    self.rtu.connect_input_reg(self.turbine.getProductionRate)
    self.rtu.connect_input_reg(self.turbine.getLastSteamInputRate)
    -- tanks/containers
    self.rtu.connect_input_reg(self.turbine.getSteam)
    self.rtu.connect_input_reg(self.turbine.getSteamNeeded)
    self.rtu.connect_input_reg(self.turbine.getSteamFilledPercentage)
    self.rtu.connect_input_reg(self.turbine.getEnergy)
    self.rtu.connect_input_reg(self.turbine.getEnergyNeeded)
    self.rtu.connect_input_reg(self.turbine.getEnergyFilledPercentage)

    -- holding registers --
    self.rtu.connect_holding_reg(self.turbine.setDumpingMode, self.turbine.getDumpingMode)

    return self.rtu.interface()
end

return turbinev_rtu
