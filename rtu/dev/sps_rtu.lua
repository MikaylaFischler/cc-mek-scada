local rtu = require("rtu.rtu")

local sps_rtu = {}

-- create new super-critical phase shifter (SPS) device
---@nodiscard
---@param sps table
function sps_rtu.new(sps)
    local unit = rtu.init_unit()

    -- discrete inputs --
    unit.connect_di(sps.isFormed)

    -- coils --
    -- none

    -- input registers --
    -- multiblock properties
    unit.connect_input_reg(sps.getLength)
    unit.connect_input_reg(sps.getWidth)
    unit.connect_input_reg(sps.getHeight)
    unit.connect_input_reg(sps.getMinPos)
    unit.connect_input_reg(sps.getMaxPos)
    -- build properties
    unit.connect_input_reg(sps.getCoils)
    unit.connect_input_reg(sps.getInputCapacity)
    unit.connect_input_reg(sps.getOutputCapacity)
    unit.connect_input_reg(sps.getMaxEnergy)
    -- current state
    unit.connect_input_reg(sps.getProcessRate)
    -- tanks
    unit.connect_input_reg(sps.getInput)
    unit.connect_input_reg(sps.getInputNeeded)
    unit.connect_input_reg(sps.getInputFilledPercentage)
    unit.connect_input_reg(sps.getOutput)
    unit.connect_input_reg(sps.getOutputNeeded)
    unit.connect_input_reg(sps.getOutputFilledPercentage)
    unit.connect_input_reg(sps.getEnergy)
    unit.connect_input_reg(sps.getEnergyNeeded)
    unit.connect_input_reg(sps.getEnergyFilledPercentage)

    -- holding registers --
    -- none

    return unit.interface()
end

return sps_rtu
