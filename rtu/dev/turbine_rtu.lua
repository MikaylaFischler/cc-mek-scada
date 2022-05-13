local rtu = require("rtu.rtu")

local turbine_rtu = {}

-- create new turbine (mek 10.0) device
---@param turbine table
turbine_rtu.new = function (turbine)
    local self = {
        rtu = rtu.init_unit(),
        turbine = turbine
    }

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
    self.rtu.connect_input_reg(self.turbine.getSteamCapacity)
    self.rtu.connect_input_reg(self.turbine.getMaxFlowRate)
    self.rtu.connect_input_reg(self.turbine.getMaxProduction)
    self.rtu.connect_input_reg(self.turbine.getMaxWaterOutput)
    -- current state
    self.rtu.connect_input_reg(self.turbine.getFlowRate)
    self.rtu.connect_input_reg(self.turbine.getProductionRate)
    self.rtu.connect_input_reg(self.turbine.getLastSteamInputRate)
    self.rtu.connect_input_reg(self.turbine.getDumpingMode)
    -- tanks
    self.rtu.connect_input_reg(self.turbine.getSteam)
    self.rtu.connect_input_reg(self.turbine.getSteamNeeded)
    self.rtu.connect_input_reg(self.turbine.getSteamFilledPercentage)

    -- holding registers --
    -- none

    return self.rtu.interface()
end

return turbine_rtu
