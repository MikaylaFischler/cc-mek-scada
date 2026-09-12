--
-- Basic Unit Flow Overview
--

local types             = require("scada-common.types")
local util              = require("scada-common.util")
local const         = require("scada-common.constants")

local ioctl             = require("coordinator.ioctl")

local style             = require("coordinator.ui.style")

local waste_flow        = require("coordinator.ui.components.waste_flow")

local core              = require("graphics.core")

local Div               = require("graphics.elements.Div")
local PipeNetwork       = require("graphics.elements.PipeNetwork")
local TextBox           = require("graphics.elements.TextBox")

local Rectangle         = require("graphics.elements.Rectangle")

local PushButton        = require("graphics.elements.controls.PushButton")

local DataIndicator     = require("graphics.elements.indicators.DataIndicator")
local VerticalBar  = require("graphics.elements.indicators.VerticalBar")
local HorizontalBar  = require("graphics.elements.indicators.HorizontalBar")
local TriIndicatorLight = require("graphics.elements.indicators.TriIndicatorLight")

local COOLANT_TYPE = types.COOLANT_TYPE

local ALIGN = core.ALIGN

local sprintf = util.sprintf

local border = core.border
local cpair = core.cpair
local pipe = core.pipe

local wh_gray = style.wh_gray
local lg_gray = style.lg_gray

