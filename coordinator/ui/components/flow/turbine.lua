--
-- Flow Monitor Single Turbine Detail Block
--

local util           = require("scada-common.util")

local ioctl          = require("coordinator.ioctl")

local style          = require("coordinator.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local TextBox        = require("graphics.elements.TextBox")

local Rectangle      = require("graphics.elements.Rectangle")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local HorizontalBar  = require("graphics.elements.indicators.HorizontalBar")
local IndicatorLight = require("graphics.elements.indicators.IndicatorLight")
local VerticalBar    = require("graphics.elements.indicators.VerticalBar")

local ALIGN = core.ALIGN

local sprintf = util.sprintf

local border = core.border
local cpair = core.cpair

local gray = colors.gray

local water_c = cpair(colors.blue, gray)
local steam_c = cpair(colors.white, gray)

-- src/generators/java/mekanism/generators/client/render/RenderTurbineRotor.java
local MEK_BASE_SPEED  = 512
-- 20 ticks per second * 60 seconds per minute, 360 degrees per rotation
local ROTATION_TO_RPM = 60 * 20 * (MEK_BASE_SPEED / 360)

-- make a new turbine detail row item
---@param frame Container
---@param unit crd_io_unit
---@param tbn_id integer
return function (frame, unit, tbn_id)
    local s_field = style.theme.field_box

    local lu_c    = style.lu_colors

    local ind_yel = style.ind_yel
    local ind_red = style.ind_red
    local ind_wht = style.ind_wht

    local db   = ioctl.get_db()
    local ps   = unit.turbine_ps_tbl[tbn_id]
    local data = unit.turbine_data_tbl[tbn_id]

    local id_tag = Rectangle{parent=frame,x=2,y=1,width=24,height=3,border=border(1,gray,true),thin=true}
    TextBox{parent=id_tag,text="Turbine Generator "..tbn_id,alignment=ALIGN.CENTER}

    --#region tanks

    local steam_div = Div{parent=frame,x=2,y=6,width=24,height=8}

    local steam_bar = VerticalBar{parent=steam_div,fg_bg=steam_c,height=8,width=2}
    steam_bar.register(ps, "steam_fill", steam_bar.update)

    TextBox{parent=steam_div,x=4,y=1,text="Steam",width=21,fg_bg=style.label}
    local steam_amnt = DataIndicator{parent=steam_div,x=4,format="%18d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    steam_amnt.register(ps, "steam", function (x) steam_amnt.update(x.amount) end)

    TextBox{parent=steam_div,x=4,y=4,text="Steam Capacity",width=21,fg_bg=style.label}
    local steam_cap = DataIndicator{parent=steam_div,x=4,format="%18d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    steam_cap.register(ps, "steam_cap", steam_cap.update)

    TextBox{parent=steam_div,x=4,y=7,text="Steam Fill",width=21,fg_bg=style.label}
    local steam_fill = DataIndicator{parent=steam_div,x=4,format="%19.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    steam_fill.register(ps, "steam_fill", function (v) steam_fill.update(v * 100) end)

    local energy_div = Div{parent=frame,x=2,y=16,width=24,height=8}

    local energy_bar = VerticalBar{parent=energy_div,fg_bg=cpair(colors.blue,gray),height=8,width=2}
    energy_bar.register(ps, "energy_fill", energy_bar.update)

    TextBox{parent=energy_div,x=4,y=1,text="Energy",width=21,fg_bg=style.label}
    local energy = DataIndicator{parent=energy_div,x=4,format="%18.2f",value=0,unit=db.energy_label,commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    energy.register(ps, "energy", energy.update)

    TextBox{parent=energy_div,x=4,y=4,text="Energy Capacity",width=21,fg_bg=style.label}
    local energy_cap = DataIndicator{parent=energy_div,x=4,format="%18d",value=0,unit=db.energy_label,commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    energy_cap.register(ps, "max_energy", energy_cap.update)

    TextBox{parent=energy_div,x=4,y=7,text="Energy Fill",width=21,fg_bg=style.label}
    local energy_fill = DataIndicator{parent=energy_div,x=4,format="%19.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    energy_fill.register(ps, "energy_fill", function (v) energy_fill.update(v * 100) end)

    --#endregion
    --#region steam flow

    local s_flow = Rectangle{parent=frame,x=27,y=1,width=21,height=24,border=border(1,gray,true),thin=true}

    TextBox{parent=s_flow,text="Steam Flow",alignment=ALIGN.CENTER}

    TextBox{parent=s_flow,y=3,text="Vents",width=7,fg_bg=style.label}
    local vents = DataIndicator{parent=s_flow,format="%7d",value=0,commas=true,lu_colors=lu_c,width=7,fg_bg=s_field}
    vents.register(ps, "vents", vents.update)

    TextBox{parent=s_flow,x=9,y=3,text="Dispersers",width=11,fg_bg=style.label}
    local dispersers = DataIndicator{parent=s_flow,x=9,format="%11d",value=0,commas=true,lu_colors=lu_c,width=11,fg_bg=s_field}
    dispersers.register(ps, "dispersers", dispersers.update)

    TextBox{parent=s_flow,y=6,text="Min. Response Tau",width=19,fg_bg=style.label}
    local flow_perf = DataIndicator{parent=s_flow,format="%19.6f",value=0,commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    flow_perf.register(ps, "flow_perf", flow_perf.update)

    TextBox{parent=s_flow,y=9,text="Flow Response Tau",width=19,fg_bg=style.label}
    local flow_perf_l = DataIndicator{parent=s_flow,format="%19.6f",value=0,commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    flow_perf_l.register(ps, "flow_perf_live", flow_perf_l.update)

    TextBox{parent=s_flow,y=12,text="Maximum Flow Rate",width=19,fg_bg=style.label}
    local max_flow = DataIndicator{parent=s_flow,format="%14d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    max_flow.register(ps, "max_flow_rate", max_flow.update)

    TextBox{parent=s_flow,y=15,text="Steam Input Rate",width=19,fg_bg=style.label}
    local input_rate = DataIndicator{parent=s_flow,format="%14d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    input_rate.register(ps, "steam_input_rate", input_rate.update)

    TextBox{parent=s_flow,y=18,text="Steam Flow Rate",width=19,fg_bg=style.label}
    local flow_rate = DataIndicator{parent=s_flow,format="%14d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    flow_rate.register(ps, "flow_rate", flow_rate.update)

    TextBox{parent=s_flow,y=21,text="Flow Utilization",width=19,fg_bg=style.label}
    local flow_bar = HorizontalBar{parent=s_flow,show_percent=true,bar_fg_bg=steam_c,height=1,width=19}
    flow_bar.register(ps, "flow_rate", function (v) flow_bar.update(v / data.build.max_flow_rate) end)

    --#endregion
    --#region generator

    local e_flow = Rectangle{parent=frame,x=49,y=1,width=23,height=24,border=border(1,gray,true),thin=true}

    TextBox{parent=e_flow,text="Generator",alignment=ALIGN.CENTER}

    TextBox{parent=e_flow,y=3,text="Coils",width=10,fg_bg=style.label}
    local coils = DataIndicator{parent=e_flow,format="%10d",value=0,commas=true,lu_colors=lu_c,width=10,fg_bg=s_field}
    coils.register(ps, "coils", coils.update)

    TextBox{parent=e_flow,x=12,y=3,text="Blades",width=10,fg_bg=style.label}
    local blades = DataIndicator{parent=e_flow,x=12,format="%10d",value=0,commas=true,lu_colors=lu_c,width=910,fg_bg=s_field}
    blades.register(ps, "blades", blades.update)

    TextBox{parent=e_flow,y=6,text="Efficiency",width=10,fg_bg=style.label}
    local eff = DataIndicator{parent=e_flow,format="%8.2f",value=0,unit="%",lu_colors=lu_c,width=10,fg_bg=s_field}
    eff.register(ps, "gen_eff", function (e) eff.update(e * 100) end)

    TextBox{parent=e_flow,x=12,y=6,text="Multiplier",width=10,fg_bg=style.label}
    local mult = DataIndicator{parent=e_flow,x=12,format="%10.6f",value=0,lu_colors=lu_c,width=10,fg_bg=s_field}
    mult.register(ps, "gen_mult", mult.update)

    TextBox{parent=e_flow,y=9,text="Maximum Production",width=21,fg_bg=style.label}
    local max_prod = DataIndicator{parent=e_flow,format="%18d",value=0,unit="FE",commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    max_prod.register(ps, "max_production", max_prod.update)

    TextBox{parent=e_flow,y=12,text="Production Rate",width=21,fg_bg=style.label}
    local prod_rate = DataIndicator{parent=e_flow,format="%18d",value=0,unit="FE",commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    prod_rate.register(ps, "prod_rate", prod_rate.update)

    TextBox{parent=e_flow,y=15,text="Production Util.",width=21,fg_bg=style.label}
    local prod_bar = HorizontalBar{parent=e_flow,show_percent=true,bar_fg_bg=cpair(colors.green,gray),height=1,width=21}
    prod_bar.register(ps, "prod_rate", function (v) prod_bar.update(v / data.build.max_production) end)

    TextBox{parent=e_flow,y=18,text="Rotor Rotation",width=21,fg_bg=style.label}
    local rpm = DataIndicator{parent=e_flow,format="%17.4f",value=0,unit="RPM",commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    rpm.register(ps, "flow_rate", function (v) rpm.update(ROTATION_TO_RPM * (v / data.build.max_flow_rate)) end)

    TextBox{parent=e_flow,y=21,text="Rotation Speed",width=21,fg_bg=style.label}
    local rpm_bar = HorizontalBar{parent=e_flow,show_percent=true,bar_fg_bg=cpair(colors.black,gray),height=1,width=21}
    rpm_bar.register(ps, "flow_rate", function (v) rpm_bar.update(v / data.build.max_flow_rate) end)

    --#endregion
    --#region water flow

    local w_flow = Rectangle{parent=frame,x=73,y=1,width=21,height=15,border=border(1,gray,true),thin=true}

    TextBox{parent=w_flow,text="Water Return",alignment=ALIGN.CENTER}

    TextBox{parent=w_flow,y=3,text="Condensers",width=19,fg_bg=style.label}
    local condensers = DataIndicator{parent=w_flow,format="%19d",value=0,commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    condensers.register(ps, "condensers", condensers.update)

    TextBox{parent=w_flow,y=6,text="Max. Water Output",width=19,fg_bg=style.label}
    local max_water = DataIndicator{parent=w_flow,format="%14d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    max_water.register(ps, "max_water_output", max_water.update)

    TextBox{parent=w_flow,y=9,text="Water Flow Rate",width=19,fg_bg=style.label}
    local water_ret = DataIndicator{parent=w_flow,format="%14d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    water_ret.register(ps, "flow_rate", function (r) water_ret.update(math.min(r, data.build.max_water_output)) end)

    TextBox{parent=w_flow,y=12,text="Water Return Util.",width=19,fg_bg=style.label}
    local water_bar = HorizontalBar{parent=w_flow,show_percent=true,bar_fg_bg=water_c,height=1,width=19}
    water_bar.register(ps, "flow_rate", function (v) water_bar.update(v / data.build.max_water_output) end)

    --#endregion
    --#region dumping

    local dumping = Rectangle{parent=frame,x=73,y=17,width=21,height=8,border=border(1,gray,true),thin=true}

    TextBox{parent=dumping,text="Steam Dumping\nMode",alignment=ALIGN.CENTER}

    local d_n = IndicatorLight{parent=dumping,y=4,label="Not Dumping",colors=ind_wht}
    local d_e = IndicatorLight{parent=dumping,label="Dumping Excess",colors=ind_yel}
    local d_a = IndicatorLight{parent=dumping,label="Dumping All Steam",colors=ind_red}
    d_n.register(ps, "SteamDumpOpen", function (m) d_n.update(m == 1) end)
    d_e.register(ps, "SteamDumpOpen", function (m) d_e.update(m == 2) end)
    d_a.register(ps, "SteamDumpOpen", function (m) d_a.update(m == 3) end)

    --#endregion
    --#region simulation details

    local sim = Rectangle{parent=frame,x=95,y=1,width=44,height=24,border=border(1,gray,true),thin=true}

    TextBox{parent=sim,text="Steam Inlet Pressure",width=28,fg_bg=style.label}
    local inlet_p = DataIndicator{parent=sim,x=29,y=1,format="%10.2f",value=0,unit="bar",lu_colors=lu_c,width=14,fg_bg=s_field}
    inlet_p.register(ps, "phys_inlet_p", inlet_p.update)

    local inlet_p_bar = HorizontalBar{parent=sim,y=3,thin_bar=true,bar_fg_bg=steam_c,height=1,width=42}
    inlet_p_bar.register(ps, "phys_inlet_p", function (v) inlet_p_bar.update(v / (ps.get("phys_inlet_p_max") or math.huge)) end)

    TextBox{parent=sim,y=4,text="| 0 bar",width=7,fg_bg=style.label}
    local inlet_p_mid = TextBox{parent=sim,x=21,y=4,text="| ? bar",width=10,fg_bg=style.label}
    local inlet_p_max = TextBox{parent=sim,x=33,y=4,text="   ? bar |",fg_bg=style.label}
    inlet_p_mid.register(ps, "phys_inlet_p_max", function (v) inlet_p_mid.set_value(sprintf("| %d bar", v / 2)) end)
    inlet_p_max.register(ps, "phys_inlet_p_max", function (v) inlet_p_max.set_value(sprintf("%4d bar |", v)) end)

    TextBox{parent=sim,y=6,text="Exhaust Gas Pressure",width=28,fg_bg=style.label}
    local exhaust_p = DataIndicator{parent=sim,x=29,y=6,format="%10.2f",value=0,unit="bar",lu_colors=lu_c,width=14,fg_bg=s_field}
    exhaust_p.register(ps, "phys_exhaust_p", exhaust_p.update)

    local exhaust_p_bar = HorizontalBar{parent=sim,y=8,thin_bar=true,bar_fg_bg=steam_c,height=1,width=42}
    exhaust_p_bar.register(ps, "phys_exhaust_p", function (v) exhaust_p_bar.update(v / (ps.get("phys_exhaust_p_max") or math.huge)) end)

    TextBox{parent=sim,y=9,text="| 0 bar",width=7,fg_bg=style.label}
    local exhaust_p_mid = TextBox{parent=sim,x=21,y=9,text="| ? bar",width=10,fg_bg=style.label}
    local exhaust_p_max = TextBox{parent=sim,x=33,y=9,text="   ? bar |",width=10,fg_bg=style.label}
    exhaust_p_mid.register(ps, "phys_exhaust_p_max", function (v) exhaust_p_mid.set_value(sprintf("| %d bar", v / 2)) end)
    exhaust_p_max.register(ps, "phys_exhaust_p_max", function (v) exhaust_p_max.set_value(sprintf("%4d bar |", v)) end)

    TextBox{parent=sim,y=12,text="Steam Input Rate",width=18,fg_bg=style.label}
    local inlet_f = DataIndicator{parent=sim,x=20,y=12,format="%18d",value=0,unit="kg/s",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    inlet_f.register(ps, "phys_inlet_f", inlet_f.update)

    local inlet_f_bar = HorizontalBar{parent=sim,y=13,thin_bar=true,bar_fg_bg=steam_c,height=1,width=42}
    inlet_f_bar.register(ps, "phys_inlet_f", function (v) inlet_f_bar.update(v / (ps.get("phys_inlet_f_max") or math.huge)) end)

    TextBox{parent=sim,y=14,text="| 0 kg/s",width=8,fg_bg=style.label}
    local inlet_f_max = TextBox{parent=sim,x=22,y=14,text="             ? kg/s |",width=21,fg_bg=style.label}
    inlet_f_max.register(ps, "phys_inlet_f_max", function (v) inlet_f_max.set_value(sprintf("%14d kg/s |", v)) end)

    TextBox{parent=sim,y=16,text="Steam Flow Rate",width=18,fg_bg=style.label}
    local steam_f = DataIndicator{parent=sim,x=20,y=16,format="%18d",value=0,unit="kg/s",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    steam_f.register(ps, "phys_steam_f", steam_f.update)

    local steam_f_bar = HorizontalBar{parent=sim,y=17,thin_bar=true,bar_fg_bg=steam_c,height=1,width=42}
    steam_f_bar.register(ps, "phys_steam_f", function (v) steam_f_bar.update(v / (ps.get("phys_steam_f_max") or math.huge)) end)

    TextBox{parent=sim,y=18,text="| 0 kg/s",width=8,fg_bg=style.label}
    local steam_f_max = TextBox{parent=sim,x=22,y=18,text="             ? kg/s |",width=21,fg_bg=style.label}
    steam_f_max.register(ps, "phys_steam_f_max", function (v) steam_f_max.set_value(sprintf("%14d kg/s |", v)) end)

    TextBox{parent=sim,y=20,text="Water Return Rate",width=18,fg_bg=style.label}
    local water_f = DataIndicator{parent=sim,x=20,y=20,format="%18d",value=0,unit="kg/s",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    water_f.register(ps, "phys_water_f", water_f.update)

    local water_f_bar = HorizontalBar{parent=sim,y=21,thin_bar=true,bar_fg_bg=water_c,height=1,width=42}
    water_f_bar.register(ps, "phys_water_f", function (v) water_f_bar.update(v / (ps.get("phys_water_f_max") or math.huge)) end)

    TextBox{parent=sim,y=22,text="| 0 kg/s",width=8,fg_bg=style.label}
    local water_f_max = TextBox{parent=sim,x=22,y=22,text="             ? kg/s |",width=21,fg_bg=style.label}
    water_f_max.register(ps, "phys_water_f_max", function (v) water_f_max.set_value(sprintf("%14d kg/s |", v)) end)

    --#endregion
end
