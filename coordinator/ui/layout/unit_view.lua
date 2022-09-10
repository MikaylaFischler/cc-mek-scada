--
-- Reactor Unit SCADA Coordinator GUI
--

local tcallbackdsp = require("scada-common.tcallbackdsp")

local iocontrol    = require("coordinator.iocontrol")

local style        = require("coordinator.ui.style")

local unit_detail  = require("coordinator.ui.components.unit_detail")

local DisplayBox   = require("graphics.elements.displaybox")

-- create a unit view
---@param monitor table
---@param id integer
local function init(monitor, id)
    local main = DisplayBox{window=monitor,fg_bg=style.root}

    unit_detail(main, id)

    return main
end

return init
