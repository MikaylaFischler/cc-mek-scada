local svqtypes = {}

local SV_Q_CMDS = {
    BUILD_CHANGED = 1
}

local SV_Q_DATA = {
    START = 1,
    SCRAM = 2,
    RESET_RPS = 3,
    SET_BURN = 4,
    SET_WASTE = 5
}

svqtypes.SV_Q_CMDS = SV_Q_CMDS
svqtypes.SV_Q_DATA = SV_Q_DATA

return svqtypes
