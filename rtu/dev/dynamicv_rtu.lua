local rtu = require("rtu.rtu")

local dynamicv_rtu = {}

-- create new dynamic tank device
---@nodiscard
---@param dynamic_tank table
---@return rtu_device interface, boolean faulted
function dynamicv_rtu.new(dynamic_tank)
    local unit = rtu.init_unit()

    -- disable auto fault clearing
    dynamic_tank.__p_clear_fault()
    dynamic_tank.__p_disable_afc()

    -- discrete inputs --
    unit.connect_di(dynamic_tank.isFormed)

    -- coils --
    unit.connect_coil(function () dynamic_tank.incrementContainerEditMode() end, function () end)
    unit.connect_coil(function () dynamic_tank.decrementContainerEditMode() end, function () end)

    -- input registers --
    -- multiblock properties
    unit.connect_input_reg(dynamic_tank.getLength)
    unit.connect_input_reg(dynamic_tank.getWidth)
    unit.connect_input_reg(dynamic_tank.getHeight)
    unit.connect_input_reg(dynamic_tank.getMinPos)
    unit.connect_input_reg(dynamic_tank.getMaxPos)
    -- build properties
    unit.connect_input_reg(dynamic_tank.getTankCapacity)
    unit.connect_input_reg(dynamic_tank.getChemicalTankCapacity)
    -- tanks/containers
    unit.connect_input_reg(dynamic_tank.getStored)
    unit.connect_input_reg(dynamic_tank.getFilledPercentage)

    -- holding registers --
    unit.connect_holding_reg(dynamic_tank.getContainerEditMode, dynamic_tank.setContainerEditMode)

    -- check if any calls faulted
    local faulted = dynamic_tank.__p_is_faulted()
    dynamic_tank.__p_clear_fault()
    dynamic_tank.__p_enable_afc()

    return unit.interface(), faulted
end

return dynamicv_rtu
