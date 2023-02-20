local svqtypes = {}

local SV_Q_CMDS = {
}

local SV_Q_DATA = {
    START = 1,
    SCRAM = 2,
    RESET_RPS = 3,
    SET_BURN = 4,
    __END_PLC_CMDS__ = 5,
    CRDN_ACK = 6,
    PLC_BUILD_CHANGED = 7,
    RTU_BUILD_CHANGED = 8
}

---@class coord_ack
---@field unit integer
---@field cmd integer
---@field ack boolean

svqtypes.SV_Q_CMDS = SV_Q_CMDS
svqtypes.SV_Q_DATA = SV_Q_DATA

return svqtypes