-- make a new unit flow window
---@param parent Container parent
---@param unit_id integer unit index
local function make(parent, unit_id, c)
    local s_field = style.theme.field_box

    local text_c = style.text_colors
    local lu_c = style.lu_colors

    local fac  = ioctl.get_db().facility
    local unit = ioctl.get_db().units[unit_id]

    local ps = unit.unit_ps
    local db   = ioctl.get_db()

    -- bounding box div
    local root = Div{parent=parent,x=math.floor((parent.get_width()-140)/2),y=4,width=140,height=29}

    TextBox{parent=root,x=1,y=1,height=1,text=string.rep("\x8f",137),fg_bg=cpair(parent.get_fg_bg().bkg,colors.gray)}
    TextBox{parent=root,x=1,y=2,text=" Fission Reactor Details - Unit "..unit_id,fg_bg=cpair(colors.white,colors.gray)}

    PushButton{parent=root,x=138,y=1,min_width=3,text="\x8f\x8f\x8f",fg_bg=cpair(parent.get_fg_bg().bkg,colors.red),callback=c}
    PushButton{parent=root,x=138,y=2,min_width=3,text="\xd7",fg_bg=cpair(colors.white,colors.red),callback=c}

    local window = Rectangle{parent=root,x=1,y=3,border=border(1,colors.gray,true),fg_bg=parent.get_fg_bg()}

    --#region tanks

    local fuel_div = Div{parent=window,x=2,y=1,width=22,height=8}

    local fuel_bar  = VerticalBar{parent=fuel_div,fg_bg=cpair(style.theme.fuel_color,colors.gray),height=8,width=2}
    fuel_bar.register(ps, "fuel_fill", fuel_bar.update)

    TextBox{parent=fuel_div,x=4,y=1,text="Fissile Fuel",width=19,fg_bg=style.label}
    local fuel = DataIndicator{parent=fuel_div,x=4,format="%16.0f",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    fuel.register(ps, "fuel", fuel.update)

    TextBox{parent=fuel_div,x=4,y=4,text="Fuel Capacity",width=19,fg_bg=style.label}
    local fuel_cap = DataIndicator{parent=fuel_div,x=4,format="%16.0f",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    fuel_cap.register(ps, "fuel_cap", fuel_cap.update)

    TextBox{parent=fuel_div,x=4,y=7,text="Fuel Fill",width=19,fg_bg=style.label}
    local fuel_fill = DataIndicator{parent=fuel_div,x=4,format="%17.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    fuel_fill.register(ps, "fuel_fill", function (v) fuel_fill.update(v * 100) end)

    local waste_div = Div{parent=window,x=26,y=1,width=22,height=8}

    local waste_bar  = VerticalBar{parent=waste_div,fg_bg=cpair(colors.brown,colors.gray),height=8,width=2}
    waste_bar.register(ps, "waste_fill", waste_bar.update)

    TextBox{parent=waste_div,x=4,y=1,text="Nuclear Waste",width=19,fg_bg=style.label}
    local waste = DataIndicator{parent=waste_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    waste.register(ps, "waste", waste.update)

    TextBox{parent=waste_div,x=4,y=4,text="Waste Capacity",width=19,fg_bg=style.label}
    local waste_cap = DataIndicator{parent=waste_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    waste_cap.register(ps, "waste_cap", waste_cap.update)

    TextBox{parent=waste_div,x=4,y=7,text="Waste Fill",width=19,fg_bg=style.label}
    local waste_fill = DataIndicator{parent=waste_div,x=4,format="%17.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    waste_fill.register(ps, "waste_fill", function (v) waste_fill.update(v * 100) end)

    local ccool_div = Div{parent=window,x=2,y=10,width=22,height=8}

    local ccool_bar  = VerticalBar{parent=ccool_div,fg_bg=cpair(colors.blue,colors.gray),height=8,width=2}
    ccool_bar.register(ps, "ccool_fill", ccool_bar.update)

    ccool_bar.register(ps, "ccool_type", function (type)
        if type == types.FLUID.SODIUM then
            ccool_bar.recolor(cpair(colors.lightBlue, colors.gray))
        else
            ccool_bar.recolor(cpair(colors.blue, colors.gray))
        end
    end)

    TextBox{parent=ccool_div,x=4,y=1,text="Cooled Coolant",width=19,fg_bg=style.label}
    local ccool = DataIndicator{parent=ccool_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    ccool.register(ps, "ccool_amnt", ccool.update)

    TextBox{parent=ccool_div,x=4,y=4,text="Coolant Capacity",width=19,fg_bg=style.label}
    local ccool_cap = DataIndicator{parent=ccool_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    ccool_cap.register(ps, "ccool_cap", ccool_cap.update)

    TextBox{parent=ccool_div,x=4,y=7,text="Coolant Fill",width=19,fg_bg=style.label}
    local ccool_fill = DataIndicator{parent=ccool_div,x=4,format="%17.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    ccool_fill.register(ps, "ccool_fill", function (v) ccool_fill.update(v * 100) end)

    local hcool_div = Div{parent=window,x=26,y=10,width=22,height=8}

    local hcool_bar  = VerticalBar{parent=hcool_div,fg_bg=cpair(colors.blue,colors.gray),height=8,width=2}
    hcool_bar.register(ps, "hcool_fill", hcool_bar.update)

    hcool_bar.register(ps, "hcool_type", function (type)
        if type == types.FLUID.SUPERHEATED_SODIUM then
            hcool_bar.recolor(cpair(colors.orange, colors.gray))
        else
            hcool_bar.recolor(cpair(colors.white, colors.gray))
        end
    end)

    TextBox{parent=hcool_div,x=4,y=1,text="Heated Coolant",width=19,fg_bg=style.label}
    local hcool = DataIndicator{parent=hcool_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    hcool.register(ps, "hcool_amnt", hcool.update)

    TextBox{parent=hcool_div,x=4,y=4,text="Coolant Capacity",width=19,fg_bg=style.label}
    local hcool_cap = DataIndicator{parent=hcool_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    hcool_cap.register(ps, "hcool_cap", hcool_cap.update)

    TextBox{parent=hcool_div,x=4,y=7,text="Coolant Fill",width=19,fg_bg=style.label}
    local hcool_fill = DataIndicator{parent=hcool_div,x=4,format="%17.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    hcool_fill.register(ps, "hcool_fill", function (v) hcool_fill.update(v * 100) end)

    --#endregion
    --#region properties

    TextBox{parent=window,x=2,y=19,text=string.rep("\x8c",46),width=47,fg_bg=cpair(colors.gray,colors._INHERIT)}

    local props_div = Div{parent=window,x=2,y=20,width=90,height=5}

    TextBox{parent=props_div,y=2,text="Water Cooled Peak Operating Temperature",width=22,fg_bg=style.label}
    local max_op_h2o = DataIndicator{parent=props_div,format="%20.4f",value=0,unit=db.temp_label,commas=true,lu_colors=lu_c,width=22,fg_bg=s_field}
    max_op_h2o.register(ps, "max_op_temp_H2O", function (t) max_op_h2o.update(db.temp_convert(t)) end)

    TextBox{parent=props_div,x=25,y=2,text="Sodium Cooled Peak Operating Temperature",width=22,fg_bg=style.label}
    local max_op_na = DataIndicator{parent=props_div,x=25,format="%20.4f",value=0,unit=db.temp_label,commas=true,lu_colors=lu_c,width=22,fg_bg=s_field}
    max_op_na.register(ps, "max_op_temp_Na", function (t) max_op_na.update(db.temp_convert(t)) end)

    TextBox{parent=props_div,x=50,y=1,text="Fuel Assemblies",width=19,fg_bg=style.label}
    local fuel_asm = DataIndicator{parent=props_div,x=50,format="%19d",value=0,commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    fuel_asm.register(ps, "fuel_asm", fuel_asm.update)

    TextBox{parent=props_div,x=50,y=4,text="Fuel Surface Area",width=19,fg_bg=style.label}
    local fuel_sa = DataIndicator{parent=props_div,x=50,format="%16d",value=0,unit="m\xb2",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    fuel_sa.register(ps, "fuel_sa", fuel_sa.update)

    TextBox{parent=props_div,x=72,y=1,text="Maximum Burn Rate",width=19,fg_bg=style.label}
    local max_burn = DataIndicator{parent=props_div,x=72,format="%14d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    max_burn.register(ps, "max_burn", max_burn.update)

    TextBox{parent=props_div,x=72,y=4,text="Heat Capacity",width=19,fg_bg=style.label}
    local heat_cap = DataIndicator{parent=props_div,x=72,format="%17d",value=0,unit="J",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    heat_cap.register(ps, "heat_cap", heat_cap.update)

    --#endregion
    --#region reaction

    local reaction = Rectangle{parent=window,x=50,y=1,width=21,height=18,border=border(1,colors.gray,true),thin=true,fg_bg=parent.get_fg_bg()}

    TextBox{parent=reaction,x=1,y=1,text="Reaction",alignment=ALIGN.CENTER}

    TextBox{parent=reaction,y=3,text="Commanded Burn Rate",width=19,fg_bg=style.label}
    local burn_r = DataIndicator{parent=reaction,format="%14.2f",value=0,unit="mB/t",lu_colors=lu_c,width=19,fg_bg=s_field}
    burn_r.register(ps, "burn_rate", burn_r.update)

    TextBox{parent=reaction,y=6,text="Actual Burn Rate",width=19,fg_bg=style.label}
    local a_burn_r = DataIndicator{parent=reaction,format="%14.2f",value=0,unit="mB/t",lu_colors=lu_c,width=19,fg_bg=s_field}
    a_burn_r.register(ps, "act_burn_rate", a_burn_r.update)

    TextBox{parent=reaction,y=9,text="Heating Rate",width=19,fg_bg=style.label}
    local heating_r = DataIndicator{parent=reaction,format="%14.0f",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    heating_r.register(ps, "heating_rate", heating_r.update)

    TextBox{parent=reaction,y=12,text="Environmental Loss",width=19,fg_bg=style.label}
    local env_loss = DataIndicator{parent=reaction,format="%14d",value=0,unit="J/t",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    env_loss.register(ps, "env_loss_J", env_loss.update)

    TextBox{parent=reaction,y=15,text="Boil Efficiency",width=19,fg_bg=style.label}
    local boil_eff = DataIndicator{parent=reaction,format="%17.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    boil_eff.register(ps, "boil_eff", function (x) boil_eff.update(x * 100) end)

    --#endregion
    --#region thermals

    local thermals = Rectangle{parent=window,x=72,y=1,width=21,height=12,border=border(1,colors.gray,true),thin=true,fg_bg=parent.get_fg_bg()}

    TextBox{parent=thermals,x=1,y=1,text="Thermals",alignment=ALIGN.CENTER}

    TextBox{parent=thermals,y=3,text="Core Temperature",width=19,fg_bg=style.label}
    local core_temp = DataIndicator{parent=thermals,format="%16.2f",value=0,unit=db.temp_label,lu_colors=lu_c,width=19,fg_bg=s_field}
    core_temp.register(ps, "temp", function (t) core_temp.update(db.temp_convert(t)) end)

    TextBox{parent=thermals,y=6,text="% of Design Maximum",width=19,fg_bg=style.label}
    local op_temp_scale = HorizontalBar{parent=thermals,show_percent=true,bar_fg_bg=cpair(colors.magenta,colors.gray),height=1,width=19}
    op_temp_scale.register(ps, "temp", function (t)
        t = t - const.mek.BASE_BOIL_TEMP
        if unit.reactor_data.mek_status.ccool_type == types.FLUID.SODIUM then
            op_temp_scale.set_value(t / ((unit.reactor_data.max_op_temp_Na - const.mek.BASE_BOIL_TEMP) or 1))
        else
            op_temp_scale.set_value(t / ((unit.reactor_data.max_op_temp_H2O - const.mek.BASE_BOIL_TEMP) or 1))
        end
    end)

    TextBox{parent=thermals,y=9,text="% of Safe Maximum",width=19,fg_bg=style.label}
    local max_temp_scale = HorizontalBar{parent=thermals,show_percent=true,bar_fg_bg=cpair(colors.magenta,colors.gray),height=1,width=19}
    max_temp_scale.register(ps, "temp", function (t) max_temp_scale.update((t - const.mek.BASE_BOIL_TEMP) / (const.RPS_LIMITS.MAX_DAMAGE_TEMPERATURE - const.mek.BASE_BOIL_TEMP)) end)

    --#endregion
    --#region damage

    local damage = Rectangle{parent=window,x=72,y=14,width=21,height=5,border=border(1,colors.gray,true),thin=true,fg_bg=parent.get_fg_bg()}

    TextBox{parent=damage,x=1,y=1,text="Damage",alignment=ALIGN.CENTER}

    local damage_p = HorizontalBar{parent=damage,y=3,show_percent=true,bar_fg_bg=cpair(colors.red,colors.gray),height=1,width=19}
    damage_p.register(ps, "damage", damage_p.update)

    --#endregion

    return root
end

return make
