--
-- Flow Monitor GUI
--

local util           = require("scada-common.util")

local iocontrol      = require("coordinator.iocontrol")

local style          = require("coordinator.ui.style")

local unit_flow      = require("coordinator.ui.components.unit_flow")

local core           = require("graphics.core")

local Div            = require("graphics.elements.div")
local PipeNetwork    = require("graphics.elements.pipenet")
local Rectangle      = require("graphics.elements.rectangle")
local TextBox        = require("graphics.elements.textbox")

local DataIndicator  = require("graphics.elements.indicators.data")
local HorizontalBar  = require("graphics.elements.indicators.hbar")
local IndicatorLight = require("graphics.elements.indicators.light")
local StateIndicator = require("graphics.elements.indicators.state")

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

    local bw_fg_bg  = cpair(colors.black, colors.white)
    local text_col  = cpair(colors.black, colors.lightGray)
    local lu_col = cpair(colors.gray, colors.gray)

    local water_pipes = {}

    local fac_tanks = true

    for i = 1, 4 do
        local y = ((i - 1) * 20)
        table.insert(water_pipes, pipe(2, y, 2, y + 5, colors.blue, true))
        table.insert(water_pipes, pipe(2, y, 82, y, colors.blue, true))
        table.insert(water_pipes, pipe(82, y, 82, y + 2, colors.blue, true))
        if fac_tanks and i > 1 then table.insert(water_pipes, pipe(21, y - 19, 21, y, colors.blue, true)) end
    end

    PipeNetwork{parent=main,x=2,y=3,pipes=water_pipes,bg=colors.lightGray}

    for i = 1, facility.num_units do
        local y_offset = ((i - 1) * 20)
        unit_flow(main, 25, 5 + y_offset, units[i])
        table.insert(po_pipes, pipe(0, 3 + y_offset, 8, 0, colors.cyan, true, true))

        local vx, vy = 11, 3 + y_offset
        TextBox{parent=main,x=vx,y=vy,text="\x10\x11",fg_bg=cpair(colors.black,colors.lightGray),width=2,height=1}
        local conn = IndicatorLight{parent=main,x=vx-3,y=vy+1,label=util.sprintf("PV%02d", i + 13),colors=cpair(colors.green,colors.gray)}
        local state = IndicatorLight{parent=main,x=vx-3,y=vy+2,label="STATE",colors=cpair(colors.white,colors.white)}

        local tank = Div{parent=main,x=2,y=8+y_offset,width=20,height=12}
        TextBox{parent=tank,text=" ",height=1,x=1,y=1,fg_bg=cpair(colors.lightGray,colors.gray)}
        TextBox{parent=tank,text="DYNAMIC TANK "..i,alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=cpair(colors.white,colors.gray)}
        local tank_box = Rectangle{parent=tank,border=border(1, colors.gray, true),width=20,height=10}
        local status = StateIndicator{parent=tank_box,x=3,y=1,states=style.dtank.states,value=1,min_width=14}
        TextBox{parent=tank_box,x=2,y=3,text="Fill",height=1,width=10,fg_bg=style.label}
        local tank_pcnt = DataIndicator{parent=tank_box,x=10,y=3,label="",format="%5.2f",value=100,unit="%",lu_colors=lu_col,width=8,fg_bg=text_col}
        local tank_amnt = DataIndicator{parent=tank_box,x=2,label="",format="%13d",value=0,unit="mB",lu_colors=lu_col,width=16,fg_bg=bw_fg_bg}
        TextBox{parent=tank_box,x=2,y=6,text="Water Level",height=1,width=11,fg_bg=style.label}
        local ccool = HorizontalBar{parent=tank_box,x=2,y=7,bar_fg_bg=cpair(colors.blue,colors.gray),height=1,width=16}
        ccool.update(1)
    end

    PipeNetwork{parent=main,x=139,y=15,pipes=po_pipes,bg=colors.lightGray}

    local sps = Div{parent=main,x=140,y=3,height=12}
    TextBox{parent=sps,text=" ",width=24,height=1,x=1,y=1,fg_bg=cpair(colors.lightGray,colors.gray)}
    TextBox{parent=sps,text="SPS",alignment=TEXT_ALIGN.CENTER,width=24,height=1,fg_bg=cpair(colors.white,colors.gray)}
    local sps_box = Rectangle{parent=sps,border=border(1, colors.gray, true),width=24,height=10}
    local status = StateIndicator{parent=sps_box,x=5,y=1,states=style.sps.states,value=1,min_width=14}
    TextBox{parent=sps_box,x=2,y=3,text="Input Rate",height=1,width=10,fg_bg=style.label}
    local sps_in = DataIndicator{parent=sps_box,x=2,label="",format="%15.2f",value=0,unit="mB/t",lu_colors=lu_col,width=20,fg_bg=bw_fg_bg}
    TextBox{parent=sps_box,x=2,y=6,text="Production Rate",height=1,width=15,fg_bg=style.label}
    local sps_rate = DataIndicator{parent=sps_box,x=2,label="",format="%15.2f",value=0,unit="\xb5B/t",lu_colors=lu_col,width=20,fg_bg=bw_fg_bg}
end

return init
