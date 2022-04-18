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
    -- none

    -- input registers --
    -- build properties
    self.rtu.connect_input_reg(self.turbine.getBlades)
    self.rtu.connect_input_reg(self.turbine.getCoils)
    self.rtu.connect_input_reg(self.turbine.getVents)
    self.rtu.connect_input_reg(self.turbine.getDispersers)
    self.rtu.connect_input_reg(self.turbine.getCondensers)
    self.rtu.connect_input_reg(self.turbine.getDumpingMode)
    self.rtu.connect_input_reg(self.turbine.getSteamCapacity)
    self.rtu.connect_input_reg(self.turbine.getMaxFlowRate)
    self.rtu.connect_input_reg(self.turbine.getMaxWaterOutput)
    self.rtu.connect_input_reg(self.turbine.getMaxProduction)
    -- current state
    self.rtu.connect_input_reg(self.turbine.getFlowRate)
    self.rtu.connect_input_reg(self.turbine.getProductionRate)
    self.rtu.connect_input_reg(self.turbine.getLastSteamInputRate)
    -- tanks
    self.rtu.connect_input_reg(self.turbine.getSteam)
    self.rtu.connect_input_reg(self.turbine.getSteamNeeded)
    self.rtu.connect_input_reg(self.turbine.getSteamFilledPercentage)

    -- holding registers --
    -- none

    return {
        rtu_interface = rtu_interface
    }
end
