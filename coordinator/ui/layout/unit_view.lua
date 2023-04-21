--
-- Reactor Unit SCADA Coordinator GUI
--

local unit_detail = require("coordinator.ui.components.unit_detail")

-- create a unit view
---@param main graphics_element main displaybox
---@param id integer
local function init(main, id)
    unit_detail(main, id)
end

return init
