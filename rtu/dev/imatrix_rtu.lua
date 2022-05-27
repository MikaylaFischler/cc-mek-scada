local rtu = require("rtu.rtu")

local imatrix_rtu = {}

-- create new induction matrix (mek 10.1+) device
---@param imatrix table
imatrix_rtu.new = function (imatrix)
    local self = {
        rtu = rtu.init_unit(),
        imatrix = imatrix
    }

    -- discrete inputs --
    self.rtu.connect_di(self.boiler.isFormed)

    -- coils --
    -- none

    -- input registers --
    -- multiblock properties
    self.rtu.connect_input_reg(self.boiler.getLength)
    self.rtu.connect_input_reg(self.boiler.getWidth)
    self.rtu.connect_input_reg(self.boiler.getHeight)
    self.rtu.connect_input_reg(self.boiler.getMinPos)
    self.rtu.connect_input_reg(self.boiler.getMaxPos)
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

    return self.rtu.interface()
end

return imatrix_rtu
