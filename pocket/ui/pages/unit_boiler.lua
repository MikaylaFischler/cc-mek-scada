local types         = require("scada-common.types")
local util          = require("scada-common.util")

local iocontrol     = require("pocket.iocontrol")

local style         = require("pocket.ui.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.div")
local TextBox       = require("graphics.elements.textbox")

local DataIndicator = require("graphics.elements.indicators.data")
local IconIndicator = require("graphics.elements.indicators.icon")
local VerticalBar   = require("graphics.elements.indicators.vbar")

local PushButton    = require("graphics.elements.controls.push_button")

local ALIGN = core.ALIGN
local cpair = core.cpair

local label        = style.label
local lu_col       = style.label_unit_pair
local text_fg      = style.text_fg
local basic_states = style.icon_states.basic_states
local red_ind_s    = style.icon_states.red_ind_s
local yel_ind_s    = style.icon_states.yel_ind_s

-- create a boiler view in the unit app
---@param app pocket_app
---@param u_page nav_tree_page
---@param panes table
---@param blr_pane graphics_element
---@param b_id integer boiler ID
---@param ps psil
---@param update function
return function (app, u_page, panes, blr_pane, b_id, ps, update)
    local db = iocontrol.get_db()

    local blr_div = Div{parent=blr_pane,x=2,width=blr_pane.get_width()-2}
    table.insert(panes, blr_div)

    local blr_page = app.new_page(u_page, #panes)
    blr_page.tasks = { update }

    TextBox{parent=blr_div,y=1,text="Boiler "..b_id,height=1,alignment=ALIGN.CENTER}

    local hcool = VerticalBar{parent=blr_div,x=1,y=4,fg_bg=cpair(colors.orange,colors.gray),height=5,width=1}
    local water = VerticalBar{parent=blr_div,x=3,y=4,fg_bg=cpair(colors.blue,colors.gray),height=5,width=1}
    local steam = VerticalBar{parent=blr_div,x=19,y=4,fg_bg=cpair(colors.white,colors.gray),height=5,width=1}
    local ccool = VerticalBar{parent=blr_div,x=21,y=4,fg_bg=cpair(colors.lightBlue,colors.gray),height=5,width=1}

    TextBox{parent=blr_div,text="H",x=1,y=3,width=1,height=1,fg_bg=label}
    TextBox{parent=blr_div,text="W",x=3,y=3,width=1,height=1,fg_bg=label}
    TextBox{parent=blr_div,text="S",x=19,y=3,width=1,height=1,fg_bg=label}
    TextBox{parent=blr_div,text="C",x=21,y=3,width=1,height=1,fg_bg=label}

    hcool.register(ps, "hcool_fill", hcool.update)
    water.register(ps, "water_fill", water.update)
    steam.register(ps, "steam_fill", steam.update)
    ccool.register(ps, "ccool_fill", ccool.update)

    TextBox{parent=blr_div,text="Temperature",x=5,y=5,width=13,height=1,fg_bg=label}
    local t_prec = util.trinary(db.temp_label == types.TEMP_SCALE_UNITS[types.TEMP_SCALE.KELVIN], 11, 10)
    local temp = DataIndicator{parent=blr_div,x=5,y=6,lu_colors=lu_col,label="",unit=db.temp_label,format="%"..t_prec..".2f",value=17802.03,commas=true,width=13,fg_bg=text_fg}

    local state = IconIndicator{parent=blr_div,x=7,y=3,label="State",states=basic_states}

    temp.register(ps, "temperature", function (t) temp.update(db.temp_convert(t)) end)
    state.register(ps, "BoilerStatus", state.update)

    local b_wll = IconIndicator{parent=blr_div,y=10,label="Water Level Lo",states=red_ind_s}
    local b_hr  = IconIndicator{parent=blr_div,label="Heating Rate Lo",states=yel_ind_s}

    b_wll.register(ps, "WaterLevelLow", b_wll.update)
    b_hr.register(ps, "HeatingRateLow", b_hr.update)

    return blr_page.nav_to
end
