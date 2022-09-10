--
-- Reactor Unit SCADA Coordinator GUI
--

local tcallbackdsp = require("scada-common.tcallbackdsp")

local iocontrol    = require("coordinator.iocontrol")

local style        = require("coordinator.ui.style")

local unit_wait    = require("coordinator.ui.components.unit_waiting")
local unit_detail  = require("coordinator.ui.components.unit_detail")

local core         = require("graphics.core")

local DisplayBox   = require("graphics.elements.displaybox")

local cpair = core.graphics.cpair
local border = core.graphics.border

-- create a unit view
---@param monitor table
---@param id integer
local function init(monitor, id)
    local main = DisplayBox{window=monitor,fg_bg=style.root}

    local waiting = unit_wait(main, 20)

    -- block waiting for initial status
    local function show_view()
        local unit = iocontrol.get_db().units[id]   ---@type ioctl_entry
        if unit.reactor_data.last_status_update ~= nil then
            waiting.hide()
            unit_detail(main, id)
        else
            tcallbackdsp.dispatch(1, show_view)
        end
    end

    tcallbackdsp.dispatch(1, show_view)

    return main
end

return init
