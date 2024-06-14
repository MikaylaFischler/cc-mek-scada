local util           = require("scada-common.util")

local iocontrol      = require("pocket.iocontrol")

local style          = require("pocket.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.div")
local TextBox        = require("graphics.elements.textbox")

local DataIndicator  = require("graphics.elements.indicators.data")
local IconIndicator  = require("graphics.elements.indicators.icon")
local PowerIndicator = require("graphics.elements.indicators.power")
local StateIndicator = require("graphics.elements.indicators.state")
local VerticalBar    = require("graphics.elements.indicators.vbar")

local PushButton     = require("graphics.elements.controls.push_button")

local ALIGN = core.ALIGN
local cpair = core.cpair

local label     = style.label
local lu_col    = style.label_unit_pair
local text_fg   = style.text_fg
local tri_ind_s = style.icon_states.tri_ind_s
local red_ind_s = style.icon_states.red_ind_s
local yel_ind_s = style.icon_states.yel_ind_s

-- create a turbine view in the unit app
---@param app pocket_app
---@param u_page nav_tree_page
---@param panes table
---@param tbn_pane graphics_element
---@param u_id integer unit ID
---@param t_id integer turbine ID
---@param ps psil
---@param update function
return function (app, u_page, panes, tbn_pane, u_id, t_id, ps, update)
    local db = iocontrol.get_db()

    local tbn_div = Div{parent=tbn_pane,x=2,width=tbn_pane.get_width()-2}
    table.insert(panes, tbn_div)

    local tbn_page = app.new_page(u_page, #panes)
    tbn_page.tasks = { update }

    TextBox{parent=tbn_div,y=1,text="TRBN #"..t_id,width=8,height=1}
    local status = StateIndicator{parent=tbn_div,x=10,y=1,states=style.turbine.states,value=1,min_width=12}
    status.register(ps, "TurbineStateStatus", status.update)

    local steam = VerticalBar{parent=tbn_div,x=1,y=4,fg_bg=cpair(colors.white,colors.gray),height=5,width=1}
    local ccool = VerticalBar{parent=tbn_div,x=21,y=4,fg_bg=cpair(colors.green,colors.gray),height=5,width=1}

    TextBox{parent=tbn_div,text="S",x=1,y=3,width=1,height=1,fg_bg=label}
    TextBox{parent=tbn_div,text="E",x=21,y=3,width=1,height=1,fg_bg=label}

    steam.register(ps, "steam_fill", steam.update)
    ccool.register(ps, "energy_fill", ccool.update)

    TextBox{parent=tbn_div,text="Production",x=3,y=3,width=17,height=1,fg_bg=label}
    local prod_rate = PowerIndicator{parent=tbn_div,x=3,y=4,lu_colors=lu_col,label="",format="%11.2f",value=0,rate=true,width=17,fg_bg=text_fg}
    TextBox{parent=tbn_div,text="Flow Rate",x=3,y=5,width=17,height=1,fg_bg=label}
    local flow_rate = DataIndicator{parent=tbn_div,x=3,y=6,lu_colors=lu_col,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=17,fg_bg=text_fg}
    TextBox{parent=tbn_div,text="Steam Input Rate",x=3,y=7,width=17,height=1,fg_bg=label}
    local input_rate = DataIndicator{parent=tbn_div,x=3,y=8,lu_colors=lu_col,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=17,fg_bg=text_fg}

    prod_rate.register(ps, "prod_rate", function (val) prod_rate.update(util.joules_to_fe(val)) end)
    flow_rate.register(ps, "flow_rate", flow_rate.update)
    input_rate.register(ps, "steam_input_rate", input_rate.update)

    local t_sdo = IconIndicator{parent=tbn_div,y=10,label="Steam Dumping",states=tri_ind_s}
    local t_tos  = IconIndicator{parent=tbn_div,label="Over Speed",states=red_ind_s}
    local t_gtrp  = IconIndicator{parent=tbn_div,label="Generator Trip",states=yel_ind_s}
    local t_trp  = IconIndicator{parent=tbn_div,label="Turbine Trip",states=red_ind_s}

    t_sdo.register(ps, "SteamDumpOpen", t_sdo.update)
    t_tos.register(ps, "TurbineOverSpeed", t_tos.update)
    t_gtrp.register(ps, "GeneratorTrip", t_gtrp.update)
    t_trp.register(ps, "TurbineTrip", t_trp.update)


    local tbn_ext_div = Div{parent=tbn_pane,x=2,width=tbn_pane.get_width()-2}
    table.insert(panes, tbn_ext_div)

    local tbn_ext_page = app.new_page(tbn_page, #panes)
    tbn_ext_page.tasks = { update }

    PushButton{parent=tbn_div,x=9,y=18,text="MORE",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=tbn_ext_page.nav_to}
    PushButton{parent=tbn_ext_div,x=9,y=18,text="BACK",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=tbn_page.nav_to}

    TextBox{parent=tbn_ext_div,y=1,text="More Turbine Info",height=1,alignment=ALIGN.CENTER}

    TextBox{parent=tbn_ext_div,text="Steam Tank",x=1,y=3,width=10,height=1,fg_bg=label}
    local steam_p = DataIndicator{parent=tbn_ext_div,x=14,y=3,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local steam_amnt = DataIndicator{parent=tbn_ext_div,x=1,y=4,lu_colors=lu_col,label="",unit="mB",format="%18.0f",value=0,commas=true,width=21,fg_bg=text_fg}

    steam_p.register(ps, "steam_fill", function (x) steam_p.update(x * 100) end)
    steam_amnt.register(ps, "steam", function (x) steam_amnt.update(x.amount) end)

    TextBox{parent=tbn_ext_div,text="Energy Fill",x=1,y=6,width=12,height=1,fg_bg=label}
    local charge_p = DataIndicator{parent=tbn_ext_div,x=14,y=6,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
    local charge_amnt = PowerIndicator{parent=tbn_ext_div,x=1,y=7,lu_colors=lu_col,label="",format="%17.4f",value=0,width=21,fg_bg=text_fg}

    charge_p.register(ps, "energy_fill", function (x) charge_p.update(x * 100) end)
    charge_amnt.register(ps, "energy", charge_amnt.update)

    TextBox{parent=tbn_ext_div,text="Rotation Rate",x=1,y=9,width=13,height=1,fg_bg=label}
    local rotation = DataIndicator{parent=tbn_ext_div,x=1,y=10,lu_colors=lu_col,label="",unit="",format="%21.12f",value=0,width=21,fg_bg=text_fg}

    rotation.register(ps, "steam", function ()
        local ok, result = pcall(function () return util.turbine_rotation(db.units[u_id].turbine_data_tbl[t_id]) end)
        if ok then rotation.update(result) end
    end)

    return tbn_page.nav_to
end
