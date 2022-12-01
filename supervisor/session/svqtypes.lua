local svqtypes = {}

local SV_Q_CMDS = {
    BUILD_CHANGED = 1
}

local SV_Q_DATA = {
    START = 1,
    SCRAM = 2,
    RESET_RPS = 3,
    SET_BURN = 4,
    __END_PLC_CMDS__ = 5,
    CRDN_ACK = 6
}

---@class coord_ack
---@field unit integer
---@field cmd integer
---@field ack boolean

svqtypes.SV_Q_CMDS = SV_Q_CMDS
svqtypes.SV_Q_DATA = SV_Q_DATA

return svqtypes
