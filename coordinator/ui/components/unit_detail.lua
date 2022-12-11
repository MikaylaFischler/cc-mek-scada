--
-- Reactor Unit SCADA Coordinator GUI
--

local iocontrol         = require("coordinator.iocontrol")

local style             = require("coordinator.ui.style")

local core              = require("graphics.core")

local Div               = require("graphics.elements.div")
local Rectangle         = require("graphics.elements.rectangle")
local TextBox           = require("graphics.elements.textbox")

local AlarmLight        = require("graphics.elements.indicators.alight")
local CoreMap           = require("graphics.elements.indicators.coremap")
local DataIndicator     = require("graphics.elements.indicators.data")
local IndicatorLight    = require("graphics.elements.indicators.light")
local TriIndicatorLight = require("graphics.elements.indicators.trilight")
local VerticalBar       = require("graphics.elements.indicators.vbar")

local HazardButton      = require("graphics.elements.controls.hazard_button")
local MultiButton       = require("graphics.elements.controls.multi_button")
local PushButton        = require("graphics.elements.controls.push_button")
local SpinboxNumeric    = require("graphics.elements.controls.spinbox_numeric")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border

local period = core.flasher.PERIOD

local waste_opts = {
    {
        text = "Auto",
        fg_bg = cpair(colors.black, colors.lightGray),
        active_fg_bg = cpair(colors.white, colors.gray)
    },
    {
        text = "Pu",
        fg_bg = cpair(colors.black, colors.lightGray),
        active_fg_bg = cpair(colors.black, colors.green)
    },
    {
        text = "Po",
        fg_bg = cpair(colors.black, colors.lightGray),
        active_fg_bg = cpair(colors.black, colors.cyan)
    },
    {
        text = "AM",
        fg_bg = cpair(colors.black, colors.lightGray),
        active_fg_bg = cpair(colors.black, colors.purple)
    }
}

