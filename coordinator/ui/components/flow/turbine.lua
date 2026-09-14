--
-- Flow Monitor Turbine Detail View
--

local const         = require("scada-common.constants")
local types         = require("scada-common.types")
local util          = require("scada-common.util")

local ioctl         = require("coordinator.ioctl")

local style         = require("coordinator.ui.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local TextBox       = require("graphics.elements.TextBox")

local Rectangle     = require("graphics.elements.Rectangle")

local PushButton    = require("graphics.elements.controls.PushButton")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local HorizontalBar  = require("graphics.elements.indicators.HorizontalBar")
local IndicatorLight = require("graphics.elements.indicators.IndicatorLight")
local PowerIndicator = require("graphics.elements.indicators.PowerIndicator")
local VerticalBar    = require("graphics.elements.indicators.VerticalBar")

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

    local ind_yel = style.ind_yel
    local ind_red = style.ind_red
    local ind_wht = style.ind_wht

    local db   = ioctl.get_db()
    local unit = db.units[unit_id]
    local ps   = unit.turbine_ps_tbl[1]

    -- bounding box div
    local root = Div{parent=parent,x=math.floor((parent.get_width()-140)/2),y=1,width=142,height=78}

    local s = (unit.num_turbines > 1) and "s" or ""

    TextBox{parent=root,x=1,y=1,height=1,text=string.rep("\x8f",139),fg_bg=cpair(parent.get_fg_bg().bkg,gray)}
    TextBox{parent=root,x=1,y=2,text=" Steam Turbine Generator"..s.." Details - Unit "..unit_id,fg_bg=cpair(colors.white,gray)}

    PushButton{parent=root,x=140,y=1,min_width=3,text="\x8f\x8f\x8f",fg_bg=cpair(parent.get_fg_bg().bkg,colors.red),callback=close_cb}
    PushButton{parent=root,x=140,y=2,min_width=3,text="\xd7",fg_bg=cpair(colors.white,colors.red),callback=close_cb}

    local window = Rectangle{parent=root,x=1,y=3,border=border(1,gray,true),fg_bg=parent.get_fg_bg()}

    local id_tag = Rectangle{parent=window,x=2,y=1,width=24,height=3,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}
    TextBox{parent=id_tag,text="Turbine Generator 1",alignment=ALIGN.CENTER}

    --#region tanks

    local steam_div = Div{parent=window,x=2,y=6,width=22,height=8}

    local steam_bar  = VerticalBar{parent=steam_div,fg_bg=steam_c,height=8,width=2}
    steam_bar.register(ps, "steam_fill", steam_bar.update)

    TextBox{parent=steam_div,x=4,y=1,text="Steam",width=19,fg_bg=style.label}
    local steam_amnt = DataIndicator{parent=steam_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    steam_amnt.register(ps, "steam", function (x) steam_amnt.update(x.amount) end)

    TextBox{parent=steam_div,x=4,y=4,text="Steam Capacity",width=19,fg_bg=style.label}
    local steam_cap = DataIndicator{parent=steam_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    steam_cap.register(ps, "steam_cap", steam_cap.update)

    TextBox{parent=steam_div,x=4,y=7,text="Steam Fill",width=19,fg_bg=style.label}
    local steam_fill = DataIndicator{parent=steam_div,x=4,format="%17.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    steam_fill.register(ps, "steam_fill", function (v) steam_fill.update(v * 100) end)

    local energy_div = Div{parent=window,x=2,y=16,width=24,height=8}

    local energy_bar  = VerticalBar{parent=energy_div,fg_bg=cpair(colors.blue,gray),height=8,width=2}
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

    local s_flow = Rectangle{parent=window,x=27,y=1,width=21,height=24,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}
    Rectangle{parent=window,x=27,y=26,width=21,height=24,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}
    Rectangle{parent=window,x=27,y=51,width=21,height=24,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}

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
    flow_bar.register(ps, "flow_rate", function (v) flow_bar.update(v / (ps.get("max_flow_rate") or math.huge)) end)

    --#endregion
    --#region generator

    local e_flow = Rectangle{parent=window,x=49,y=1,width=23,height=24,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}

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
    prod_bar.register(ps, "prod_rate", function (v) prod_bar.update(v / (ps.get("max_production") or math.huge)) end)

    TextBox{parent=e_flow,y=18,text="Rotor Rotation",width=21,fg_bg=style.label}
    local rpm = DataIndicator{parent=e_flow,format="%17.4f",value=0,unit="RPM",commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    rpm.register(ps, "flow_rate", function (v) rpm.update(512 * (v / (ps.get("max_flow_rate") or math.huge))) end)

    TextBox{parent=e_flow,y=21,text="Rotation Speed",width=21,fg_bg=style.label}
    local rpm_bar = HorizontalBar{parent=e_flow,show_percent=true,bar_fg_bg=cpair(colors.black,gray),height=1,width=21}
    rpm_bar.register(ps, "flow_rate", function (v) rpm_bar.update(v / (ps.get("max_flow_rate") or math.huge)) end)

    --#endregion
    --#region water flow

    local w_flow = Rectangle{parent=window,x=73,y=1,width=21,height=15,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}

    TextBox{parent=w_flow,text="Water Return",alignment=ALIGN.CENTER}

    TextBox{parent=w_flow,y=3,text="Condensers",width=19,fg_bg=style.label}
    local condensers = DataIndicator{parent=w_flow,format="%19d",value=0,commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    condensers.register(ps, "condensers", condensers.update)

    TextBox{parent=w_flow,y=6,text="Max. Water Output",width=19,fg_bg=style.label}
    local max_water = DataIndicator{parent=w_flow,format="%14d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    max_water.register(ps, "max_water_output", max_water.update)

    TextBox{parent=w_flow,y=9,text="Water Flow Rate",width=19,fg_bg=style.label}
    local water_ret = DataIndicator{parent=w_flow,format="%14d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    water_ret.register(ps, "flow_rate", function (r) water_ret.update(math.min(r, ps.get("max_water_output"))) end)

    TextBox{parent=w_flow,y=12,text="Water Return Util.",width=19,fg_bg=style.label}
    local water_bar = HorizontalBar{parent=w_flow,show_percent=true,bar_fg_bg=water_c,height=1,width=19}
    water_bar.register(ps, "flow_rate", function (v) water_bar.update(v / (ps.get("max_water_output") or math.huge)) end)

    --#endregion
    --#region dumping

    local dumping = Rectangle{parent=window,x=73,y=17,width=21,height=8,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}

    TextBox{parent=dumping,text="Steam Dumping\nMode",alignment=ALIGN.CENTER}

    local d_n = IndicatorLight{parent=dumping,y=4,label="Not Dumping",colors=ind_wht}
    local d_e = IndicatorLight{parent=dumping,label="Dumping Excess",colors=ind_yel}
    local d_a = IndicatorLight{parent=dumping,label="Dumping All Steam",colors=ind_red}
    d_n.register(ps, "SteamDumpOpen", function (m) d_n.update(m == 1) end)
    d_e.register(ps, "SteamDumpOpen", function (m) d_e.update(m == 2) end)
    d_a.register(ps, "SteamDumpOpen", function (m) d_a.update(m == 3) end)

    --#endregion
    --#region technical details

    local sim = Rectangle{parent=window,x=95,y=1,width=44,height=26,border=border(1,gray,true),thin=true,fg_bg=parent.get_fg_bg()}

    TextBox{parent=sim,y=1,text="Steam Inlet Pressure",width=28,fg_bg=style.label}
    local inlet_p = DataIndicator{parent=sim,x=30,y=1,format="%9.2f",value=0,unit="bar",lu_colors=lu_c,width=14,fg_bg=s_field}
    inlet_p.register(ps, "phys_inlet_p", inlet_p.update)

    local inlet_p_bar = HorizontalBar{parent=sim,y=3,thin_bar=true,bar_fg_bg=steam_c,height=1,width=42}
    inlet_p_bar.register(ps, "phys_inlet_p", function (v) inlet_p_bar.update(v / (ps.get("phys_inlet_p_max") or 1)) end)

    TextBox{parent=sim,y=4,text="| 0 bar",width=7,fg_bg=style.label}
    local inlet_p_mid = TextBox{parent=sim,x=21,y=4,text="| ? bar",width=10,fg_bg=style.label}
    local inlet_p_max = TextBox{parent=sim,x=33,y=4,text="   ? bar |",fg_bg=style.label}
    inlet_p_mid.register(ps, "phys_inlet_p_max", function (v) inlet_p_mid.set_value(sprintf("| %d bar", v / 2)) end)
    inlet_p_max.register(ps, "phys_inlet_p_max", function (v) inlet_p_max.set_value(sprintf("%4d bar |", v)) end)

    TextBox{parent=sim,y=6,text="Exhaust Gas Pressure",width=28,fg_bg=style.label}
    local exhaust_p = DataIndicator{parent=sim,x=30,y=6,format="%9.2f",value=0,unit="bar",lu_colors=lu_c,width=14,fg_bg=s_field}
    exhaust_p.register(ps, "phys_exhaust_p", exhaust_p.update)

    local exhaust_p_bar = HorizontalBar{parent=sim,y=8,thin_bar=true,bar_fg_bg=wh_gray,height=1,width=42}
    exhaust_p_bar.register(ps, "phys_exhaust_p", function (v) exhaust_p_bar.update(v / (ps.get("phys_exhaust_p_max") or 1)) end)

    TextBox{parent=sim,y=9,text="| 0 bar",width=7,fg_bg=style.label}
    local exhaust_p_mid = TextBox{parent=sim,x=21,y=9,text="| ? bar",width=10,fg_bg=style.label}
    local exhaust_p_max = TextBox{parent=sim,x=33,y=9,text="   ? bar |",width=10,fg_bg=style.label}
    exhaust_p_mid.register(ps, "phys_exhaust_p_max", function (v) exhaust_p_mid.set_value(sprintf("| %d bar", v / 2)) end)
    exhaust_p_max.register(ps, "phys_exhaust_p_max", function (v) exhaust_p_max.set_value(sprintf("%4d bar |", v)) end)

    TextBox{parent=sim,y=11,text="Steam Input Rate",width=18,fg_bg=style.label}
    local inlet_f = DataIndicator{parent=sim,x=20,y=11,format="%18d",value=0,unit="kg/s",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    inlet_f.register(ps, "phys_inlet_flow", inlet_f.update)

    local inlet_f_bar = HorizontalBar{parent=sim,y=13,thin_bar=true,bar_fg_bg=steam_c,height=1,width=42}
    inlet_f_bar.register(ps, "phys_inlet_flow", function (v) inlet_f_bar.update(v / (ps.get("phys_inlet_flow_max") or 1)) end)

    TextBox{parent=sim,y=14,text="| 0 kg/s",width=8,fg_bg=style.label}
    local inlet_f_max = TextBox{parent=sim,x=22,y=14,text="             ? kg/s |",width=21,fg_bg=style.label}
    inlet_f_max.register(ps, "phys_inlet_flow_max", function (v) inlet_f_max.set_value(sprintf("%14d kg/s |", v)) end)

    TextBox{parent=sim,y=16,text="Steam Flow Rate",width=18,fg_bg=style.label}
    local steam_f = DataIndicator{parent=sim,x=20,y=16,format="%18d",value=0,unit="kg/s",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    steam_f.register(ps, "phys_steam_flow", steam_f.update)

    local steam_f_bar = HorizontalBar{parent=sim,y=18,thin_bar=true,bar_fg_bg=steam_c,height=1,width=42}
    steam_f_bar.register(ps, "phys_steam_flow", function (v) steam_f_bar.update(v / (ps.get("phys_steam_flow_max") or 1)) end)

    TextBox{parent=sim,y=19,text="| 0 kg/s",width=8,fg_bg=style.label}
    local steam_f_max = TextBox{parent=sim,x=22,y=19,text="             ? kg/s |",width=21,fg_bg=style.label}
    steam_f_max.register(ps, "phys_steam_flow_max", function (v) steam_f_max.set_value(sprintf("%14d kg/s |", v)) end)

    TextBox{parent=sim,y=21,text="Water Return Rate",width=18,fg_bg=style.label}
    local water_f = DataIndicator{parent=sim,x=20,y=21,format="%18d",value=0,unit="kg/s",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    water_f.register(ps, "phys_water_flow", water_f.update)

    local water_f_bar = HorizontalBar{parent=sim,y=23,thin_bar=true,bar_fg_bg=water_c,height=1,width=42}
    water_f_bar.register(ps, "phys_water_flow", function (v) water_f_bar.update(v / (ps.get("phys_water_flow_max") or 1)) end)

    TextBox{parent=sim,y=24,text="| 0 kg/s",width=8,fg_bg=style.label}
    local water_f_max = TextBox{parent=sim,x=22,y=24,text="             ? kg/s |",width=21,fg_bg=style.label}
    water_f_max.register(ps, "phys_water_flow_max", function (v) water_f_max.set_value(sprintf("%14d kg/s |", v)) end)

    --#endregion

    return root
end

return make
