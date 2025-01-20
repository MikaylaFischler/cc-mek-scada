local iocontrol      = require("pocket.iocontrol")

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

local yel_ind_s = style.icon_states.yel_ind_s
local wht_ind_s = style.icon_states.wht_ind_s

-- create an induction matrix view for the facility app
---@param app pocket_app
---@param panes Div[]
---@param matrix_pane Div
---@param ps psil
---@param update function
return function (app, panes, matrix_pane, ps, update)
    local db = iocontrol.get_db()
    local fac = db.facility

    local mtx_div = Div{parent=matrix_pane,x=2,width=matrix_pane.get_width()-2}
    table.insert(panes, mtx_div)

    local matrix_page = app.new_page(nil, #panes)
    matrix_page.tasks = { update }

    TextBox{parent=mtx_div,y=1,text="Induction Matrix",alignment=ALIGN.CENTER}
    local status = StateIndicator{parent=mtx_div,x=5,y=3,states=style.imatrix.states,value=1,min_width=12}
    status.register(ps, "InductionMatrixStateStatus", status.update)

    TextBox{parent=mtx_div,text="Chg",y=5,fg_bg=label}
    local chg_bar = HorizontalBar{parent=mtx_div,x=5,y=5,height=1,fg_bg=cpair(colors.green,colors.gray)}
    TextBox{parent=mtx_div,text="In",y=7,fg_bg=label}
    local in_bar = HorizontalBar{parent=mtx_div,x=5,y=7,height=1,fg_bg=cpair(colors.blue,colors.gray)}
    TextBox{parent=mtx_div,text="Out",y=9,fg_bg=label}
    local out_bar = HorizontalBar{parent=mtx_div,x=5,y=9,height=1,fg_bg=cpair(colors.red,colors.gray)}

    local function calc_saturation(val)
        local data = fac.induction_data_tbl[1]
        if (type(data.build) == "table") and (type(data.build.transfer_cap) == "number") and (data.build.transfer_cap > 0) then
            return val / data.build.transfer_cap
        else return 0 end
    end

    chg_bar.register(ps, "energy_fill", chg_bar.update)
    in_bar.register(ps, "last_input", function (val) in_bar.update(calc_saturation(val)) end)
    out_bar.register(ps, "last_output", function (val) out_bar.update(calc_saturation(val)) end)

    local energy  = PowerIndicator{parent=mtx_div,y=11,lu_colors=lu_col,label="Chg:  ",unit=db.energy_label,format="%8.2f",value=0,width=21,fg_bg=text_fg}
    local avg_chg = PowerIndicator{parent=mtx_div,lu_colors=lu_col,label="\xb7Avg: ",unit=db.energy_label,format="%8.2f",value=0,width=21,fg_bg=text_fg}
    local input   = PowerIndicator{parent=mtx_div,lu_colors=lu_col,label="In:   ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=21,fg_bg=text_fg}
    local avg_in  = PowerIndicator{parent=mtx_div,lu_colors=lu_col,label="\xb7Avg: ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=21,fg_bg=text_fg}
    local output  = PowerIndicator{parent=mtx_div,lu_colors=lu_col,label="Out:  ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=21,fg_bg=text_fg}
    local avg_out = PowerIndicator{parent=mtx_div,lu_colors=lu_col,label="\xb7Avg: ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=21,fg_bg=text_fg}

    energy.register(ps, "energy", function (val) energy.update(db.energy_convert(val)) end)
    avg_chg.register(ps, "avg_charge", avg_chg.update)
    input.register(ps, "last_input", function (val) input.update(db.energy_convert(val)) end)
    avg_in.register(ps, "avg_inflow", avg_in.update)
    output.register(ps, "last_output", function (val) output.update(db.energy_convert(val)) end)
    avg_out.register(ps, "avg_outflow", avg_out.update)

    local mtx_ext_div = Div{parent=matrix_pane,x=2,width=matrix_pane.get_width()-2}
    table.insert(panes, mtx_ext_div)

    local mtx_ext_page = app.new_page(matrix_page, #panes)
    mtx_ext_page.tasks = { update }

    PushButton{parent=mtx_div,x=9,y=18,text="MORE",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=mtx_ext_page.nav_to}
    PushButton{parent=mtx_ext_div,x=9,y=18,text="BACK",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=matrix_page.nav_to}

    TextBox{parent=mtx_ext_div,y=1,text="More Matrix Info",alignment=ALIGN.CENTER}

    local chging = IconIndicator{parent=mtx_ext_div,y=3,label="Charging",states=wht_ind_s}
    local dischg = IconIndicator{parent=mtx_ext_div,y=4,label="Discharging",states=wht_ind_s}

    TextBox{parent=mtx_ext_div,text="Energy Fill",x=1,y=6,width=13,fg_bg=label}
    local fill = DataIndicator{parent=mtx_ext_div,x=14,y=6,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}

    chging.register(ps, "is_charging", chging.update)
    dischg.register(ps, "is_discharging", dischg.update)
    fill.register(ps, "energy_fill", function (x) fill.update(x * 100) end)

    local max_io = IconIndicator{parent=mtx_ext_div,y=8,label="Max I/O Rate",states=yel_ind_s}

    TextBox{parent=mtx_ext_div,text="Input Util.",x=1,y=10,width=13,fg_bg=label}
    local in_util = DataIndicator{parent=mtx_ext_div,x=14,y=10,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    TextBox{parent=mtx_ext_div,text="Output Util.",x=1,y=11,width=13,fg_bg=label}
    local out_util = DataIndicator{parent=mtx_ext_div,x=14,y=11,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}

    max_io.register(ps, "at_max_io", max_io.update)
    in_util.register(ps, "last_input", function (x) in_util.update(calc_saturation(x) * 100) end)
    out_util.register(ps, "last_output", function (x) out_util.update(calc_saturation(x) * 100) end)

    TextBox{parent=mtx_ext_div,text="Capacity ("..db.energy_label..")",x=1,y=13,fg_bg=label}
    local capacity  = DataIndicator{parent=mtx_ext_div,y=14,lu_colors=lu_col,label="",unit="",format="%21d",value=0,width=21,fg_bg=text_fg}
    TextBox{parent=mtx_ext_div,text="Max In/Out ("..db.energy_label.."/t)",x=1,y=15,fg_bg=label}
    local trans_cap = DataIndicator{parent=mtx_ext_div,y=16,lu_colors=lu_col,label="",unit="",format="%21d",rate=true,value=0,width=21,fg_bg=text_fg}

    capacity.register(ps, "max_energy", function (val) capacity.update(db.energy_convert(val)) end)
    trans_cap.register(ps, "transfer_cap", function (val) trans_cap.update(db.energy_convert(val)) end)

    return matrix_page.nav_to
end
