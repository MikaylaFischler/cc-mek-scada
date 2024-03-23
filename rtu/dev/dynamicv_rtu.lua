local rtu = require("rtu.rtu")

local dynamicv_rtu = {}

-- create new dynamic tank device
---@nodiscard
---@param dynamic_tank table
---@return rtu_device interface, boolean faulted
function dynamicv_rtu.new(dynamic_tank)
    local unit = rtu.init_unit(dynamic_tank)

    -- discrete inputs --
    unit.connect_di("isFormed")

    -- coils --
    unit.connect_coil(function () dynamic_tank.incrementContainerEditMode() end, function () end)
    unit.connect_coil(function () dynamic_tank.decrementContainerEditMode() end, function () end)

    -- input registers --
    -- multiblock properties
    unit.connect_input_reg("getLength")
    unit.connect_input_reg("getWidth")
    unit.connect_input_reg("getHeight")
    unit.connect_input_reg("getMinPos")
    unit.connect_input_reg("getMaxPos")
    -- build properties
    unit.connect_input_reg("getTankCapacity")
    unit.connect_input_reg("getChemicalTankCapacity")
    -- tanks/containers
    unit.connect_input_reg("getStored")
    unit.connect_input_reg("getFilledPercentage")

    -- holding registers --
    unit.connect_holding_reg("getContainerEditMode", "setContainerEditMode")

    return unit.interface(), false
end

return dynamicv_rtu
