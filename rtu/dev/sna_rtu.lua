local rtu = require("rtu.rtu")

local sna_rtu = {}

-- create new solar neutron activator (SNA) device
---@nodiscard
---@param sna table
---@return rtu_device interface, boolean faulted
function sna_rtu.new(sna)
    local unit = rtu.init_unit(sna)

    -- disable auto fault clearing
    sna.__p_clear_fault()
    sna.__p_disable_afc()

    -- discrete inputs --
    -- none

    -- coils --
    -- none

    -- input registers --
    -- build properties
    unit.connect_input_reg(sna.getInputCapacity)
    unit.connect_input_reg(sna.getOutputCapacity)
    -- current state
    unit.connect_input_reg(sna.getProductionRate)
    unit.connect_input_reg(sna.getPeakProductionRate)
    -- tanks
    unit.connect_input_reg(sna.getInput)
    unit.connect_input_reg(sna.getInputNeeded)
    unit.connect_input_reg(sna.getInputFilledPercentage)
    unit.connect_input_reg(sna.getOutput)
    unit.connect_input_reg(sna.getOutputNeeded)
    unit.connect_input_reg(sna.getOutputFilledPercentage)

    -- holding registers --
    -- none

    -- check if any calls faulted
    local faulted = sna.__p_is_faulted()
    sna.__p_clear_fault()
    sna.__p_enable_afc()

    return unit.interface(), faulted
end

return sna_rtu
