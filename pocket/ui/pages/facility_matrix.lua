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
    local fac = iocontrol.get_db().facility

    local mtx_div = Div{parent=tank_pane,x=2,width=tank_pane.get_width()-2}
    table.insert(panes, mtx_div)

    local matrix_page = app.new_page(nil, #panes)
    matrix_page.tasks = { update }

    TextBox{parent=mtx_div,y=1,text="I Matrix",width=9}
    local status = StateIndicator{parent=mtx_div,x=10,y=1,states=style.imatrix.states,value=1,min_width=12}
    status.register(ps, "InductionMatrixStateStatus", status.update)

    TextBox{parent=mtx_div,y=3,text="Fill",width=10,fg_bg=label}
    local chg_pcnt = DataIndicator{parent=mtx_div,x=14,y=3,label="",format="%5.2f",value=100,unit="%",lu_colors=lu_col,width=8,fg_bg=text_fg}
    local chg_amnt = DataIndicator{parent=mtx_div,label="",format="%18d",value=0,commas=true,unit="mB",lu_colors=lu_col,width=21,fg_bg=text_fg}

    TextBox{parent=mtx_div,y=6,text="Charge Level",width=12,fg_bg=label}
    local level = HorizontalBar{parent=mtx_div,y=7,bar_fg_bg=cpair(colors.green,colors.gray),height=1,width=21}

    level.register(ps, "fill", level.update)

    return matrix_page.nav_to
end
