---@class rtu_unit_qtypes
local qtypes = {}

-- turbine valve rtu session commands
local TBV_RTU_S_CMDS = {
    INC_DUMP_MODE = 1,
    DEC_DUMP_MODE = 2
}

-- turbine valve rtu session commands w/ parameters
local TBV_RTU_S_DATA = {
    SET_DUMP_MODE = 1
}

-- dynamic tank valve rtu session commands
local DTV_RTU_S_CMDS = {
    INC_CONT_MODE = 1,
    DEC_CONT_MODE = 2
}

-- dynamic tank valve rtu session commands w/ parameters
local DTV_RTU_S_DATA = {
    SET_CONT_MODE = 1
}

qtypes.TBV_RTU_S_CMDS = TBV_RTU_S_CMDS
qtypes.TBV_RTU_S_DATA = TBV_RTU_S_DATA
qtypes.DTV_RTU_S_CMDS = DTV_RTU_S_CMDS
qtypes.DTV_RTU_S_DATA = DTV_RTU_S_DATA

return qtypes
