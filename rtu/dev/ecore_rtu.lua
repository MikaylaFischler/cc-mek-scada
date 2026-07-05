local rtu = require("rtu.rtu")

local ecore_rtu = {}

-- create new draconic evolution energy core device
---@nodiscard
---@param ecore DraconicEnergyCore|ppm_generic
---@return rtu_device interface, boolean faulted
function ecore_rtu.new(ecore)
    local unit = rtu.init_unit(ecore)

    -- discrete inputs --
    -- none

    -- coils --
    -- none

    -- input registers --
    -- build properties
    unit.connect_input_reg("getMaxEnergyStored")
    -- I/O rates
    unit.connect_input_reg("getInputPerTick")
    unit.connect_input_reg("getOutputPerTick")
    unit.connect_input_reg("getTransferPerTick")
    -- tanks
    unit.connect_input_reg("getEnergyStored")

    -- holding registers --
    -- none

    return unit.interface(), false
end

return ecore_rtu
