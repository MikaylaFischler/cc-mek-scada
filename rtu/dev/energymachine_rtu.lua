-- #REQUIRES rtu.lua

function new(machine)
    local self = {
        rtu = rtu.rtu_init(),
        machine = machine
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
    self.rtu.connect_input_reg(self.machine.getTotalMaxEnergy)
    -- containers
    self.rtu.connect_input_reg(self.machine.getTotalEnergy)
    self.rtu.connect_input_reg(self.machine.getTotalEnergyNeeded)
    self.rtu.connect_input_reg(self.machine.getTotalEnergyFilledPercentage)

    -- holding registers --
    -- none

    return {
        rtu_interface = rtu_interface
    }
end
