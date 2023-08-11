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

local Div          = require("graphics.elements.div")
local PipeNetwork  = require("graphics.elements.pipenet")
local TextBox      = require("graphics.elements.textbox")

local Rectangle      = require("graphics.elements.rectangle")

local DataIndicator  = require("graphics.elements.indicators.data")
local HorizontalBar  = require("graphics.elements.indicators.hbar")
local StateIndicator = require("graphics.elements.indicators.state")

local IndicatorLight    = require("graphics.elements.indicators.light")
local TriIndicatorLight = require("graphics.elements.indicators.trilight")
local VerticalBar       = require("graphics.elements.indicators.vbar")

local TEXT_ALIGN = core.TEXT_ALIGN

local cpair = core.cpair
local border = core.border
local pipe = core.pipe

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

    local po_pipes = {}

    for i = 1, facility.num_units do
        local y_offset = ((i - 1) * 20)
        flow_overview(main, 25, 5 + y_offset, units[i])
        table.insert(po_pipes, pipe(0, 6 + y_offset, 8, 0, colors.cyan, true, true))
    end

    local text_fg_bg = cpair(colors.black, colors.white)
    local lu_col = cpair(colors.gray, colors.gray)

    PipeNetwork{parent=main,x=139,y=12,pipes=po_pipes,bg=colors.lightGray}

    local sps = Div{parent=main,x=142,y=5,height=8}

    TextBox{parent=sps,x=1,y=1,text="SPS",alignment=TEXT_ALIGN.CENTER,width=21,height=1,fg_bg=cpair(colors.white,colors.gray)}
    local sps_box = Rectangle{parent=sps,x=1,y=2,border=border(1, colors.gray, true),width=21,height=7,thin=true,fg_bg=cpair(colors.black,colors.white)}
    local sps_conn = IndicatorLight{parent=sps_box,label="CONNECTED",colors=cpair(colors.green,colors.gray)}
    local sps_act = IndicatorLight{parent=sps_box,label="ACTIVE",colors=cpair(colors.green,colors.gray)}
    local sps_in = DataIndicator{parent=sps_box,y=4,lu_colors=lu_col,label="IN  ",unit="mB/t",format="%9.2f",value=123.456,width=19,fg_bg=text_fg_bg}
    local sps_rate = DataIndicator{parent=sps_box,lu_colors=lu_col,label="RATE",unit="\xb5B/t",format="%9.2f",value=123456.78,width=19,fg_bg=text_fg_bg}
end

return init
