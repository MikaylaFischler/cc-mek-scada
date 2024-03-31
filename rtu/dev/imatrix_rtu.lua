local rtu = require("rtu.rtu")

local imatrix_rtu = {}

-- create new induction matrix (mek 10.1+) device
---@nodiscard
---@param imatrix table
---@return rtu_device interface, boolean faulted
function imatrix_rtu.new(imatrix)
    local unit = rtu.init_unit(imatrix)

    -- discrete inputs --
    unit.connect_di("isFormed")

    -- coils --
    -- none

    -- input registers --
    -- multiblock properties
    unit.connect_input_reg("getLength")
    unit.connect_input_reg("getWidth")
    unit.connect_input_reg("getHeight")
    unit.connect_input_reg("getMinPos")
    unit.connect_input_reg("getMaxPos")
    -- build properties
    unit.connect_input_reg("getMaxEnergy")
    unit.connect_input_reg("getTransferCap")
    unit.connect_input_reg("getInstalledCells")
    unit.connect_input_reg("getInstalledProviders")
    -- I/O rates
    unit.connect_input_reg("getLastInput")
    unit.connect_input_reg("getLastOutput")
    -- tanks
    unit.connect_input_reg("getEnergy")
    unit.connect_input_reg("getEnergyNeeded")
    unit.connect_input_reg("getEnergyFilledPercentage")

    -- holding registers --
    -- none

    return unit.interface(), false
end

return imatrix_rtu
