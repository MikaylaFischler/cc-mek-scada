local iocontrol      = require("pocket.iocontrol")

local style          = require("pocket.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local TextBox        = require("graphics.elements.TextBox")

local PushButton     = require("graphics.elements.controls.PushButton")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local HorizontalBar  = require("graphics.elements.indicators.HorizontalBar")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")

local ALIGN = core.ALIGN
local cpair = core.cpair

local label   = style.label
local lu_col  = style.label_unit_pair
local text_fg = style.text_fg

-- create an SPS view in the facility app
---@param app pocket_app
---@param panes Div[]
---@param sps_pane Div
---@param ps psil
---@param update function
return function (app, panes, sps_pane, ps, update)
    local db = iocontrol.get_db()

    local sps_div = Div{parent=sps_pane,x=2,width=sps_pane.get_width()-2}
    table.insert(panes, sps_div)

    local sps_page = app.new_page(nil, #panes)
    sps_page.tasks = { update }

    TextBox{parent=sps_div,y=1,text="Facility SPS",alignment=ALIGN.CENTER}
    local status = StateIndicator{parent=sps_div,x=5,y=3,states=style.sps.states,value=1,min_width=12}
    status.register(ps, "SPSStateStatus", status.update)

    TextBox{parent=sps_div,text="Po",y=5,fg_bg=label}
    local po_bar = HorizontalBar{parent=sps_div,x=4,y=5,fg_bg=cpair(colors.cyan,colors.gray),height=1}
    TextBox{parent=sps_div,text="AM",y=7,fg_bg=label}
    local am_bar = HorizontalBar{parent=sps_div,x=4,y=7,fg_bg=cpair(colors.purple,colors.gray),height=1}

    po_bar.register(ps, "input_fill", po_bar.update)
    am_bar.register(ps, "output_fill", am_bar.update)

    TextBox{parent=sps_div,y=9,text="Input Rate",width=10,fg_bg=label}
    local input_rate = DataIndicator{parent=sps_div,label="",format="%16.2f",value=0,unit="mB/t",lu_colors=lu_col,width=21,fg_bg=text_fg}
    TextBox{parent=sps_div,y=12,text="Production Rate",width=15,fg_bg=label}
    local proc_rate = DataIndicator{parent=sps_div,label="",format="%16d",value=0,unit="\xb5B/t",lu_colors=lu_col,width=21,fg_bg=text_fg}

    proc_rate.register(ps, "process_rate", function (r) proc_rate.update(r * 1000) end)
    input_rate.register(db.facility.ps, "po_am_rate", input_rate.update)

    local sps_ext_div = Div{parent=sps_pane,x=2,width=sps_pane.get_width()-2}
    table.insert(panes, sps_ext_div)

    local sps_ext_page = app.new_page(sps_page, #panes)
    sps_ext_page.tasks = { update }

    PushButton{parent=sps_div,x=9,y=18,text="MORE",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=sps_ext_page.nav_to}
    PushButton{parent=sps_ext_div,x=9,y=18,text="BACK",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=sps_page.nav_to}

    TextBox{parent=sps_ext_div,y=1,text="More SPS Info",alignment=ALIGN.CENTER}

    TextBox{parent=sps_ext_div,text="Polonium",x=1,y=3,width=13,fg_bg=label}
    local input_p = DataIndicator{parent=sps_ext_div,x=14,y=3,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local input_amnt = DataIndicator{parent=sps_ext_div,x=1,y=4,lu_colors=lu_col,label="",unit="mB",format="%18.0f",value=0,commas=true,width=21,fg_bg=text_fg}

    input_p.register(ps, "input_fill", function (x) input_p.update(x * 100) end)
    input_amnt.register(ps, "input", function (x) input_amnt.update(x.amount) end)

    TextBox{parent=sps_ext_div,text="Antimatter",x=1,y=6,width=15,fg_bg=label}
    local output_p = DataIndicator{parent=sps_ext_div,x=14,y=6,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local output_amnt = DataIndicator{parent=sps_ext_div,x=1,y=7,lu_colors=lu_col,label="",unit="\xb5B",format="%18.3f",value=0,commas=true,width=21,fg_bg=text_fg}

    output_p.register(ps, "output_fill", function (x) output_p.update(x * 100) end)
    output_amnt.register(ps, "output", function (x) output_amnt.update(x.amount) end)

    return sps_page.nav_to
end
