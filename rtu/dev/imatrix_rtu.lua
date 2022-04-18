-- #REQUIRES rtu.lua

function new(imatrix)
    local self = {
        rtu = rtu.rtu_init(),
        imatrix = imatrix
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
    self.rtu.connect_input_reg(self.imatrix.getTotalMaxEnergy)
    -- containers
    self.rtu.connect_input_reg(self.imatrix.getTotalEnergy)
    self.rtu.connect_input_reg(self.imatrix.getTotalEnergyNeeded)
    self.rtu.connect_input_reg(self.imatrix.getTotalEnergyFilledPercentage)

    -- holding registers --
    -- none

    return {
        rtu_interface = rtu_interface
    }
end
