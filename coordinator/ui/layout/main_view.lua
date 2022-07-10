--
-- Main SCADA Coordinator GUI
--

local log = require("scada-common.log")

local database = require("coordinator.database")
local style    = require("coordinator.ui.style")

local core = require("graphics.core")

local DisplayBox = require("graphics.elements.displaybox")
local TextBox    = require("graphics.elements.textbox")

local unit_overview = require("coordinator.ui.components.unit_overview")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local function init(monitor)
    local main = DisplayBox{window=monitor,fg_bg=style.root}

    -- window header message
    TextBox{parent=main,text="Nuclear Generation Facility SCADA Coordinator",alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    local db = database.get()

    -- unit overviews
    if db.facility.num_units >= 1 then unit_overview(main, 2, 3, db.units[1]) end
    if db.facility.num_units >= 2 then unit_overview(main, 84, 3, db.units[2]) end
    if db.facility.num_units >= 3 then unit_overview(main, 2, 29, db.units[3]) end
    if db.facility.num_units == 4 then unit_overview(main, 84, 29, db.units[4]) end

    return main
end

return init
