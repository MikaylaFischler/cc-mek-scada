local rtu = require("rtu.rtu")

local sps_rtu = {}

-- create new super-critical phase shifter (SPS) device
---@nodiscard
---@param sps table
---@return rtu_device interface, boolean faulted
function sps_rtu.new(sps)
    local unit = rtu.init_unit(sps)

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
    unit.connect_input_reg("getCoils")
    unit.connect_input_reg("getInputCapacity")
    unit.connect_input_reg("getOutputCapacity")
    unit.connect_input_reg("getMaxEnergy")
    -- current state
    unit.connect_input_reg("getProcessRate")
    -- tanks
    unit.connect_input_reg("getInput")
    unit.connect_input_reg("getInputNeeded")
    unit.connect_input_reg("getInputFilledPercentage")
    unit.connect_input_reg("getOutput")
    unit.connect_input_reg("getOutputNeeded")
    unit.connect_input_reg("getOutputFilledPercentage")
    unit.connect_input_reg("getEnergy")
    unit.connect_input_reg("getEnergyNeeded")
    unit.connect_input_reg("getEnergyFilledPercentage")

    -- holding registers --
    -- none

    return unit.interface(), false
end

return sps_rtu
