--
-- Flow Monitor Single Boiler Detail Block
--

local util          = require("scada-common.util")

local ioctl         = require("coordinator.ioctl")

local style         = require("coordinator.ui.style")

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

local gray = colors.gray

local c_Na_c  = cpair(colors.lightBlue, gray)
local h_Na_c  = cpair(colors.orange, gray)
local water_c = cpair(colors.blue, gray)
local steam_c = cpair(colors.white, gray)

-- make a new boiler detail row item
---@param frame Container
---@param unit crd_io_unit
---@param blr_id integer
return function (frame, unit, blr_id)
    local s_field = style.theme.field_box

    local lu_c = style.lu_colors

    local db   = ioctl.get_db()
    local ps   = unit.boiler_ps_tbl[blr_id]
    local data = unit.boiler_data_tbl[blr_id]

    local id_tag = Rectangle{parent=frame,x=2,y=1,width=24,height=3,border=border(1,gray,true),thin=true}
    TextBox{parent=id_tag,text="Sodium Boiler "..blr_id,alignment=ALIGN.CENTER}

    --#region reactor coolant loop

    local rc_loop = Rectangle{parent=frame,x=2,y=5,width=24,height=21,border=border(1,gray,true),thin=true}

    TextBox{parent=rc_loop,text="Reactor Coolant Loop",alignment=ALIGN.CENTER}

    local hcool_div = Div{parent=rc_loop,x=1,y=3,width=24,height=8}

    local hcool_bar = VerticalBar{parent=hcool_div,fg_bg=h_Na_c,height=8,width=2}
    hcool_bar.register(ps, "hcool_fill", hcool_bar.update)

    TextBox{parent=hcool_div,x=4,y=1,text="Superheated Sodium",width=19,fg_bg=style.label}
    local hcool_amnt = DataIndicator{parent=hcool_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    hcool_amnt.register(ps, "hcool", function (x) hcool_amnt.update(x.amount) end)

    TextBox{parent=hcool_div,x=4,y=4,text="Coolant Capacity",width=19,fg_bg=style.label}
    local hcool_cap = DataIndicator{parent=hcool_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    hcool_cap.register(ps, "hcoolant_cap", hcool_cap.update)

    TextBox{parent=hcool_div,x=4,y=7,text="Coolant Fill",width=19,fg_bg=style.label}
    local hcool_fill = DataIndicator{parent=hcool_div,x=4,format="%17.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    hcool_fill.register(ps, "hcool_fill", function (v) hcool_fill.update(v * 100) end)

    local ccool_div = Div{parent=rc_loop,x=1,y=12,width=24,height=8}

    local ccool_bar = VerticalBar{parent=ccool_div,fg_bg=c_Na_c,height=8,width=2}
    ccool_bar.register(ps, "ccool_fill", ccool_bar.update)

    TextBox{parent=ccool_div,x=4,y=1,text="Cooled Sodium",width=19,fg_bg=style.label}
    local ccool_amnt = DataIndicator{parent=ccool_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    ccool_amnt.register(ps, "ccool", function (x) ccool_amnt.update(x.amount) end)

    TextBox{parent=ccool_div,x=4,y=4,text="Coolant Capacity",width=19,fg_bg=style.label}
    local ccool_cap = DataIndicator{parent=ccool_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    ccool_cap.register(ps, "ccoolant_cap", ccool_cap.update)

    TextBox{parent=ccool_div,x=4,y=7,text="Coolant Fill",width=19,fg_bg=style.label}
    local ccool_fill = DataIndicator{parent=ccool_div,x=4,format="%17.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    ccool_fill.register(ps, "ccool_fill", function (v) ccool_fill.update(v * 100) end)

    --#endregion
    --#region heat exchanger

    local heat_ex = Rectangle{parent=frame,x=27,y=1,width=23,height=25,border=border(1,gray,true),thin=true}

    TextBox{parent=heat_ex,text="Heat Exchanger",alignment=ALIGN.CENTER}

    TextBox{parent=heat_ex,y=3,text="Superheating Elements",width=21,fg_bg=style.label}
    local superheaters = DataIndicator{parent=heat_ex,format="%21d",value=0,commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    superheaters.register(ps, "superheaters", superheaters.update)

    TextBox{parent=heat_ex,y=6,text="Boil Capacity",width=21,fg_bg=style.label}
    local boil_cap = DataIndicator{parent=heat_ex,format="%16d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    boil_cap.register(ps, "boil_cap", boil_cap.update)

    TextBox{parent=heat_ex,y=10,text="Temperature",width=21,fg_bg=style.label}
    local temp = DataIndicator{parent=heat_ex,format="%18.2f",value=0,unit=db.temp_label,commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    temp.register(ps, "temperature", function (t) temp.update(db.temp_convert(t)) end)

    TextBox{parent=heat_ex,y=13,text="Maximum Boil at Temp.",width=21,fg_bg=style.label}
    local max_boil = DataIndicator{parent=heat_ex,format="%16d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    max_boil.register(ps, "max_boil_rate", max_boil.update)

    TextBox{parent=heat_ex,y=16,text="Boil Rate",width=21,fg_bg=style.label}
    local boil = DataIndicator{parent=heat_ex,format="%16d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=21,fg_bg=s_field}
    boil.register(ps, "boil_rate", boil.update)

    TextBox{parent=heat_ex,y=19,text="Boil Performance",width=21,fg_bg=style.label}
    local boil_perf = HorizontalBar{parent=heat_ex,show_percent=true,bar_fg_bg=cpair(colors.red,gray),height=1,width=21}
    boil_perf.register(ps, "boil_rate", function (v) boil_perf.update(v / (data.state.max_boil_rate == 0 and math.huge or data.state.max_boil_rate)) end)

    TextBox{parent=heat_ex,y=22,text="Boil Capacity Util.",width=21,fg_bg=style.label}
    local cap_bar = HorizontalBar{parent=heat_ex,show_percent=true,bar_fg_bg=cpair(colors.red,gray),height=1,width=21}
    cap_bar.register(ps, "boil_rate", function (v) cap_bar.update(v / data.build.boil_cap) end)

    --#endregion
    --#region turbine steam loop

    local ts_loop = Rectangle{parent=frame,x=51,y=1,width=24,height=25,border=border(1,gray,true),thin=true}

    TextBox{parent=ts_loop,text="Turbine Steam Loop",alignment=ALIGN.CENTER}

    TextBox{parent=ts_loop,y=3,text="Feedwater Min / Needed",width=22,fg_bg=style.label}
    local water_min = DataIndicator{parent=ts_loop,format="%17d",value=0,unit="mB/t",commas=true,lu_colors=lu_c,width=22,fg_bg=s_field}
    local water_need = DataIndicator{parent=ts_loop,format="%19d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=22,fg_bg=s_field}
    water_min.register(ps, "max_boil_rate", water_min.update)
    water_need.register(ps, "water_need", water_need.update)

    local water_div = Div{parent=ts_loop,x=1,y=7,width=24,height=8}

    local water_bar = VerticalBar{parent=water_div,fg_bg=water_c,height=8,width=2}
    water_bar.register(ps, "water_fill", water_bar.update)

    TextBox{parent=water_div,x=4,y=1,text="Supply Feedwater",width=19,fg_bg=style.label}
    local water_amnt = DataIndicator{parent=water_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    water_amnt.register(ps, "water", function (x) water_amnt.update(x.amount) end)

    TextBox{parent=water_div,x=4,y=4,text="Water Capacity",width=19,fg_bg=style.label}
    local water_cap = DataIndicator{parent=water_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    water_cap.register(ps, "water_cap", water_cap.update)

    TextBox{parent=water_div,x=4,y=7,text="Water Fill",width=19,fg_bg=style.label}
    local water_fill = DataIndicator{parent=water_div,x=4,format="%17.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    water_fill.register(ps, "water_fill", function (v) water_fill.update(v * 100) end)

    local steam_div = Div{parent=ts_loop,x=1,y=16,width=24,height=8}

    local steam_bar = VerticalBar{parent=steam_div,fg_bg=steam_c,height=8,width=2}
    steam_bar.register(ps, "steam_fill", steam_bar.update)

    TextBox{parent=steam_div,x=4,y=1,text="Superheated Steam",width=19,fg_bg=style.label}
    local steam_amnt = DataIndicator{parent=steam_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    steam_amnt.register(ps, "steam", function (x) steam_amnt.update(x.amount) end)

    TextBox{parent=steam_div,x=4,y=4,text="Steam Capacity",width=19,fg_bg=style.label}
    local steam_cap = DataIndicator{parent=steam_div,x=4,format="%16d",value=0,unit="mB",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    steam_cap.register(ps, "steam_cap", steam_cap.update)

    TextBox{parent=steam_div,x=4,y=7,text="Steam Fill",width=19,fg_bg=style.label}
    local steam_fill = DataIndicator{parent=steam_div,x=4,format="%17.2f",value=0,unit="%",commas=true,lu_colors=lu_c,width=19,fg_bg=s_field}
    steam_fill.register(ps, "steam_fill", function (v) steam_fill.update(v * 100) end)

    --#endregion
    --#region simulation details

    local sim = Rectangle{parent=frame,x=76,y=1,width=44,height=25,border=border(1,gray,true),thin=true}

    TextBox{parent=sim,x=1,y=1,text="Technical Details",alignment=ALIGN.CENTER}

    TextBox{parent=sim,y=3,text="Water Tank Pressure",width=29,fg_bg=style.label}
    local water_p = DataIndicator{parent=sim,x=29,y=3,format="%10.2f",value=0,unit="bar",lu_colors=lu_c,width=14,fg_bg=s_field}
    water_p.register(ps, "phys_water_p", water_p.update)

    local water_p_bar = HorizontalBar{parent=sim,y=5,thin_bar=true,bar_fg_bg=steam_c,height=1,width=42}
    water_p_bar.register(ps, "phys_water_p", function (v) water_p_bar.update(v / (ps.get("phys_water_p_max") or math.huge)) end)

    TextBox{parent=sim,y=6,text="| 0 bar",width=7,fg_bg=style.label}
    local water_p_mid = TextBox{parent=sim,x=21,y=6,text="| ? bar",width=10,fg_bg=style.label}
    local water_p_max = TextBox{parent=sim,x=33,y=6,text="   ? bar |",fg_bg=style.label}
    water_p_mid.register(ps, "phys_water_p_max", function (v) water_p_mid.set_value(sprintf("| %d bar", v / 2)) end)
    water_p_max.register(ps, "phys_water_p_max", function (v) water_p_max.set_value(sprintf("%4d bar |", v)) end)

    TextBox{parent=sim,y=8,text="Steam Tank Pressure",width=28,fg_bg=style.label}
    local steam_p = DataIndicator{parent=sim,x=29,y=8,format="%10.2f",value=0,unit="bar",lu_colors=lu_c,width=14,fg_bg=s_field}
    steam_p.register(ps, "phys_steam_p", steam_p.update)

    local steam_p_bar = HorizontalBar{parent=sim,y=10,thin_bar=true,bar_fg_bg=steam_c,height=1,width=42}
    steam_p_bar.register(ps, "phys_steam_p", function (v) steam_p_bar.update(v / (ps.get("phys_steam_p_max") or math.huge)) end)

    TextBox{parent=sim,y=11,text="| 0 bar",width=7,fg_bg=style.label}
    local steam_p_mid = TextBox{parent=sim,x=21,y=11,text="| ? bar",width=10,fg_bg=style.label}
    local steam_p_max = TextBox{parent=sim,x=33,y=11,text="   ? bar |",width=10,fg_bg=style.label}
    steam_p_mid.register(ps, "phys_steam_p_max", function (v) steam_p_mid.set_value(sprintf("| %d bar", v / 2)) end)
    steam_p_max.register(ps, "phys_steam_p_max", function (v) steam_p_max.set_value(sprintf("%4d bar |", v)) end)

    TextBox{parent=sim,y=13,text="Combined Boiler Pressure",width=28,fg_bg=style.label}
    local boiler_p = DataIndicator{parent=sim,x=29,y=13,format="%10.2f",value=0,unit="bar",lu_colors=lu_c,width=14,fg_bg=s_field}
    boiler_p.register(ps, "phys_boiler_p", boiler_p.update)

    local boiler_p_bar = HorizontalBar{parent=sim,y=15,thin_bar=true,bar_fg_bg=cpair(colors.red,gray),height=1,width=42}
    boiler_p_bar.register(ps, "phys_boiler_p", function (v) boiler_p_bar.update(v / (ps.get("phys_boiler_p_max") or math.huge)) end)

    TextBox{parent=sim,y=16,text="| 0 bar",width=7,fg_bg=style.label}
    local boiler_p_mid = TextBox{parent=sim,x=21,y=16,text="| ? bar",width=10,fg_bg=style.label}
    local boiler_p_max = TextBox{parent=sim,x=33,y=16,text="   ? bar |",width=10,fg_bg=style.label}
    boiler_p_mid.register(ps, "phys_boiler_p_max", function (v) boiler_p_mid.set_value(sprintf("| %d bar", v / 2)) end)
    boiler_p_max.register(ps, "phys_boiler_p_max", function (v) boiler_p_max.set_value(sprintf("%4d bar |", v)) end)

    TextBox{parent=sim,y=20,text="Steam Flow Rate",width=18,fg_bg=style.label}
    local steam_f = DataIndicator{parent=sim,x=20,y=20,format="%18d",value=0,unit="kg/s",commas=true,lu_colors=lu_c,width=23,fg_bg=s_field}
    steam_f.register(ps, "phys_steam_flow", steam_f.update)

    local steam_f_bar = HorizontalBar{parent=sim,y=22,thin_bar=true,bar_fg_bg=steam_c,height=1,width=42}
    steam_f_bar.register(ps, "phys_steam_flow", function (v) steam_f_bar.update(v / (ps.get("phys_steam_flow_max") or math.huge)) end)

    TextBox{parent=sim,y=23,text="| 0 kg/s",width=8,fg_bg=style.label}
    local steam_f_max = TextBox{parent=sim,x=22,y=23,text="             ? kg/s |",width=21,fg_bg=style.label}
    steam_f_max.register(ps, "phys_steam_flow_max", function (v) steam_f_max.set_value(sprintf("%14d kg/s |", v)) end)

    --#endregion
end
