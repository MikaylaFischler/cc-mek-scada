local types          = require("scada-common.types")
local util           = require("scada-common.util")

local iocontrol      = require("pocket.iocontrol")

local style          = require("pocket.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local TextBox        = require("graphics.elements.TextBox")

local PushButton     = require("graphics.elements.controls.PushButton")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")
local IconIndicator  = require("graphics.elements.indicators.IconIndicator")
local VerticalBar    = require("graphics.elements.indicators.VerticalBar")

local ALIGN = core.ALIGN
local cpair = core.cpair

local label     = style.label
local lu_col    = style.label_unit_pair
local text_fg   = style.text_fg
local red_ind_s = style.icon_states.red_ind_s
local yel_ind_s = style.icon_states.yel_ind_s

-- create a boiler view in the unit app
---@param app pocket_app
---@param u_page nav_tree_page
---@param panes Div[]
---@param blr_pane Div
---@param b_id integer boiler ID
---@param ps psil
---@param update function
return function (app, u_page, panes, blr_pane, b_id, ps, update)
    local db = iocontrol.get_db()

    local blr_div = Div{parent=blr_pane,x=2,width=blr_pane.get_width()-2}
    table.insert(panes, blr_div)

    local blr_page = app.new_page(u_page, #panes)
    blr_page.tasks = { update }

    TextBox{parent=blr_div,y=1,text="BLR #"..b_id,width=8}
    local status = StateIndicator{parent=blr_div,x=10,y=1,states=style.boiler.states,value=1,min_width=12}
    status.register(ps, "BoilerStateStatus", status.update)

    local hcool = VerticalBar{parent=blr_div,x=1,y=4,fg_bg=cpair(colors.orange,colors.gray),height=5,width=1}
    local water = VerticalBar{parent=blr_div,x=3,y=4,fg_bg=cpair(colors.blue,colors.gray),height=5,width=1}
    local steam = VerticalBar{parent=blr_div,x=19,y=4,fg_bg=cpair(colors.white,colors.gray),height=5,width=1}
    local ccool = VerticalBar{parent=blr_div,x=21,y=4,fg_bg=cpair(colors.lightBlue,colors.gray),height=5,width=1}

    TextBox{parent=blr_div,text="H",x=1,y=3,width=1,fg_bg=label}
    TextBox{parent=blr_div,text="W",x=3,y=3,width=1,fg_bg=label}
    TextBox{parent=blr_div,text="S",x=19,y=3,width=1,fg_bg=label}
    TextBox{parent=blr_div,text="C",x=21,y=3,width=1,fg_bg=label}

    hcool.register(ps, "hcool_fill", hcool.update)
    water.register(ps, "water_fill", water.update)
    steam.register(ps, "steam_fill", steam.update)
    ccool.register(ps, "ccool_fill", ccool.update)

    TextBox{parent=blr_div,text="Temperature",x=5,y=5,width=13,fg_bg=label}
    local t_prec = util.trinary(db.temp_label == types.TEMP_SCALE_UNITS[types.TEMP_SCALE.KELVIN], 11, 10)
    local temp = DataIndicator{parent=blr_div,x=5,y=6,lu_colors=lu_col,label="",unit=db.temp_label,format="%"..t_prec..".2f",value=0,commas=true,width=13,fg_bg=text_fg}

    temp.register(ps, "temperature", function (t) temp.update(db.temp_convert(t)) end)

    local b_wll = IconIndicator{parent=blr_div,y=10,label="Water Level Lo",states=red_ind_s}
    local b_hr = IconIndicator{parent=blr_div,label="Heating Rate Lo",states=yel_ind_s}

    b_wll.register(ps, "WaterLevelLow", b_wll.update)
    b_hr.register(ps, "HeatingRateLow", b_hr.update)

    TextBox{parent=blr_div,text="Boil Rate",x=1,y=13,width=12,fg_bg=label}
    local boil_r = DataIndicator{parent=blr_div,x=6,y=14,lu_colors=lu_col,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=text_fg}

    boil_r.register(ps, "boil_rate", boil_r.update)

    local blr_ext_div = Div{parent=blr_pane,x=2,width=blr_pane.get_width()-2}
    table.insert(panes, blr_ext_div)

    local blr_ext_page = app.new_page(blr_page, #panes)
    blr_ext_page.tasks = { update }

    PushButton{parent=blr_div,x=9,y=18,text="MORE",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=blr_ext_page.nav_to}
    PushButton{parent=blr_ext_div,x=9,y=18,text="BACK",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=blr_page.nav_to}

    TextBox{parent=blr_ext_div,y=1,text="More Boiler Info",alignment=ALIGN.CENTER}

    local function update_amount(indicator)
        return function (x) indicator.update(x.amount) end
    end

    TextBox{parent=blr_ext_div,text="Hot Coolant",x=1,y=3,width=12,fg_bg=label}
    local heated_p = DataIndicator{parent=blr_ext_div,x=14,y=3,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local hcool_amnt = DataIndicator{parent=blr_ext_div,x=1,y=4,lu_colors=lu_col,label="",unit="mB",format="%18.0f",value=0,commas=true,width=21,fg_bg=text_fg}

    heated_p.register(ps, "hcool_fill", function (x) heated_p.update(x * 100) end)
    hcool_amnt.register(ps, "hcool", update_amount(hcool_amnt))

    TextBox{parent=blr_ext_div,text="Water Tank",x=1,y=6,width=9,fg_bg=label}
    local fuel_p = DataIndicator{parent=blr_ext_div,x=14,y=6,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local fuel_amnt = DataIndicator{parent=blr_ext_div,x=1,y=7,lu_colors=lu_col,label="",unit="mB",format="%18.0f",value=0,commas=true,width=21,fg_bg=text_fg}

    fuel_p.register(ps, "water_fill", function (x) fuel_p.update(x * 100) end)
    fuel_amnt.register(ps, "water", update_amount(fuel_amnt))

    TextBox{parent=blr_ext_div,text="Steam Tank",x=1,y=9,width=10,fg_bg=label}
    local steam_p = DataIndicator{parent=blr_ext_div,x=14,y=9,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local steam_amnt = DataIndicator{parent=blr_ext_div,x=1,y=10,lu_colors=lu_col,label="",unit="mB",format="%18.0f",value=0,commas=true,width=21,fg_bg=text_fg}

    steam_p.register(ps, "steam_fill", function (x) steam_p.update(x * 100) end)
    steam_amnt.register(ps, "steam", update_amount(steam_amnt))

    TextBox{parent=blr_ext_div,text="Cool Coolant",x=1,y=12,width=12,fg_bg=label}
    local cooled_p = DataIndicator{parent=blr_ext_div,x=14,y=12,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local ccool_amnt = DataIndicator{parent=blr_ext_div,x=1,y=13,lu_colors=lu_col,label="",unit="mB",format="%18.0f",value=0,commas=true,width=21,fg_bg=text_fg}

    cooled_p.register(ps, "ccool_fill", function (x) cooled_p.update(x * 100) end)
    ccool_amnt.register(ps, "ccool", update_amount(ccool_amnt))

    TextBox{parent=blr_ext_div,text="Env. Loss",x=1,y=15,width=9,fg_bg=label}
    local env_loss = DataIndicator{parent=blr_ext_div,x=11,y=15,lu_colors=lu_col,label="",unit="",format="%11.8f",value=0,width=11,fg_bg=text_fg}

    env_loss.register(ps, "env_loss", env_loss.update)

    return blr_page.nav_to
end
