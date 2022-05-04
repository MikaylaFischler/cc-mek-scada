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
    -- multiblock properties
    self.rtu.connect_input_reg(self.boiler.isFormed)
    self.rtu.connect_input_reg(self.boiler.getLength)
    self.rtu.connect_input_reg(self.boiler.getWidth)
    self.rtu.connect_input_reg(self.boiler.getHeight)
    -- build properties
    self.rtu.connect_input_reg(self.imatrix.getMaxEnergy)
    self.rtu.connect_input_reg(self.imatrix.getTransferCap)
    self.rtu.connect_input_reg(self.imatrix.getInstalledCells)
    self.rtu.connect_input_reg(self.imatrix.getInstalledProviders)
    -- containers
    self.rtu.connect_input_reg(self.imatrix.getEnergy)
    self.rtu.connect_input_reg(self.imatrix.getEnergyNeeded)
    self.rtu.connect_input_reg(self.imatrix.getEnergyFilledPercentage)
    -- I/O rates
    self.rtu.connect_input_reg(self.imatrix.getLastInput)
    self.rtu.connect_input_reg(self.imatrix.getLastOutput)

    -- holding registers --
    -- none

    return {
        rtu_interface = rtu_interface
    }
end
