local rtu = require("rtu.rtu")

local imatrix_rtu = {}

-- create new induction matrix (mek 10.1+) device
---@nodiscard
---@param imatrix table
function imatrix_rtu.new(imatrix)
    local unit = rtu.init_unit()

    -- discrete inputs --
    unit.connect_di(imatrix.isFormed)

    -- coils --
    -- none

    -- input registers --
    -- multiblock properties
    unit.connect_input_reg(imatrix.getLength)
    unit.connect_input_reg(imatrix.getWidth)
    unit.connect_input_reg(imatrix.getHeight)
    unit.connect_input_reg(imatrix.getMinPos)
    unit.connect_input_reg(imatrix.getMaxPos)
    -- build properties
    unit.connect_input_reg(imatrix.getMaxEnergy)
    unit.connect_input_reg(imatrix.getTransferCap)
    unit.connect_input_reg(imatrix.getInstalledCells)
    unit.connect_input_reg(imatrix.getInstalledProviders)
    -- I/O rates
    unit.connect_input_reg(imatrix.getLastInput)
    unit.connect_input_reg(imatrix.getLastOutput)
    -- tanks
    unit.connect_input_reg(imatrix.getEnergy)
    unit.connect_input_reg(imatrix.getEnergyNeeded)
    unit.connect_input_reg(imatrix.getEnergyFilledPercentage)

    -- holding registers --
    -- none

    return unit.interface()
end

return imatrix_rtu