-- create a unit view
---@param parent graphics_element parent
---@param id integer
local function init(parent, id)
    local unit = iocontrol.get_db().units[id]   ---@type ioctl_entry
    local r_ps = unit.reactor_ps
    local b_ps = unit.boiler_ps_tbl
    local t_ps = unit.turbine_ps_tbl

    local main = Div{parent=parent,x=1,y=1}

    TextBox{parent=main,text="Reactor Unit #" .. id,alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    local hzd_fg_bg = cpair(colors.white, colors.gray)
    local lu_cpair  = cpair(colors.gray, colors.gray)

    -----------------------------
    -- main stats and core map --
    -----------------------------

    local core_map = CoreMap{parent=main,x=2,y=3,reactor_l=18,reactor_w=18}
    r_ps.subscribe("temp", core_map.update)
    r_ps.subscribe("size", function (s) core_map.resize(s[1], s[2]) end)

    local stat_fg_bg = cpair(colors.black,colors.white)

    TextBox{parent=main,x=2,y=22,text="Heating Rate",height=1,width=12,fg_bg=style.label}
    local heating_r = DataIndicator{parent=main,x=2,label="",format="%14.0f",value=0,unit="mB/t",commas=true,lu_colors=lu_cpair,width=19,fg_bg=stat_fg_bg}
    r_ps.subscribe("heating_rate", heating_r.update)

    TextBox{parent=main,x=2,y=25,text="Commanded Burn Rate",height=1,width=19,fg_bg=style.label}
    local burn_r = DataIndicator{parent=main,x=2,label="",format="%14.1f",value=0,unit="mB/t",lu_colors=lu_cpair,width=19,fg_bg=stat_fg_bg}
    r_ps.subscribe("burn_rate", burn_r.update)

    TextBox{parent=main,text="F",x=23,y=22,width=1,height=1,fg_bg=style.label}
    TextBox{parent=main,text="C",x=25,y=22,width=1,height=1,fg_bg=style.label}
    TextBox{parent=main,text="H",x=27,y=22,width=1,height=1,fg_bg=style.label}
    TextBox{parent=main,text="W",x=29,y=22,width=1,height=1,fg_bg=style.label}

    local fuel  = VerticalBar{parent=main,x=23,y=23,fg_bg=cpair(colors.black,colors.gray),height=4,width=1}
    local ccool = VerticalBar{parent=main,x=25,y=23,fg_bg=cpair(colors.blue,colors.gray),height=4,width=1}
    local hcool = VerticalBar{parent=main,x=27,y=23,fg_bg=cpair(colors.white,colors.gray),height=4,width=1}
    local waste = VerticalBar{parent=main,x=29,y=23,fg_bg=cpair(colors.brown,colors.gray),height=4,width=1}

    r_ps.subscribe("fuel_fill", fuel.update)
    r_ps.subscribe("ccool_fill", ccool.update)
    r_ps.subscribe("hcool_fill", hcool.update)
    r_ps.subscribe("waste_fill", waste.update)

    r_ps.subscribe("ccool_type", function (type)
        if type == "mekanism:sodium" then
            ccool.recolor(cpair(colors.lightBlue, colors.gray))
        else
            ccool.recolor(cpair(colors.blue, colors.gray))
        end
    end)

    r_ps.subscribe("hcool_type", function (type)
        if type == "mekanism:superheated_sodium" then
            hcool.recolor(cpair(colors.orange, colors.gray))
        else
            hcool.recolor(cpair(colors.white, colors.gray))
        end
    end)

    TextBox{parent=main,x=32,y=22,text="Core Temp",height=1,width=9,fg_bg=style.label}
    local core_temp = DataIndicator{parent=main,x=32,label="",format="%11.2f",value=0,unit="K",lu_colors=lu_cpair,width=13,fg_bg=stat_fg_bg}
    r_ps.subscribe("temp", core_temp.update)

    TextBox{parent=main,x=32,y=25,text="Burn Rate",height=1,width=9,fg_bg=style.label}
    local act_burn_r = DataIndicator{parent=main,x=32,label="",format="%8.1f",value=0,unit="mB/t",lu_colors=lu_cpair,width=13,fg_bg=stat_fg_bg}
    r_ps.subscribe("act_burn_rate", act_burn_r.update)

    TextBox{parent=main,x=32,y=28,text="Damage",height=1,width=6,fg_bg=style.label}
    local damage_p = DataIndicator{parent=main,x=32,label="",format="%11.0f",value=0,unit="%",lu_colors=lu_cpair,width=13,fg_bg=stat_fg_bg}
    r_ps.subscribe("damage", damage_p.update)

    ---@todo radiation monitor
    TextBox{parent=main,x=32,y=31,text="Radiation",height=1,width=21,fg_bg=style.label}
    DataIndicator{parent=main,x=32,label="",format="%7.2f",value=0,unit="mSv/h",lu_colors=lu_cpair,width=13,fg_bg=stat_fg_bg}

    -------------------
    -- system status --
    -------------------

    local u_stat = Rectangle{parent=main,border=border(1, colors.gray, true),thin=true,width=33,height=4,x=46,y=3,fg_bg=cpair(colors.black,colors.white)}
    local stat_line_1 = TextBox{parent=u_stat,x=1,y=1,text="UNKNOWN",width=33,height=1,alignment=TEXT_ALIGN.CENTER,fg_bg=cpair(colors.black, colors.white)}
    local stat_line_2 = TextBox{parent=u_stat,x=1,y=2,text="awaiting data",width=33,height=1,alignment=TEXT_ALIGN.CENTER,fg_bg=cpair(colors.gray, colors.white)}

    r_ps.subscribe("U_StatusLine1", stat_line_1.set_value)
    r_ps.subscribe("U_StatusLine2", stat_line_2.set_value)

    -----------------
    -- annunciator --
    -----------------

    -- annunciator colors (generally) per IAEA-TECDOC-812 recommendations

    local annunciator = Div{parent=main,width=23,height=18,x=22,y=3}

    -- connectivity/basic state
    local plc_online = IndicatorLight{parent=annunciator,label="PLC Online",colors=cpair(colors.green,colors.red)}
    local plc_hbeat  = IndicatorLight{parent=annunciator,label="PLC Heartbeat",colors=cpair(colors.white,colors.gray)}
    local r_active   = IndicatorLight{parent=annunciator,label="Active",colors=cpair(colors.green,colors.gray)}
    ---@todo auto control as info sent here
    local r_auto     = IndicatorLight{parent=annunciator,label="Auto. Control",colors=cpair(colors.blue,colors.gray)}

    annunciator.line_break()

    ---@todo radiation monitor
    local rad_mon    = IndicatorLight{parent=annunciator,label="Radiation Monitor",colors=cpair(colors.green,colors.gray)}

    r_ps.subscribe("PLCOnline", plc_online.update)
    r_ps.subscribe("PLCHeartbeat", plc_hbeat.update)
    r_ps.subscribe("status", r_active.update)

    annunciator.line_break()

    -- non-RPS reactor annunciator panel
    local r_scram = IndicatorLight{parent=annunciator,label="Reactor SCRAM",colors=cpair(colors.red,colors.gray)}
    local r_mscrm = IndicatorLight{parent=annunciator,label="Manual Reactor SCRAM",colors=cpair(colors.red,colors.gray)}
    local r_ascrm = IndicatorLight{parent=annunciator,label="Auto Reactor SCRAM",colors=cpair(colors.red,colors.gray)}
    local r_rtrip = IndicatorLight{parent=annunciator,label="RCP Trip",colors=cpair(colors.red,colors.gray)}
    local r_cflow = IndicatorLight{parent=annunciator,label="RCS Flow Low",colors=cpair(colors.yellow,colors.gray)}
    local r_clow  = IndicatorLight{parent=annunciator,label="Coolant  Level Low",colors=cpair(colors.yellow,colors.gray)}
    local r_temp  = IndicatorLight{parent=annunciator,label="Reactor Temp. High",colors=cpair(colors.red,colors.gray)}
    local r_rhdt  = IndicatorLight{parent=annunciator,label="Reactor High Delta T",colors=cpair(colors.yellow,colors.gray)}
    local r_firl  = IndicatorLight{parent=annunciator,label="Fuel Input Rate Low",colors=cpair(colors.yellow,colors.gray)}
    local r_wloc  = IndicatorLight{parent=annunciator,label="Waste Line Occlusion",colors=cpair(colors.yellow,colors.gray)}
    local r_hsrt  = IndicatorLight{parent=annunciator,label="Startup Rate High",colors=cpair(colors.yellow,colors.gray)}

    r_ps.subscribe("ReactorSCRAM", r_scram.update)
    r_ps.subscribe("ManualReactorSCRAM", r_mscrm.update)
    r_ps.subscribe("AutoReactorSCRAM", r_ascrm.update)
    r_ps.subscribe("RCPTrip", r_rtrip.update)
    r_ps.subscribe("RCSFlowLow", r_cflow.update)
    r_ps.subscribe("CoolantLevelLow", r_clow.update)
    r_ps.subscribe("ReactorTempHigh", r_temp.update)
    r_ps.subscribe("ReactorHighDeltaT", r_rhdt.update)
    r_ps.subscribe("FuelInputRateLow", r_firl.update)
    r_ps.subscribe("WasteLineOcclusion", r_wloc.update)
    r_ps.subscribe("HighStartupRate", r_hsrt.update)

    -- RPS annunciator panel

    TextBox{parent=main,text="REACTOR PROTECTION SYSTEM",fg_bg=cpair(colors.black,colors.cyan),alignment=TEXT_ALIGN.CENTER,width=33,height=1,x=46,y=8}
    local rps = Rectangle{parent=main,border=border(1, colors.cyan, true),thin=true,width=33,height=12,x=46,y=9}
    local rps_annunc = Div{parent=rps,width=31,height=10,x=2,y=1}

    local rps_trp = IndicatorLight{parent=rps_annunc,label="RPS Trip",colors=cpair(colors.red,colors.gray),flash=true,period=period.BLINK_250_MS}
    local rps_dmg = IndicatorLight{parent=rps_annunc,label="Damage Critical",colors=cpair(colors.red,colors.gray),flash=true,period=period.BLINK_250_MS}
    local rps_exh = IndicatorLight{parent=rps_annunc,label="Excess Heated Coolant",colors=cpair(colors.yellow,colors.gray)}
    local rps_exw = IndicatorLight{parent=rps_annunc,label="Excess Waste",colors=cpair(colors.yellow,colors.gray)}
    local rps_tmp = IndicatorLight{parent=rps_annunc,label="Core Temp. High",colors=cpair(colors.red,colors.gray),flash=true,period=period.BLINK_250_MS}
    local rps_nof = IndicatorLight{parent=rps_annunc,label="No Fuel",colors=cpair(colors.yellow,colors.gray)}
    local rps_noc = IndicatorLight{parent=rps_annunc,label="Coolant Level Low Low",colors=cpair(colors.yellow,colors.gray)}
    local rps_flt = IndicatorLight{parent=rps_annunc,label="PPM Fault",colors=cpair(colors.yellow,colors.gray),flash=true,period=period.BLINK_500_MS}
    local rps_tmo = IndicatorLight{parent=rps_annunc,label="Timeout",colors=cpair(colors.yellow,colors.gray),flash=true,period=period.BLINK_500_MS}
    local rps_sfl = IndicatorLight{parent=rps_annunc,label="System Failure",colors=cpair(colors.orange,colors.gray),flash=true,period=period.BLINK_500_MS}

    r_ps.subscribe("rps_tripped", rps_trp.update)
    r_ps.subscribe("dmg_crit", rps_dmg.update)
    r_ps.subscribe("ex_hcool", rps_exh.update)
    r_ps.subscribe("ex_waste", rps_exw.update)
    r_ps.subscribe("high_temp", rps_tmp.update)
    r_ps.subscribe("no_fuel", rps_nof.update)
    r_ps.subscribe("no_cool", rps_noc.update)
    r_ps.subscribe("fault", rps_flt.update)
    r_ps.subscribe("timeout", rps_tmo.update)
    r_ps.subscribe("sys_fail", rps_sfl.update)

    -- cooling annunciator panel

    TextBox{parent=main,text="REACTOR COOLANT SYSTEM",fg_bg=cpair(colors.black,colors.blue),alignment=TEXT_ALIGN.CENTER,width=33,height=1,x=46,y=22}
    local rcs = Rectangle{parent=main,border=border(1, colors.blue, true),thin=true,width=33,height=24,x=46,y=23}
    local rcs_annunc = Div{parent=rcs,width=27,height=22,x=2,y=1}
    local rcs_tags = Div{parent=rcs,width=2,height=22,x=29,y=1}

    local c_cfm  = IndicatorLight{parent=rcs_annunc,label="Coolant Feed Mismatch",colors=cpair(colors.yellow,colors.gray)}
    local c_brm  = IndicatorLight{parent=rcs_annunc,label="Boil Rate Mismatch",colors=cpair(colors.yellow,colors.gray)}
    local c_sfm  = IndicatorLight{parent=rcs_annunc,label="Steam Feed Mismatch",colors=cpair(colors.yellow,colors.gray)}
    local c_mwrf = IndicatorLight{parent=rcs_annunc,label="Max Water Return Feed",colors=cpair(colors.yellow,colors.gray)}
    local c_tbnt = IndicatorLight{parent=rcs_annunc,label="Turbine Trip",colors=cpair(colors.red,colors.gray),flash=true,period=period.BLINK_250_MS}

    r_ps.subscribe("CoolantFeedMismatch", c_cfm.update)
    r_ps.subscribe("BoilRateMismatch", c_brm.update)
    r_ps.subscribe("SteamFeedMismatch", c_sfm.update)
    r_ps.subscribe("MaxWaterReturnFeed", c_mwrf.update)
    r_ps.subscribe("TurbineTrip", c_tbnt.update)

    rcs_annunc.line_break()

    -- boiler annunciator panel(s)

    if unit.num_boilers > 0 then
        TextBox{parent=rcs_tags,x=1,y=7,text="B1",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local b1_wll = IndicatorLight{parent=rcs_annunc,label="Water Level Low",colors=cpair(colors.red,colors.gray)}
        b_ps[1].subscribe("WasterLevelLow", b1_wll.update)

        TextBox{parent=rcs_tags,text="B1",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local b1_hr = IndicatorLight{parent=rcs_annunc,label="Heating Rate Low",colors=cpair(colors.yellow,colors.gray)}
        b_ps[1].subscribe("HeatingRateLow", b1_hr.update)
    end
    if unit.num_boilers > 1 then
        TextBox{parent=rcs_tags,text="B2",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local b2_wll = IndicatorLight{parent=rcs_annunc,label="Water Level Low",colors=cpair(colors.red,colors.gray)}
        b_ps[2].subscribe("WasterLevelLow", b2_wll.update)

        TextBox{parent=rcs_tags,text="B2",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local b2_hr = IndicatorLight{parent=rcs_annunc,label="Heating Rate Low",colors=cpair(colors.yellow,colors.gray)}
        b_ps[2].subscribe("HeatingRateLow", b2_hr.update)
    end

    -- turbine annunciator panels

    if unit.num_boilers == 0 then
        TextBox{parent=rcs_tags,y=7,text="T1",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
    else
        rcs_tags.line_break()
        rcs_annunc.line_break()
        TextBox{parent=rcs_tags,text="T1",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
    end

    local t1_sdo = TriIndicatorLight{parent=rcs_annunc,label="Steam Relief Valve Open",c1=colors.gray,c2=colors.yellow,c3=colors.red}
    t_ps[1].subscribe("SteamDumpOpen", function (val) t1_sdo.update(val + 1) end)

    TextBox{parent=rcs_tags,text="T1",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
    local t1_tos = IndicatorLight{parent=rcs_annunc,label="Turbine Over Speed",colors=cpair(colors.red,colors.gray)}
    t_ps[1].subscribe("TurbineOverSpeed", t1_tos.update)

    TextBox{parent=rcs_tags,text="T1",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
    local t1_trp = IndicatorLight{parent=rcs_annunc,label="Turbine Trip",colors=cpair(colors.red,colors.gray),flash=true,period=period.BLINK_250_MS}
    t_ps[1].subscribe("TurbineTrip", t1_trp.update)

    if unit.num_turbines > 1 then
        rcs_tags.line_break()
        rcs_annunc.line_break()

        TextBox{parent=rcs_tags,text="T2",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t2_sdo = TriIndicatorLight{parent=rcs_annunc,label="Steam Relief Valve Open",c1=colors.gray,c2=colors.yellow,c3=colors.red}
        t_ps[2].subscribe("SteamDumpOpen", function (val) t2_sdo.update(val + 1) end)

        TextBox{parent=rcs_tags,text="T2",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t2_tos = IndicatorLight{parent=rcs_annunc,label="Turbine Over Speed",colors=cpair(colors.red,colors.gray)}
        t_ps[2].subscribe("TurbineOverSpeed", t2_tos.update)

        TextBox{parent=rcs_tags,text="T2",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t2_trp = IndicatorLight{parent=rcs_annunc,label="Turbine Trip",colors=cpair(colors.red,colors.gray),flash=true,period=period.BLINK_250_MS}
        t_ps[2].subscribe("TurbineTrip", t2_trp.update)
    end

    if unit.num_turbines > 2 then
        rcs_tags.line_break()
        rcs_annunc.line_break()

        TextBox{parent=rcs_tags,text="T3",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t3_sdo = TriIndicatorLight{parent=rcs_annunc,label="Steam Relief Valve Open",c1=colors.gray,c2=colors.yellow,c3=colors.red}
        t_ps[3].subscribe("SteamDumpOpen", function (val) t3_sdo.update(val + 1) end)

        TextBox{parent=rcs_tags,text="T3",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t3_tos = IndicatorLight{parent=rcs_annunc,label="Turbine Over Speed",colors=cpair(colors.red,colors.gray)}
        t_ps[3].subscribe("TurbineOverSpeed", t3_tos.update)

        TextBox{parent=rcs_tags,text="T3",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t3_trp = IndicatorLight{parent=rcs_annunc,label="Turbine Trip",colors=cpair(colors.red,colors.gray),flash=true,period=period.BLINK_250_MS}
        t_ps[3].subscribe("TurbineTrip", t3_trp.update)
    end

    ----------------------
    -- reactor controls --
    ----------------------

    local burn_control = Div{parent=main,x=2,y=28,width=19,height=3,fg_bg=cpair(colors.gray,colors.white)}
    local burn_rate = SpinboxNumeric{parent=burn_control,x=2,y=1,whole_num_precision=4,fractional_precision=1,arrow_fg_bg=cpair(colors.gray,colors.white),fg_bg=cpair(colors.black,colors.white)}
    TextBox{parent=burn_control,x=9,y=2,text="mB/t"}

    local set_burn = function () unit.set_burn(burn_rate.get_value()) end
    PushButton{parent=burn_control,x=14,y=2,text="SET",min_width=5,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=cpair(colors.white,colors.gray),callback=set_burn}

    r_ps.subscribe("burn_rate", burn_rate.set_value)
    r_ps.subscribe("max_burn", burn_rate.set_max)

    local dis_colors = cpair(colors.white, colors.lightGray)

    local start = HazardButton{parent=main,x=22,y=28,text="START",accent=colors.lightBlue,dis_colors=dis_colors,callback=unit.start,fg_bg=hzd_fg_bg}
    local ack_a = HazardButton{parent=main,x=12,y=32,text="ACK \x13",accent=colors.orange,dis_colors=dis_colors,callback=unit.ack_alarms,fg_bg=hzd_fg_bg}
    local scram = HazardButton{parent=main,x=2,y=32,text="SCRAM",accent=colors.yellow,dis_colors=dis_colors,callback=unit.scram,fg_bg=hzd_fg_bg}
    local reset = HazardButton{parent=main,x=22,y=32,text="RESET",accent=colors.red,dis_colors=dis_colors,callback=unit.reset_rps,fg_bg=hzd_fg_bg}

    unit.start_ack = start.on_response
    unit.scram_ack = scram.on_response
    unit.reset_rps_ack = reset.on_response
    unit.ack_alarms_ack = ack_a.on_response

    local function start_button_en_check()
        if (unit.reactor_data ~= nil) and (unit.reactor_data.mek_status ~= nil) then
            local can_start = (not unit.reactor_data.mek_status.status) and (not unit.reactor_data.rps_tripped)
            if can_start then start.enable() else start.disable() end
        end
    end

    r_ps.subscribe("status", start_button_en_check)
    r_ps.subscribe("rps_tripped", start_button_en_check)
    r_ps.subscribe("rps_tripped", function (active) if active then reset.enable() else reset.disable() end end)

    TextBox{parent=main,text="WASTE PROCESSING",fg_bg=cpair(colors.black,colors.brown),alignment=TEXT_ALIGN.CENTER,width=33,height=1,x=46,y=48}
    local waste_proc = Rectangle{parent=main,border=border(1, colors.brown, true),thin=true,width=33,height=3,x=46,y=49}
    local waste_div = Div{parent=waste_proc,x=2,y=1,width=31,height=1}

    local waste_mode = MultiButton{parent=waste_div,x=1,y=1,options=waste_opts,callback=unit.set_waste,min_width=6}

    r_ps.subscribe("U_WasteMode", waste_mode.set_value)

    ----------------------
    -- alarm management --
    ----------------------

    local alarm_panel = Div{parent=main,x=2,y=36,width=29,height=16,fg_bg=cpair(colors.black,colors.white)}

    local a_brc = AlarmLight{parent=alarm_panel,x=6,y=2,label="Containment Breach",c1=colors.gray,c2=colors.red,c3=colors.green,flash=true,period=period.BLINK_250_MS}
    local a_rad = AlarmLight{parent=alarm_panel,x=6,label="Containment Radiation",c1=colors.gray,c2=colors.red,c3=colors.green,flash=true,period=period.BLINK_250_MS}
    local a_dmg = AlarmLight{parent=alarm_panel,x=6,label="Critical Damage",c1=colors.gray,c2=colors.red,c3=colors.green,flash=true,period=period.BLINK_250_MS}
    alarm_panel.line_break()
    local a_rcl = AlarmLight{parent=alarm_panel,x=6,label="Reactor Lost",c1=colors.gray,c2=colors.red,c3=colors.green,flash=true,period=period.BLINK_250_MS}
    local a_rcd = AlarmLight{parent=alarm_panel,x=6,label="Reactor Damage",c1=colors.gray,c2=colors.red,c3=colors.green,flash=true,period=period.BLINK_250_MS}
    local a_rot = AlarmLight{parent=alarm_panel,x=6,label="Reactor Over Temp",c1=colors.gray,c2=colors.red,c3=colors.green,flash=true,period=period.BLINK_250_MS}
    local a_rht = AlarmLight{parent=alarm_panel,x=6,label="Reactor High Temp",c1=colors.gray,c2=colors.yellow,c3=colors.green,flash=true,period=period.BLINK_500_MS}
    local a_rwl = AlarmLight{parent=alarm_panel,x=6,label="Reactor Waste Leak",c1=colors.gray,c2=colors.red,c3=colors.green,flash=true,period=period.BLINK_250_MS}
    local a_rwh = AlarmLight{parent=alarm_panel,x=6,label="Reactor Waste High",c1=colors.gray,c2=colors.yellow,c3=colors.green,flash=true,period=period.BLINK_500_MS}
    alarm_panel.line_break()
    local a_rps = AlarmLight{parent=alarm_panel,x=6,label="RPS Transient",c1=colors.gray,c2=colors.yellow,c3=colors.green,flash=true,period=period.BLINK_500_MS}
    local a_clt = AlarmLight{parent=alarm_panel,x=6,label="RCS Transient",c1=colors.gray,c2=colors.yellow,c3=colors.green,flash=true,period=period.BLINK_500_MS}
    local a_tbt = AlarmLight{parent=alarm_panel,x=6,label="Turbine Trip",c1=colors.gray,c2=colors.red,c3=colors.green,flash=true,period=period.BLINK_250_MS}

    r_ps.subscribe("Alarm_1", a_brc.update)
    r_ps.subscribe("Alarm_2", a_rad.update)
    r_ps.subscribe("Alarm_4", a_dmg.update)

    r_ps.subscribe("Alarm_3", a_rcl.update)
    r_ps.subscribe("Alarm_5", a_rcd.update)
    r_ps.subscribe("Alarm_6", a_rot.update)
    r_ps.subscribe("Alarm_7", a_rht.update)
    r_ps.subscribe("Alarm_8", a_rwl.update)
    r_ps.subscribe("Alarm_9", a_rwh.update)

    r_ps.subscribe("Alarm_10", a_rps.update)
    r_ps.subscribe("Alarm_11", a_clt.update)
    r_ps.subscribe("Alarm_12", a_tbt.update)

    -- ack's and resets

    local c = unit.alarm_callbacks
    local ack_fg_bg = cpair(colors.black, colors.orange)
    local rst_fg_bg = cpair(colors.black, colors.lime)
    local active_fg_bg = cpair(colors.white, colors.gray)

    PushButton{parent=alarm_panel,x=2,y=2,text="\x13",min_width=1,callback=c.c_breach.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=2,text="R",min_width=1,callback=c.c_breach.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=3,text="\x13",min_width=1,callback=c.radiation.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=3,text="R",min_width=1,callback=c.radiation.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=4,text="\x13",min_width=1,callback=c.dmg_crit.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=4,text="R",min_width=1,callback=c.dmg_crit.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}

    PushButton{parent=alarm_panel,x=2,y=6,text="\x13",min_width=1,callback=c.r_lost.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=6,text="R",min_width=1,callback=c.r_lost.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=7,text="\x13",min_width=1,callback=c.damage.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=7,text="R",min_width=1,callback=c.damage.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=8,text="\x13",min_width=1,callback=c.over_temp.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=8,text="R",min_width=1,callback=c.over_temp.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=9,text="\x13",min_width=1,callback=c.high_temp.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=9,text="R",min_width=1,callback=c.high_temp.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=10,text="\x13",min_width=1,callback=c.waste_leak.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=10,text="R",min_width=1,callback=c.waste_leak.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=11,text="\x13",min_width=1,callback=c.waste_high.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=11,text="R",min_width=1,callback=c.waste_high.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}

    PushButton{parent=alarm_panel,x=2,y=13,text="\x13",min_width=1,callback=c.rps_trans.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=13,text="R",min_width=1,callback=c.rps_trans.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=14,text="\x13",min_width=1,callback=c.rcs_trans.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=14,text="R",min_width=1,callback=c.rcs_trans.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=15,text="\x13",min_width=1,callback=c.t_trip.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=15,text="R",min_width=1,callback=c.t_trip.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}

    -- color tags

    TextBox{parent=alarm_panel,x=5,y=13,text="\x95",width=1,height=1,fg_bg=cpair(colors.white, colors.cyan)}
    TextBox{parent=alarm_panel,x=5,text="\x95",width=1,height=1,fg_bg=cpair(colors.white, colors.blue)}
    TextBox{parent=alarm_panel,x=5,text="\x95",width=1,height=1,fg_bg=cpair(colors.white, colors.blue)}

    return main
end

return init
