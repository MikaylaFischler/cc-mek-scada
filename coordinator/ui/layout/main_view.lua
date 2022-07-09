--
-- Main SCADA Coordinator GUI
--

local core   = require("graphics.core")
local log    = require("scada-common.log")

local style  = require("coordinator.ui.style")

local DisplayBox = require("graphics.elements.displaybox")
local TextBox    = require("graphics.elements.textbox")

local unit_overview = require("coordinator.ui.components.unit_overview")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local function init(monitor)
    local main = DisplayBox{window=monitor,fg_bg=style.root}

    -- window header message
    TextBox{parent=main,text="Nuclear Generation Facility SCADA Coordinator",alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    -- unit overviews
    unit_overview(main, 2, 3, 1)
    unit_overview(main, 84, 3, 2)
    unit_overview(main, 2, 29, 3)
    unit_overview(main, 84, 29, 4)

    return main
end

return init
