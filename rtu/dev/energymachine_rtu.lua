local rtu = require("rtu.rtu")

local energymachine_rtu = {}

-- create new energy machine device
---@param machine table
function energymachine_rtu.new(machine)
    local unit = rtu.init_unit()

    -- discrete inputs --
    -- none

    -- coils --
    -- none

    -- input registers --
    -- build properties
    unit.connect_input_reg(machine.getTotalMaxEnergy)
    -- containers
    unit.connect_input_reg(machine.getTotalEnergy)
    unit.connect_input_reg(machine.getTotalEnergyNeeded)
    unit.connect_input_reg(machine.getTotalEnergyFilledPercentage)

    -- holding registers --
    -- none

    return unit.interface()
end

return energymachine_rtu
