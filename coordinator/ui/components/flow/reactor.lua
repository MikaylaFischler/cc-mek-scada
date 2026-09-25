--
-- Flow Monitor Reactor Detail View
--

local const         = require("scada-common.constants")
local types         = require("scada-common.types")
local util          = require("scada-common.util")

local ioctl         = require("coordinator.ioctl")

local style         = require("coordinator.ui.style")

local make_window   = require("coordinator.ui.components.flow.window")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local TextBox       = require("graphics.elements.TextBox")

local Rectangle     = require("graphics.elements.Rectangle")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")
local HorizontalBar = require("graphics.elements.indicators.HorizontalBar")
local VerticalBar   = require("graphics.elements.indicators.VerticalBar")

local ALIGN = core.ALIGN

local sprintf = util.sprintf

local border = core.border
local cpair = core.cpair

local wh_gray = style.wh_gray
local gray = colors.gray

local c_Na_c  = cpair(colors.lightBlue, gray)
local h_Na_c  = cpair(colors.orange, gray)
local water_c = cpair(colors.blue, gray)
local steam_c = cpair(colors.white, gray)

-- make a new reactor detail window
---@param parent Container parent
---@param unit_id integer unit index
---@param close_cb function window close callback
local function make(parent, unit_id, close_cb)
    local s_field = style.theme.field_box

    local lu_c = style.lu_colors

    local db   = ioctl.get_db()
    local unit = db.units[unit_id]
    local ps   = unit.unit_ps

    local window = make_window(parent, 126, 33, "Fission Reactor Details - Unit "..unit_id, close_cb)

    --#region fuel system

    local fuel_sys = Rectangle{parent=window,x=2,y=1,width=25,height=29,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}

    TextBox{parent=fuel_sys,text="Fuel System",alignment=ALIGN.CENTER}

    TextBox{parent=fuel_sys,y=3,text="Assemblies",width=10,fg_bg=style.label}
    local fuel_asm = DataIndicator{parent=fuel_sys,format="%10d",value=0,commas=true,lu_colors=lu_c,width=10,fg_bg=s_field}
    fuel_asm.register(ps, "fuel_asm", fuel_asm.update)

    TextBox{parent=fuel_sys,y=3,x=12,text="Surface Area",width=12,fg_bg=style.label}
    local fuel_sa = DataIndicator{parent=fuel_sys,x=12,format="%9d",value=0,unit="m\xb2",commas=true,lu_colors=lu_c,width=12,fg_bg=s_field}
    fuel_sa.register(ps, "fuel_sa", fuel_sa.update)

    TextBox{parent=fuel_sys,y=6,text=" Burn Rates",alignment=ALIGN.CENTER,fg_bg=style.label}
    TextBox{parent=fuel_sys,y=7,text="Maximum",width=7,fg_bg=style.label}
    local max_burn = DataIndicator{parent=fuel_sys,x=9,y=7,format="%10.2f",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=15,fg_bg=s_field}
    max_burn.register(ps, "max_burn", max_burn.update)

    TextBox{parent=fuel_sys,y=8,text="Command",width=7,fg_bg=style.label}
    local burn_r = DataIndicator{parent=fuel_sys,x=9,y=8,format="%10.2f",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=15,fg_bg=s_field}
    burn_r.register(ps, "burn_rate", burn_r.update)

    TextBox{parent=fuel_sys,y=9,text="Actual",width=7,fg_bg=style.label}
    local a_burn_r = DataIndicator{parent=fuel_sys,x=9,y=9,format="%10.2f",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=15,fg_bg=s_field}
    a_burn_r.register(ps, "act_burn_rate", a_burn_r.update)

    local fuel_div = Div{parent=fuel_sys,y=11,height=8}

    local fuel_bar = VerticalBar{parent=fuel_div,fg_bg=cpair(style.theme.fuel_color,gray),height=8,width=2}
    fuel_bar.register(ps, "fuel_fill", fuel_bar.update)

    TextBox{parent=fuel_div,x=4,y=1,text="Fissile Fuel",fg_bg=style.label}
    local fuel = DataIndicator{parent=fuel_div,x=4,format="%17.0f",value=0,unit="mB",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    fuel.register(ps, "fuel", fuel.update)

    TextBox{parent=fuel_div,x=4,y=4,text="Fuel Capacity",fg_bg=style.label}
    local fuel_cap = DataIndicator{parent=fuel_div,x=4,format="%17.0f",value=0,unit="mB",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    fuel_cap.register(ps, "fuel_cap", fuel_cap.update)

    TextBox{parent=fuel_div,x=4,y=7,text="Fuel Fill",fg_bg=style.label}
    local fuel_fill = DataIndicator{parent=fuel_div,x=4,format="%18.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    fuel_fill.register(ps, "fuel_fill", function (v) fuel_fill.update(v * 100) end)

    local waste_div = Div{parent=fuel_sys,y=20,height=8}

    local waste_bar = VerticalBar{parent=waste_div,fg_bg=cpair(colors.brown,gray),height=8,width=2}
    waste_bar.register(ps, "waste_fill", waste_bar.update)

    TextBox{parent=waste_div,x=4,y=1,text="Nuclear Waste",fg_bg=style.label}
    local waste = DataIndicator{parent=waste_div,x=4,format="%17d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    waste.register(ps, "waste", waste.update)

    TextBox{parent=waste_div,x=4,y=4,text="Waste Capacity",fg_bg=style.label}
    local waste_cap = DataIndicator{parent=waste_div,x=4,format="%17d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    waste_cap.register(ps, "waste_cap", waste_cap.update)

    TextBox{parent=waste_div,x=4,y=7,text="Waste Fill",fg_bg=style.label}
    local waste_fill = DataIndicator{parent=waste_div,x=4,format="%18.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    waste_fill.register(ps, "waste_fill", function (v) waste_fill.update(v * 100) end)

    --#endregion
    --#region heat management

    local heat_mgmt = Rectangle{parent=window,x=28,y=1,width=25,height=29,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}

    TextBox{parent=heat_mgmt,y=1,text="Heat Management",alignment=ALIGN.CENTER}

    TextBox{parent=heat_mgmt,y=3,text="Heat Capacity",width=23,fg_bg=style.label}
    local heat_cap = DataIndicator{parent=heat_mgmt,format="%21d",value=0,unit="J",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    heat_cap.register(ps, "heat_cap", heat_cap.update)

    TextBox{parent=heat_mgmt,y=6,text="Environmental Loss",width=23,fg_bg=style.label}
    local env_loss = DataIndicator{parent=heat_mgmt,format="%19d",value=0,unit="J/t",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    env_loss.register(ps, "env_loss_J", env_loss.update)

    TextBox{parent=heat_mgmt,y=10,text="Water Cooled Peak Operating Temperature",width=23,fg_bg=style.label}
    local max_op_h2o = DataIndicator{parent=heat_mgmt,format="%20.4f",value=0,unit=db.temp_label,commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    max_op_h2o.register(ps, "max_op_temp_H2O", function (t) max_op_h2o.update(db.temp_convert(t)) end)

    TextBox{parent=heat_mgmt,y=14,text="Sodium Cooled Peak Operating Temperature",width=23,fg_bg=style.label}
    local max_op_na = DataIndicator{parent=heat_mgmt,format="%20.4f",value=0,unit=db.temp_label,commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    max_op_na.register(ps, "max_op_temp_Na", function (t) max_op_na.update(db.temp_convert(t)) end)

    TextBox{parent=heat_mgmt,y=18,text="Core Temperature",width=23,fg_bg=style.label}
    local core_temp = DataIndicator{parent=heat_mgmt,format="%20.2f",value=0,unit=db.temp_label,lu_colors=lu_c,width=23,fg_bg=s_field}
    core_temp.register(ps, "temp", function (t) core_temp.update(db.temp_convert(t)) end)

    TextBox{parent=heat_mgmt,y=21,text="Temp. Percentage of Design Maximum",width=23,fg_bg=style.label}
    local op_temp_scale = HorizontalBar{parent=heat_mgmt,show_percent=true,bar_fg_bg=cpair(colors.magenta,gray),height=1,width=23}
    op_temp_scale.register(ps, "temp", function (t)
        t = t - const.mek.BASE_BOIL_TEMP
        if unit.reactor_data.mek_status.ccool_type == types.FLUID.SODIUM then
            op_temp_scale.set_value(t / (unit.reactor_data.max_op_temp_Na - const.mek.BASE_BOIL_TEMP))
        else
            op_temp_scale.set_value(t / (unit.reactor_data.max_op_temp_H2O - const.mek.BASE_BOIL_TEMP))
        end
    end)

    TextBox{parent=heat_mgmt,y=25,text="Temp. Percentage of Safe Maximum",width=23,fg_bg=style.label}
    local max_temp_scale = HorizontalBar{parent=heat_mgmt,show_percent=true,bar_fg_bg=cpair(colors.magenta,gray),height=1,width=23}
    max_temp_scale.register(ps, "temp", function (t) max_temp_scale.update((t - const.mek.BASE_BOIL_TEMP) / (const.RPS_LIMITS.MAX_DAMAGE_TEMPERATURE - const.mek.BASE_BOIL_TEMP)) end)

    --#endregion
    --#region cooling system

    local cool_sys = Rectangle{parent=window,x=54,y=1,width=25,height=29,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}

    TextBox{parent=cool_sys,y=1,text="Coolant System",alignment=ALIGN.CENTER}

    TextBox{parent=cool_sys,y=3,text="Boil Efficiency",fg_bg=style.label}
    local boil_eff = DataIndicator{parent=cool_sys,format="%21.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    boil_eff.register(ps, "boil_eff", function (x) boil_eff.update(x * 100) end)

    TextBox{parent=cool_sys,y=7,text="Heating Rate",fg_bg=style.label}
    local heating_r = DataIndicator{parent=cool_sys,format="%18.0f",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    heating_r.register(ps, "heating_rate", heating_r.update)

    local ccool_div = Div{parent=cool_sys,y=11,height=8}

    local ccool_bar = VerticalBar{parent=ccool_div,fg_bg=water_c,height=8,width=2}
    ccool_bar.register(ps, "ccool_fill", ccool_bar.update)

    ccool_bar.register(ps, "ccool_type", function (type)
        ccool_bar.recolor((type == types.FLUID.SODIUM) and c_Na_c or water_c)
    end)

    TextBox{parent=ccool_div,x=4,y=1,text="Cooled Coolant",fg_bg=style.label}
    local ccool = DataIndicator{parent=ccool_div,x=4,format="%17d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    ccool.register(ps, "ccool_amnt", ccool.update)

    TextBox{parent=ccool_div,x=4,y=4,text="Coolant Capacity",fg_bg=style.label}
    local ccool_cap = DataIndicator{parent=ccool_div,x=4,format="%17d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    ccool_cap.register(ps, "ccool_cap", ccool_cap.update)

    TextBox{parent=ccool_div,x=4,y=7,text="Coolant Fill",fg_bg=style.label}
    local ccool_fill = DataIndicator{parent=ccool_div,x=4,format="%18.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    ccool_fill.register(ps, "ccool_fill", function (v) ccool_fill.update(v * 100) end)

    local hcool_div = Div{parent=cool_sys,y=20,height=8}

    local hcool_bar = VerticalBar{parent=hcool_div,fg_bg=cpair(colors.blue,gray),height=8,width=2}
    hcool_bar.register(ps, "hcool_fill", hcool_bar.update)

    hcool_bar.register(ps, "hcool_type", function (type)
        hcool_bar.recolor((type == types.FLUID.SUPERHEATED_SODIUM) and h_Na_c or steam_c)
    end)

    TextBox{parent=hcool_div,x=4,y=1,text="Heated Coolant",fg_bg=style.label}
    local hcool = DataIndicator{parent=hcool_div,x=4,format="%17d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    hcool.register(ps, "hcool_amnt", hcool.update)

    TextBox{parent=hcool_div,x=4,y=4,text="Coolant Capacity",fg_bg=style.label}
    local hcool_cap = DataIndicator{parent=hcool_div,x=4,format="%17d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    hcool_cap.register(ps, "hcool_cap", hcool_cap.update)

    TextBox{parent=hcool_div,x=4,y=7,text="Coolant Fill",fg_bg=style.label}
    local hcool_fill = DataIndicator{parent=hcool_div,x=4,format="%18.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=20,fg_bg=s_field}
    hcool_fill.register(ps, "hcool_fill", function (v) hcool_fill.update(v * 100) end)

    --#endregion
    --#region simulation details

    local sim_p = Rectangle{parent=window,x=80,y=1,width=44,height=23,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}

    TextBox{parent=sim_p,x=1,y=1,text="Reactor Pressures",alignment=ALIGN.CENTER}

    TextBox{parent=sim_p,y=3,text="Cooled Coolant Tank Pressure",width=28,fg_bg=style.label}
    local ccool_p = DataIndicator{parent=sim_p,x=30,y=3,format="%9.2f",value=0,unit="bar",lu_colors=lu_c,width=13,fg_bg=s_field}
    ccool_p.register(ps, "phys_ccool_p", ccool_p.update)

    local ccool_p_bar = HorizontalBar{parent=sim_p,y=5,thin_bar=true,bar_fg_bg=wh_gray,height=1,width=42}
    ccool_p_bar.register(ps, "phys_ccool_p", function (v) ccool_p_bar.update(v / (ps.get("phys_ccool_p_max") or math.huge)) end)

    ccool_p_bar.register(ps, "ccool_type", function (type)
        ccool_p_bar.recolor((type == types.FLUID.SODIUM) and c_Na_c or water_c)
    end)

    TextBox{parent=sim_p,y=6,text="| 0 bar",width=7,fg_bg=style.label}
    local cccol_p_mid = TextBox{parent=sim_p,x=21,y=6,text="| ? bar",width=10,fg_bg=style.label}
    local ccool_p_max = TextBox{parent=sim_p,x=33,y=6,text="   ? bar |",fg_bg=style.label}
    cccol_p_mid.register(ps, "phys_ccool_p_max", function (v) cccol_p_mid.set_value(sprintf("| %d bar", v / 2)) end)
    ccool_p_max.register(ps, "phys_ccool_p_max", function (v) ccool_p_max.set_value(sprintf("%4d bar |", v)) end)

    TextBox{parent=sim_p,y=8,text="Heated Coolant Tank Pressure",width=28,fg_bg=style.label}
    local hcool_p = DataIndicator{parent=sim_p,x=30,y=8,format="%9.2f",value=0,unit="bar",lu_colors=lu_c,width=13,fg_bg=s_field}
    hcool_p.register(ps, "phys_hcool_p", hcool_p.update)

    local hcool_p_bar = HorizontalBar{parent=sim_p,y=10,thin_bar=true,bar_fg_bg=wh_gray,height=1,width=42}
    hcool_p_bar.register(ps, "phys_hcool_p", function (v) hcool_p_bar.update(v / (ps.get("phys_hcool_p_max") or math.huge)) end)

    hcool_p_bar.register(ps, "hcool_type", function (type)
        hcool_p_bar.recolor((type == types.FLUID.SUPERHEATED_SODIUM) and h_Na_c or steam_c)
    end)

    TextBox{parent=sim_p,y=11,text="| 0 bar",width=7,fg_bg=style.label}
    local hccol_p_mid = TextBox{parent=sim_p,x=21,y=11,text="| ? bar",width=10,fg_bg=style.label}
    local hcool_p_max = TextBox{parent=sim_p,x=33,y=11,text="   ? bar |",width=10,fg_bg=style.label}
    hccol_p_mid.register(ps, "phys_hcool_p_max", function (v) hccol_p_mid.set_value(sprintf("| %d bar", v / 2)) end)
    hcool_p_max.register(ps, "phys_hcool_p_max", function (v) hcool_p_max.set_value(sprintf("%4d bar |", v)) end)

    TextBox{parent=sim_p,y=13,text="Reactor Vessel Pressure",width=28,fg_bg=style.label}
    local vessel_p = DataIndicator{parent=sim_p,x=30,y=13,format="%9.2f",value=0,unit="bar",lu_colors=lu_c,width=13,fg_bg=s_field}
    vessel_p.register(ps, "phys_vessel_p", vessel_p.update)

    local vessel_p_bar = HorizontalBar{parent=sim_p,y=15,thin_bar=true,bar_fg_bg=cpair(colors.red,gray),height=1,width=42}
    vessel_p_bar.register(ps, "phys_vessel_p", function (v) vessel_p_bar.update(v / (ps.get("phys_vessel_p_max") or math.huge)) end)

    TextBox{parent=sim_p,y=16,text="| 0 bar",width=7,fg_bg=style.label}
    local vessel_p_mid = TextBox{parent=sim_p,x=21,y=16,text="| ? bar",width=10,fg_bg=style.label}
    local vessel_p_max = TextBox{parent=sim_p,x=33,y=16,text="   ? bar |",width=10,fg_bg=style.label}
    vessel_p_mid.register(ps, "phys_vessel_p_max", function (v) vessel_p_mid.set_value(sprintf("| %d bar", v / 2)) end)
    vessel_p_max.register(ps, "phys_vessel_p_max", function (v) vessel_p_max.set_value(sprintf("%4d bar |", v)) end)

    TextBox{parent=sim_p,y=18,text="Coolant Flow Rate",width=18,fg_bg=style.label}
    local cool_f = DataIndicator{parent=sim_p,x=20,y=18,format="%18d",value=0,unit="kg/s",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    cool_f.register(ps, "phys_cool_f", cool_f.update)

    local cool_f_bar = HorizontalBar{parent=sim_p,y=20,thin_bar=true,bar_fg_bg=wh_gray,height=1,width=42}
    cool_f_bar.register(ps, "phys_cool_f", function (v) cool_f_bar.update(v / (ps.get("phys_cool_f_max") or math.huge)) end)

    cool_f_bar.register(ps, "hcool_type", function (type)
        cool_f_bar.recolor((type == types.FLUID.SUPERHEATED_SODIUM) and h_Na_c or steam_c)
    end)

    TextBox{parent=sim_p,y=21,text="| 0 kg/s",width=8,fg_bg=style.label}
    local cool_f_max = TextBox{parent=sim_p,x=22,y=21,text="             ? kg/s |",width=21,fg_bg=style.label}
    cool_f_max.register(ps, "phys_cool_f_max", function (v) cool_f_max.set_value(sprintf("%14d kg/s |", v)) end)

    --#endregion
    --#region containment

    local cont = Rectangle{parent=window,x=80,y=25,width=44,height=5,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}

    TextBox{parent=cont,x=1,y=1,text="Reactor Containment",alignment=ALIGN.CENTER}

    TextBox{parent=cont,y=3,text="Damage",width=6,fg_bg=style.label}

    local damage_v = DataIndicator{parent=cont,x=8,y=3,format="%12d",value=0,unit="%",commas=true,lu_colors=lu_c,width=14,fg_bg=s_field}
    damage_v.register(ps, "damage", damage_v.update)

    local damage_p = HorizontalBar{parent=cont,x=23,y=3,bar_fg_bg=cpair(colors.red,gray),height=1,width=20}
    damage_p.register(ps, "damage", damage_p.update)

    --#endregion
end

return make
