local rtu = require("rtu.rtu")

local envd_rtu = {}

-- create new environment detector device
---@nodiscard
---@param envd table
---@return rtu_device interface, boolean faulted
function envd_rtu.new(envd)
    local unit = rtu.init_unit(envd)

    -- disable auto fault clearing
    envd.__p_clear_fault()
    envd.__p_disable_afc()

    -- discrete inputs --
    -- none

    -- coils --
    -- none

    -- input registers --
    unit.connect_input_reg(envd.getRadiation)
    unit.connect_input_reg(envd.getRadiationRaw)

    -- holding registers --
    -- none

    -- check if any calls faulted
    local faulted = envd.__p_is_faulted()
    envd.__p_clear_fault()
    envd.__p_enable_afc()

    return unit.interface(), faulted
end

return envd_rtu
