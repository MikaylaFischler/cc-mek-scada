local types          = require("scada-common.types")
local util           = require("scada-common.util")

local iocontrol      = require("pocket.iocontrol")

local style          = require("pocket.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local TextBox        = require("graphics.elements.TextBox")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local HorizontalBar  = require("graphics.elements.indicators.HorizontalBar")
local IconIndicator  = require("graphics.elements.indicators.IconIndicator")
local PowerIndicator = require("graphics.elements.indicators.PowerIndicator")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")

local cpair = core.cpair

local label   = style.label
local lu_col  = style.label_unit_pair
local text_fg = style.text_fg

local mode_ind_s = {
    { color = cpair(colors.black, colors.lightGray), symbol = "-" },
    { color = cpair(colors.black, colors.white), symbol = "+" }
}

-- create an induction matrix view for the facility app
---@param app pocket_app
---@param panes Div[]
---@param tank_pane Div
---@param ps psil
---@param update function
return function (app, panes, tank_pane, ps, update)
    local db = iocontrol.get_db()
    local fac = db.facility

    local mtx_div = Div{parent=tank_pane,x=2,width=tank_pane.get_width()-2}
    table.insert(panes, mtx_div)

    local matrix_page = app.new_page(nil, #panes)
    matrix_page.tasks = { update }

    TextBox{parent=mtx_div,y=1,text="I Matrix",width=9}
    local status = StateIndicator{parent=mtx_div,x=10,y=1,states=style.imatrix.states,value=1,min_width=12}
    status.register(ps, "InductionMatrixStateStatus", status.update)

    TextBox{parent=mtx_div,text="Charge",x=1,y=5,fg_bg=label}
    local chg_bar = HorizontalBar{parent=mtx_div,x=1,y=6,fg_bg=cpair(colors.green,colors.gray)}
    TextBox{parent=mtx_div,text="Input",x=1,y=7,fg_bg=label}
    local in_bar = HorizontalBar{parent=mtx_div,x=1,y=8,fg_bg=cpair(colors.blue,colors.gray)}
    TextBox{parent=mtx_div,text="Output",x=21,y=9,fg_bg=label}
    local out_bar = HorizontalBar{parent=mtx_div,x=1,y=10,fg_bg=cpair(colors.red,colors.gray)}

    local function calc_saturation(val)
        local data = fac.induction_data_tbl[1]
        if (type(data.build) == "table") and (type(data.build.transfer_cap) == "number") and (data.build.transfer_cap > 0) then
            return val / data.build.transfer_cap
        else return 0 end
    end

    chg_bar.register(ps, "energy_fill", chg_bar.update)
    in_bar.register(ps, "last_input", function (val) in_bar.update(calc_saturation(val)) end)
    out_bar.register(ps, "last_output", function (val) out_bar.update(calc_saturation(val)) end)

    local energy  = PowerIndicator{parent=mtx_div,x=1,y=12,lu_colors=lu_col,label="Chg: ",unit=db.energy_label,format="%8.2f",value=0,width=22,fg_bg=text_fg}
    local avg_chg = PowerIndicator{parent=mtx_div,x=1,lu_colors=lu_col,label="\xb7Avg:",unit=db.energy_label,format="%8.2f",value=0,width=22,fg_bg=text_fg}
    local input   = PowerIndicator{parent=mtx_div,x=1,lu_colors=lu_col,label="In:  ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=22,fg_bg=text_fg}
    local avg_in  = PowerIndicator{parent=mtx_div,x=1,lu_colors=lu_col,label="\xb7Avg:",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=22,fg_bg=text_fg}
    local output  = PowerIndicator{parent=mtx_div,x=1,lu_colors=lu_col,label="Out: ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=22,fg_bg=text_fg}
    local avg_out = PowerIndicator{parent=mtx_div,x=1,lu_colors=lu_col,label="\xb7Avg:",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=22,fg_bg=text_fg}

    energy.register(ps, "energy", function (val) energy.update(db.energy_convert(val)) end)
    avg_chg.register(fac.ps, "avg_charge", avg_chg.update)
    input.register(ps, "last_input", function (val) input.update(db.energy_convert(val)) end)
    avg_in.register(fac.ps, "avg_inflow", avg_in.update)
    output.register(ps, "last_output", function (val) output.update(db.energy_convert(val)) end)
    avg_out.register(fac.ps, "avg_outflow", avg_out.update)

    return matrix_page.nav_to
end
