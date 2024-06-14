local types          = require("scada-common.types")
local util           = require("scada-common.util")

local iocontrol      = require("pocket.iocontrol")

local style          = require("pocket.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.div")
local TextBox        = require("graphics.elements.textbox")

local PushButton     = require("graphics.elements.controls.push_button")

local DataIndicator  = require("graphics.elements.indicators.data")
local StateIndicator = require("graphics.elements.indicators.state")
local IconIndicator  = require("graphics.elements.indicators.icon")
local VerticalBar    = require("graphics.elements.indicators.vbar")

local ALIGN = core.ALIGN
local cpair = core.cpair

local label     = style.label
local lu_col    = style.label_unit_pair
local text_fg   = style.text_fg
local red_ind_s = style.icon_states.red_ind_s
local yel_ind_s = style.icon_states.yel_ind_s

-- create a reactor view in the unit app
---@param app pocket_app
---@param u_page nav_tree_page
---@param panes table
---@param page_div graphics_element
---@param u_ps psil
---@param update function
return function (app, u_page, panes, page_div, u_ps, update)
    local db = iocontrol.get_db()

    local rct_pane = Div{parent=page_div}
    local rct_div = Div{parent=rct_pane,x=2,width=page_div.get_width()-2}
    table.insert(panes, rct_div)

    local rct_page = app.new_page(u_page, #panes)
    rct_page.tasks = { update }

    TextBox{parent=rct_div,y=1,text="Reactor",width=8,height=1}
    local status = StateIndicator{parent=rct_div,x=10,y=1,states=style.reactor.states,value=1,min_width=12}
    status.register(u_ps, "U_ReactorStateStatus", status.update)

    local fuel  = VerticalBar{parent=rct_div,x=1,y=4,fg_bg=cpair(colors.lightGray,colors.gray),height=5,width=1}
    local ccool = VerticalBar{parent=rct_div,x=3,y=4,fg_bg=cpair(colors.blue,colors.gray),height=5,width=1}
    local hcool = VerticalBar{parent=rct_div,x=19,y=4,fg_bg=cpair(colors.white,colors.gray),height=5,width=1}
    local waste = VerticalBar{parent=rct_div,x=21,y=4,fg_bg=cpair(colors.brown,colors.gray),height=5,width=1}

    TextBox{parent=rct_div,text="F",x=1,y=3,width=1,height=1,fg_bg=label}
    TextBox{parent=rct_div,text="C",x=3,y=3,width=1,height=1,fg_bg=label}
    TextBox{parent=rct_div,text="H",x=19,y=3,width=1,height=1,fg_bg=label}
    TextBox{parent=rct_div,text="W",x=21,y=3,width=1,height=1,fg_bg=label}

    fuel.register(u_ps, "fuel_fill", fuel.update)
    ccool.register(u_ps, "ccool_fill", ccool.update)
    hcool.register(u_ps, "hcool_fill", hcool.update)
    waste.register(u_ps, "waste_fill", waste.update)

    ccool.register(u_ps, "ccool_type", function (type)
        if type == types.FLUID.SODIUM then
            ccool.recolor(cpair(colors.lightBlue, colors.gray))
        else
            ccool.recolor(cpair(colors.blue, colors.gray))
        end
    end)

    hcool.register(u_ps, "hcool_type", function (type)
        if type == types.FLUID.SUPERHEATED_SODIUM then
            hcool.recolor(cpair(colors.orange, colors.gray))
        else
            hcool.recolor(cpair(colors.white, colors.gray))
        end
    end)

    TextBox{parent=rct_div,text="Burn Rate",x=5,y=4,width=13,height=1,fg_bg=label}
    local burn_rate = DataIndicator{parent=rct_div,x=5,y=5,lu_colors=lu_col,label="",unit="mB/t",format="%8.2f",value=0,commas=true,width=13,fg_bg=text_fg}
    TextBox{parent=rct_div,text="Temperature",x=5,y=6,width=13,height=1,fg_bg=label}
    local t_prec = util.trinary(db.temp_label == types.TEMP_SCALE_UNITS[types.TEMP_SCALE.KELVIN], 11, 10)
    local core_temp = DataIndicator{parent=rct_div,x=5,y=7,lu_colors=lu_col,label="",unit=db.temp_label,format="%"..t_prec..".2f",value=0,commas=true,width=13,fg_bg=text_fg}

    burn_rate.register(u_ps, "act_burn_rate", burn_rate.update)
    core_temp.register(u_ps, "temp", function (t) core_temp.update(db.temp_convert(t)) end)

    local r_temp = IconIndicator{parent=rct_div,y=10,label="Reactor Temp. Hi",states=red_ind_s}
    local r_rhdt = IconIndicator{parent=rct_div,label="Hi Delta Temp.",states=yel_ind_s}
    local r_firl = IconIndicator{parent=rct_div,label="Fuel Rate Lo",states=yel_ind_s}
    local r_wloc = IconIndicator{parent=rct_div,label="Waste Line Occl.",states=yel_ind_s}
    local r_hsrt = IconIndicator{parent=rct_div,label="Hi Startup Rate",states=yel_ind_s}

    r_temp.register(u_ps, "ReactorTempHigh", r_temp.update)
    r_rhdt.register(u_ps, "ReactorHighDeltaT", r_rhdt.update)
    r_firl.register(u_ps, "FuelInputRateLow", r_firl.update)
    r_wloc.register(u_ps, "WasteLineOcclusion", r_wloc.update)
    r_hsrt.register(u_ps, "HighStartupRate", r_hsrt.update)

    TextBox{parent=rct_div,text="HR",x=1,y=16,width=4,height=1,fg_bg=label}
    local heating_r = DataIndicator{parent=rct_div,x=6,y=16,lu_colors=lu_col,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=text_fg}
    TextBox{parent=rct_div,text="DMG",x=1,y=17,width=4,height=1,fg_bg=label}
    local damage_p = DataIndicator{parent=rct_div,x=6,y=17,lu_colors=lu_col,label="",unit="%",format="%11.2f",value=0,width=16,fg_bg=text_fg}

    heating_r.register(u_ps, "heating_rate", heating_r.update)
    damage_p.register(u_ps, "damage", damage_p.update)

    local rct_ext_div = Div{parent=rct_pane,x=2,width=page_div.get_width()-2}
    table.insert(panes, rct_ext_div)

    local rct_ext_page = app.new_page(rct_page, #panes)
    rct_ext_page.tasks = { update }

    PushButton{parent=rct_div,x=9,y=18,text="MORE",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=rct_ext_page.nav_to}
    PushButton{parent=rct_ext_div,x=9,y=18,text="BACK",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=rct_page.nav_to}

    TextBox{parent=rct_ext_div,y=1,text="More Reactor Info",height=1,alignment=ALIGN.CENTER}

    TextBox{parent=rct_ext_div,text="Fuel Tank",x=1,y=3,width=9,height=1,fg_bg=label}
    local fuel_p = DataIndicator{parent=rct_ext_div,x=14,y=3,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local fuel_amnt = DataIndicator{parent=rct_ext_div,x=1,y=4,lu_colors=lu_col,label="",unit="mB",format="%18.0f",value=0,commas=true,width=21,fg_bg=text_fg}

    fuel_p.register(u_ps, "fuel_fill", function (x) fuel_p.update(x * 100) end)
    fuel_amnt.register(u_ps, "fuel", fuel_amnt.update)

    TextBox{parent=rct_ext_div,text="Cool Coolant",x=1,y=6,width=12,height=1,fg_bg=label}
    local cooled_p = DataIndicator{parent=rct_ext_div,x=14,y=6,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local ccool_amnt = DataIndicator{parent=rct_ext_div,x=1,y=7,lu_colors=lu_col,label="",unit="mB",format="%18.0f",value=0,commas=true,width=21,fg_bg=text_fg}

    cooled_p.register(u_ps, "ccool_fill", function (x) cooled_p.update(x * 100) end)
    ccool_amnt.register(u_ps, "ccool_amnt", ccool_amnt.update)

    TextBox{parent=rct_ext_div,text="Hot Coolant",x=1,y=9,width=12,height=1,fg_bg=label}
    local heated_p = DataIndicator{parent=rct_ext_div,x=14,y=9,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local hcool_amnt = DataIndicator{parent=rct_ext_div,x=1,y=10,lu_colors=lu_col,label="",unit="mB",format="%18.0f",value=0,commas=true,width=21,fg_bg=text_fg}

    heated_p.register(u_ps, "hcool_fill", function (x) heated_p.update(x * 100) end)
    hcool_amnt.register(u_ps, "hcool_amnt", hcool_amnt.update)

    TextBox{parent=rct_ext_div,text="Waste Tank",x=1,y=12,width=10,height=1,fg_bg=label}
    local waste_p = DataIndicator{parent=rct_ext_div,x=14,y=12,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local waste_amnt = DataIndicator{parent=rct_ext_div,x=1,y=13,lu_colors=lu_col,label="",unit="mB",format="%18.0f",value=0,commas=true,width=21,fg_bg=text_fg}

    waste_p.register(u_ps, "waste_fill", function (x) waste_p.update(x * 100) end)
    waste_amnt.register(u_ps, "waste", waste_amnt.update)

    TextBox{parent=rct_ext_div,text="Boil Eff.",x=1,y=15,width=9,height=1,fg_bg=label}
    TextBox{parent=rct_ext_div,text="Env. Loss",x=1,y=16,width=9,height=1,fg_bg=label}
    local boil_eff = DataIndicator{parent=rct_ext_div,x=11,y=15,lu_colors=lu_col,label="",unit="%",format="%9.2f",value=0,width=11,fg_bg=text_fg}
    local env_loss = DataIndicator{parent=rct_ext_div,x=11,y=16,lu_colors=lu_col,label="",unit="",format="%11.8f",value=0,width=11,fg_bg=text_fg}

    boil_eff.register(u_ps, "boil_eff", function (x) boil_eff.update(x * 100) end)
    env_loss.register(u_ps, "env_loss", env_loss.update)

    return rct_page.nav_to
end
