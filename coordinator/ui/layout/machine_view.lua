--
-- Reactor Unit SCADA Coordinator GUI
--

local unit_detail = require("coordinator.ui.components.unit_overview")
local iocontrol   = require("coordinator.iocontrol")
-- create a unit view
---@param main DisplayBox main displaybox
---@param id integer
local function init(main, id)
    local db = iocontrol.get_db()
    local unit = db.units[id]
    unit_detail(main, 1, 1, unit)
end

return init