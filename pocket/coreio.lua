--
-- Core I/O - Pocket Central I/O Management
--

local psil = require("scada-common.psil")

local coreio = {}

---@class pocket_core_io
local io = {
    ps = psil.create()
}

---@enum POCKET_LINK_STATE
local LINK_STATE = {
    UNLINKED = 0,
    SV_LINK_ONLY = 1,
    API_LINK_ONLY = 2,
    LINKED = 3
}

coreio.LINK_STATE = LINK_STATE

-- get the core PSIL
function coreio.core_ps()
    return io.ps
end

-- set network link state
---@param state POCKET_LINK_STATE
function coreio.report_link_state(state)
    io.ps.publish("link_state", state)
end

return coreio
