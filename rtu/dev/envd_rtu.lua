local rtu = require("rtu.rtu")

local envd_rtu = {}

-- create new environment detector device
---@param envd table
function envd_rtu.new(envd)
    local unit = rtu.init_unit()

    -- discrete inputs --
    -- none

    -- coils --
    -- none

    -- input registers --
    unit.connect_input_reg(envd.getRadiation)
    unit.connect_input_reg(envd.getRadiationRaw)

    -- holding registers --
    -- none

    return unit.interface()
end

return envd_rtu
