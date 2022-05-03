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
    -- @todo check these on Mekanism 10.1+
    -- build properties
    self.rtu.connect_input_reg(self.imatrix.getTransferCap)
    self.rtu.connect_input_reg(self.imatrix.getInstalledCells)
    self.rtu.connect_input_reg(self.imatrix.getInstalledProviders)
    self.rtu.connect_input_reg(self.imatrix.getTotalMaxEnergy)
    -- containers
    self.rtu.connect_input_reg(self.imatrix.getTotalEnergy)
    self.rtu.connect_input_reg(self.imatrix.getTotalEnergyNeeded)
    self.rtu.connect_input_reg(self.imatrix.getTotalEnergyFilledPercentage)
    -- additional fields? check these on 10.1
    self.rtu.connect_input_reg(self.imatrix.getInputItem)
    self.rtu.connect_input_reg(self.imatrix.getOutputItem)
    self.rtu.connect_input_reg(self.imatrix.getLastInput)
    self.rtu.connect_input_reg(self.imatrix.getLastOutput)

    -- holding registers --
    -- none

    return {
        rtu_interface = rtu_interface
    }
end
