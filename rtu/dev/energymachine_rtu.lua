local rtu = require("rtu.rtu")

local energymachine_rtu = {}

-- create new energy machine device
---@param machine table
energymachine_rtu.new = function (machine)
    local self = {
        rtu = rtu.init_unit(),
        machine = machine
    }

    ---@class rtu_device
    local public = {}

    -- get the RTU interface
    public.rtu_interface = function () return self.rtu end

    -- discrete inputs --
    -- none

    -- coils --
    -- none

    -- input registers --
    -- build properties
    self.rtu.connect_input_reg(self.machine.getTotalMaxEnergy)
    -- containers
    self.rtu.connect_input_reg(self.machine.getTotalEnergy)
    self.rtu.connect_input_reg(self.machine.getTotalEnergyNeeded)
    self.rtu.connect_input_reg(self.machine.getTotalEnergyFilledPercentage)

    -- holding registers --
    -- none

    return public
end

return energymachine_rtu
