---@class rtu_unit_qtypes
local qtypes = {}

local TBV_RTU_S_CMDS = {
    INC_DUMP_MODE = 1,
    DEC_DUMP_MODE = 2
}

local TBV_RTU_S_DATA = {
    SET_DUMP_MODE = 1
}

qtypes.TBV_RTU_S_CMDS = TBV_RTU_S_CMDS
qtypes.TBV_RTU_S_DATA = TBV_RTU_S_DATA

return qtypes
