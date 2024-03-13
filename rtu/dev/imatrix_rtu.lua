local rtu = require("rtu.rtu")

local imatrix_rtu = {}

-- create new induction matrix (mek 10.1+) device
---@nodiscard
---@param imatrix table
---@return rtu_device interface, boolean faulted
function imatrix_rtu.new(imatrix)
    local unit = rtu.init_unit(imatrix)

    -- disable auto fault clearing
    imatrix.__p_clear_fault()
    imatrix.__p_disable_afc()

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

    -- check if any calls faulted
    local faulted = imatrix.__p_is_faulted()
    imatrix.__p_clear_fault()
    imatrix.__p_enable_afc()

    return unit.interface(), faulted
end

return imatrix_rtu
