--
-- Flow Monitor GUI
--

local util          = require("scada-common.util")

local iocontrol     = require("coordinator.iocontrol")

local style         = require("coordinator.ui.style")

local flow_overview = require("coordinator.ui.components.flow_overview")

local core          = require("graphics.core")

local TextBox       = require("graphics.elements.textbox")

local DataIndicator = require("graphics.elements.indicators.data")

local TEXT_ALIGN = core.TEXT_ALIGN

local cpair = core.cpair

-- create new flow view
---@param main graphics_element main displaybox
local function init(main)
    local facility = iocontrol.get_db().facility
    local units = iocontrol.get_db().units

    -- window header message
    local header = TextBox{parent=main,y=1,text="Facility Coolant and Waste Flow Monitor",alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}
    -- max length example: "01:23:45 AM - Wednesday, September 28 2022"
    local datetime = TextBox{parent=main,x=(header.get_width()-42),y=1,text="",alignment=TEXT_ALIGN.RIGHT,width=42,height=1,fg_bg=style.header}

    datetime.register(facility.ps, "date_time", datetime.set_value)

    for i = 1, 4 do
        flow_overview(main, 25, 5 + ((i - 1) * 20), units[i])
    end
end

return init
