-- message queue types used in session queues

local svqtypes = {}

---@enum SV_Q_CMDS
local SV_Q_CMDS = {
}

---@enum SV_Q_DATA
local SV_Q_DATA = {
    START = 1,
    SCRAM = 2,
    RESET_RPS = 3,
    SET_BURN = 4,
    __END_PLC_CMDS__ = 5,
    CRDN_ACK = 6,
    PLC_BUILD_CHANGED = 7,
    RTU_BUILD_CHANGED = 8,
    __END_CRD_CMDS__ = 9,
    SWITCH_NIC = 10,
    SWITCHED_NIC = 11
}

---@class coord_ack
---@field unit integer
---@field cmd integer
---@field ack boolean

svqtypes.SV_Q_CMDS = SV_Q_CMDS
svqtypes.SV_Q_DATA = SV_Q_DATA

return svqtypes
