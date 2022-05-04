-- #REQUIRES rtu.lua

function new(turbine)
    local self = {
        rtu = rtu.rtu_init(),
        turbine = turbine
    }

    local rtu_interface = function ()
        return self.rtu
    end

    -- discrete inputs --
    -- none

    -- coils --
    self.rtu.connect_coil(function () self.turbine.incrementDumpingMode() end), function () end)
    self.rtu.connect_coil(function () self.turbine.decrementDumpingMode() end), function () end)

    -- input registers --
    -- multiblock properties
    self.rtu.connect_input_reg(self.boiler.isFormed)
    self.rtu.connect_input_reg(self.boiler.getLength)
    self.rtu.connect_input_reg(self.boiler.getWidth)
    self.rtu.connect_input_reg(self.boiler.getHeight)
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
    self.rtu.conenct_holding_reg(self.turbine.setDumpingMode, self.turbine.getDumpingMode)

    return {
        rtu_interface = rtu_interface
    }
end
