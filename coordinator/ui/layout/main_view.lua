--
-- Main SCADA Coordinator GUI
--

local util          = require("scada-common.util")

local iocontrol     = require("coordinator.iocontrol")

local style         = require("coordinator.ui.style")

local imatrix       = require("coordinator.ui.components.imatrix")
local process_ctl   = require("coordinator.ui.components.process_ctl")
local unit_overview = require("coordinator.ui.components.unit_overview")

local core          = require("graphics.core")

local TextBox       = require("graphics.elements.TextBox")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")

local ALIGN = core.ALIGN

-- create new main view
---@param main DisplayBox main displaybox
local function init(main)
    local s_header = style.theme.header

    local facility = iocontrol.get_db().facility
    local units = iocontrol.get_db().units

    -- window header message
    local header = TextBox{parent=main,y=1,text="Nuclear Generation Facility SCADA Coordinator",alignment=ALIGN.CENTER,fg_bg=s_header}
    local ping = DataIndicator{parent=main,x=1,y=1,label="SVTT",format="%d",value=0,unit="ms",lu_colors=style.lg_white,width=12,fg_bg=s_header}
    -- max length example: "01:23:45 AM - Wednesday, September 28 2022"
    local datetime = TextBox{parent=main,x=(header.get_width()-42),y=1,text="",alignment=ALIGN.RIGHT,width=42,fg_bg=s_header}

    ping.register(facility.ps, "sv_ping", ping.update)
    datetime.register(facility.ps, "date_time", datetime.set_value)

    ---@type Div, Div, Div, Div
    local uo_1, uo_2, uo_3, uo_4

    local cnc_y_start = 3
    local row_1_height = 0

    -- unit overviews
    if facility.num_units >= 1 then
        uo_1 = unit_overview(main, 2, 3, units[1])
        row_1_height = uo_1.get_height()
    end

    if facility.num_units >= 2 then
        uo_2 = unit_overview(main, 84, 3, units[2])
        row_1_height = math.max(row_1_height, uo_2.get_height())
    end

    cnc_y_start = cnc_y_start + row_1_height + 1

    util.nop()

    if facility.num_units >= 3 then
        -- base offset 3, spacing 1, max height of units 1 and 2
        local row_2_offset = cnc_y_start

        uo_3 = unit_overview(main, 2, row_2_offset, units[3])
        cnc_y_start = row_2_offset + uo_3.get_height() + 1

        if facility.num_units == 4 then
            uo_4 = unit_overview(main, 84, row_2_offset, units[4])
            cnc_y_start = math.max(cnc_y_start, row_2_offset + uo_4.get_height() + 1)
        end

        util.nop()
    end

    -- command & control

    -- induction matrix and process control interfaces are 24 tall + space needed for divider
    local cnc_bottom_align_start = main.get_height() - 26

    assert(cnc_bottom_align_start >= cnc_y_start, "main display not of sufficient vertical resolution (add an additional row of monitors)")

    TextBox{parent=main,y=cnc_bottom_align_start,text=string.rep("\x8c", header.get_width()),alignment=ALIGN.CENTER,fg_bg=style.lg_gray}

    cnc_bottom_align_start = cnc_bottom_align_start + 2

    process_ctl(main, 2, cnc_bottom_align_start)

    util.nop()

    imatrix(main, 131, cnc_bottom_align_start, facility.induction_ps_tbl[1])
end

return init
