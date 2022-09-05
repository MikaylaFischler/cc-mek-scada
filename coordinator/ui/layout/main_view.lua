--
-- Main SCADA Coordinator GUI
--

local database      = require("coordinator.database")

local style         = require("coordinator.ui.style")

local unit_overview = require("coordinator.ui.components.unit_overview")

local core          = require("graphics.core")

local DisplayBox    = require("graphics.elements.displaybox")
local TextBox       = require("graphics.elements.textbox")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local function init(monitor)
    local main = DisplayBox{window=monitor,fg_bg=style.root}

    -- window header message
    TextBox{parent=main,text="Nuclear Generation Facility SCADA Coordinator",alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    local db = database.get()

    local uo_1, uo_2, uo_3, uo_4    ---@type graphics_element

    -- unit overviews
    if db.facility.num_units >= 1 then uo_1 = unit_overview(main, 2, 3, db.units[1]) end
    if db.facility.num_units >= 2 then uo_2 = unit_overview(main, 84, 3, db.units[2]) end

    if db.facility.num_units >= 3 then
        -- base offset 3, spacing 1, max height of units 1 and 2
        local row_2_offset = 3 + 1 + math.max(uo_1.height(), uo_2.height())

        uo_3 = unit_overview(main, 2, row_2_offset, db.units[3])
        if db.facility.num_units == 4 then uo_4 = unit_overview(main, 84, row_2_offset, db.units[4]) end
    end

    -- command & control

    return main
end

return init
