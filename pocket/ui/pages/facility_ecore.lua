--
-- Energy Core View
--

local ioctl          = require("pocket.ioctl")

local style          = require("pocket.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local TextBox        = require("graphics.elements.TextBox")

local PushButton     = require("graphics.elements.controls.PushButton")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local HorizontalBar  = require("graphics.elements.indicators.HorizontalBar")
local IconIndicator  = require("graphics.elements.indicators.IconIndicator")
local PowerIndicator = require("graphics.elements.indicators.PowerIndicator")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")

local ALIGN = core.ALIGN
local cpair = core.cpair

local label   = style.label
local lu_col  = style.label_unit_pair
local text_fg = style.text_fg

local wht_ind_s = style.icon_states.wht_ind_s

-- create an energy core view for the facility app
---@param app pocket_app
---@param panes Div[]
---@param ecore_pane Div
---@param ps psil
---@param update function
return function (app, panes, ecore_pane, ps, update)
    local db = ioctl.get_db()

    local ecr_div = Div{parent=ecore_pane,x=2,width=ecore_pane.get_width()-2}
    table.insert(panes, ecr_div)

    local matrix_page = app.new_page(nil, #panes)
    matrix_page.tasks = { update }

    TextBox{parent=ecr_div,y=1,text="Energy Core",alignment=ALIGN.CENTER}
    local status = StateIndicator{parent=ecr_div,x=5,y=3,states=style.ess.states,value=1,min_width=12}
    status.register(ps, "EnergyCoreStateStatus", status.update)

    TextBox{parent=ecr_div,text="Chg",y=5,fg_bg=label}
    local chg_bar = HorizontalBar{parent=ecr_div,x=5,y=5,height=1,fg_bg=cpair(colors.green,colors.gray)}

    chg_bar.register(ps, "energy_fill", chg_bar.update)

    TextBox{parent=ecr_div,text="Core Tier",y=7,fg_bg=label}
    local tier = TextBox{parent=ecr_div,x=11,y=7,width=11,text="Unknown",alignment=ALIGN.RIGHT}

    tier.register(ps, "tier", tier.set_value)

    local energy  = PowerIndicator{parent=ecr_div,y=9,lu_colors=lu_col,label="Chg:  ",unit=db.energy_label,format="%8.2f",value=0,width=21,fg_bg=text_fg}
    local avg_chg = PowerIndicator{parent=ecr_div,lu_colors=lu_col,label="\xb7Avg: ",unit=db.energy_label,format="%8.2f",value=0,width=21,fg_bg=text_fg}
    local input   = PowerIndicator{parent=ecr_div,y=12,lu_colors=lu_col,label="In:   ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=21,fg_bg=text_fg}
    local avg_in  = PowerIndicator{parent=ecr_div,lu_colors=lu_col,label="\xb7Avg: ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=21,fg_bg=text_fg}
    local output  = PowerIndicator{parent=ecr_div,y=15,lu_colors=lu_col,label="Out:  ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=21,fg_bg=text_fg}
    local avg_out = PowerIndicator{parent=ecr_div,lu_colors=lu_col,label="\xb7Avg: ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=21,fg_bg=text_fg}

    energy.register(ps, "energy", function (val) energy.update(db.energy_convert(val)) end)
    avg_chg.register(ps, "avg_charge", avg_chg.update)
    input.register(ps, "input", function (val) input.update(db.energy_convert(val)) end)
    avg_in.register(ps, "avg_inflow", avg_in.update)
    output.register(ps, "output", function (val) output.update(db.energy_convert(val)) end)
    avg_out.register(ps, "avg_outflow", avg_out.update)

    local mtx_ext_div = Div{parent=ecore_pane,x=2,width=ecore_pane.get_width()-2}
    table.insert(panes, mtx_ext_div)

    local mtx_ext_page = app.new_page(matrix_page, #panes)
    mtx_ext_page.tasks = { update }

    PushButton{parent=ecr_div,x=9,y=18,text="MORE",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=mtx_ext_page.nav_to}
    PushButton{parent=mtx_ext_div,x=9,y=18,text="BACK",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=matrix_page.nav_to}

    TextBox{parent=mtx_ext_div,y=1,text="More Energy Core Info",alignment=ALIGN.CENTER}

    TextBox{parent=mtx_ext_div,text="Energy Fill",y=3,width=13,fg_bg=label}
    local fill = DataIndicator{parent=mtx_ext_div,y=3,x=14,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}

    local chging = IconIndicator{parent=mtx_ext_div,y=5,label="Charging",states=wht_ind_s}
    local dischg = IconIndicator{parent=mtx_ext_div,label="Discharging",states=wht_ind_s}

    TextBox{parent=mtx_ext_div,text="Transfer",y=8,width=13,fg_bg=label}
    local transfer = PowerIndicator{parent=mtx_ext_div,lu_colors=lu_col,label="",unit=db.energy_label,format="%15.2f",rate=true,value=0,width=21,fg_bg=text_fg}

    fill.register(ps, "energy_fill", function (x) fill.update(x * 100) end)
    chging.register(ps, "is_charging", chging.update)
    dischg.register(ps, "is_discharging", dischg.update)
    transfer.register(ps, "transfer", function (val) transfer.update(db.energy_convert_from_fe(val)) end)

    TextBox{parent=mtx_ext_div,text="Capacity",y=11,width=13,fg_bg=label}
    local capacity = PowerIndicator{parent=mtx_ext_div,y=12,lu_colors=lu_col,label="",unit=db.energy_label,format="%15.2f",value=0,width=21,fg_bg=text_fg}

    TextBox{parent=mtx_ext_div,text="Capacity ("..db.energy_label..")",y=14,fg_bg=label}
    local cap_fe  = DataIndicator{parent=mtx_ext_div,y=15,lu_colors=lu_col,label="",unit="",format="%21d",value=0,width=21,fg_bg=text_fg}

    capacity.register(ps, "max_energy", function (val) capacity.update(db.energy_convert_from_fe(val)) end)
    cap_fe.register(ps, "max_energy", function (val) cap_fe.update(db.energy_convert_from_fe(val)) end)

    return matrix_page.nav_to
end
