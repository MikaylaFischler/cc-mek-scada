--
-- Reactor Unit SCADA Coordinator GUI
--

local types             = require("scada-common.types")
local util              = require("scada-common.util")

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
local RadIndicator      = require("graphics.elements.indicators.rad")
local TriIndicatorLight = require("graphics.elements.indicators.trilight")
local VerticalBar       = require("graphics.elements.indicators.vbar")

local HazardButton      = require("graphics.elements.controls.hazard_button")
local MultiButton       = require("graphics.elements.controls.multi_button")
local PushButton        = require("graphics.elements.controls.push_button")
local RadioButton       = require("graphics.elements.controls.radio_button")
local SpinboxNumeric    = require("graphics.elements.controls.spinbox_numeric")

local ALIGN = core.ALIGN

local cpair = core.cpair
local border = core.border

local bw_fg_bg = style.bw_fg_bg
local gry_wht = style.gray_white

local period = core.flasher.PERIOD

-- create a unit view
---@param parent graphics_element parent
---@param id integer
local function init(parent, id)
    local s_hi_box = style.theme.highlight_box
    local s_hi_bright = style.theme.highlight_box_bright
    local s_field = style.theme.field_box

    local hc_text = style.hc_text
    local lu_cpair = style.lu_colors
    local hzd_fg_bg = style.hzd_fg_bg
    local dis_colors = style.dis_colors
    local arrow_fg_bg = cpair(style.theme.label, s_hi_box.bkg)

    local ind_bkg = style.ind_bkg
    local ind_grn = style.ind_grn
    local ind_yel = style.ind_yel
    local ind_red = style.ind_red
    local ind_wht = style.ind_wht

    local db = iocontrol.get_db()
    local unit = db.units[id]   ---@type ioctl_unit
    local f_ps = db.facility.ps

    local main = Div{parent=parent,x=1,y=1}

    if unit == nil then return main end

    local u_ps = unit.unit_ps
    local b_ps = unit.boiler_ps_tbl
    local t_ps = unit.turbine_ps_tbl

    TextBox{parent=main,text="Reactor Unit #" .. id,alignment=ALIGN.CENTER,height=1,fg_bg=style.theme.header}

    -----------------------------
    -- main stats and core map --
    -----------------------------

    local core_map = CoreMap{parent=main,x=2,y=3,reactor_l=18,reactor_w=18}
    core_map.register(u_ps, "temp", core_map.update)
    core_map.register(u_ps, "size", function (s) core_map.resize(s[1], s[2]) end)

    TextBox{parent=main,x=12,y=22,text="Heating Rate",height=1,width=12,fg_bg=style.label}
    local heating_r = DataIndicator{parent=main,x=12,label="",format="%14.0f",value=0,unit="mB/t",commas=true,lu_colors=lu_cpair,width=19,fg_bg=s_field}
    heating_r.register(u_ps, "heating_rate", heating_r.update)

    TextBox{parent=main,x=12,y=25,text="Commanded Burn Rate",height=1,width=19,fg_bg=style.label}
    local burn_r = DataIndicator{parent=main,x=12,label="",format="%14.2f",value=0,unit="mB/t",lu_colors=lu_cpair,width=19,fg_bg=s_field}
    burn_r.register(u_ps, "burn_rate", burn_r.update)

    TextBox{parent=main,text="F",x=2,y=22,width=1,height=1,fg_bg=style.label}
    TextBox{parent=main,text="C",x=4,y=22,width=1,height=1,fg_bg=style.label}
    TextBox{parent=main,text="\x1a",x=6,y=24,width=1,height=1,fg_bg=style.label}
    TextBox{parent=main,text="\x1a",x=6,y=25,width=1,height=1,fg_bg=style.label}
    TextBox{parent=main,text="H",x=8,y=22,width=1,height=1,fg_bg=style.label}
    TextBox{parent=main,text="W",x=10,y=22,width=1,height=1,fg_bg=style.label}

    local fuel  = VerticalBar{parent=main,x=2,y=23,fg_bg=cpair(style.theme.fuel_color,colors.gray),height=4,width=1}
    local ccool = VerticalBar{parent=main,x=4,y=23,fg_bg=cpair(colors.blue,colors.gray),height=4,width=1}
    local hcool = VerticalBar{parent=main,x=8,y=23,fg_bg=cpair(colors.white,colors.gray),height=4,width=1}
    local waste = VerticalBar{parent=main,x=10,y=23,fg_bg=cpair(colors.brown,colors.gray),height=4,width=1}

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

    TextBox{parent=main,x=32,y=22,text="Core Temp",height=1,width=9,fg_bg=style.label}
    local fmt = util.trinary(string.len(db.temp_label) == 2, "%10.2f", "%11.2f")
    local core_temp = DataIndicator{parent=main,x=32,label="",format=fmt,value=0,commas=true,unit=db.temp_label,lu_colors=lu_cpair,width=13,fg_bg=s_field}
    core_temp.register(u_ps, "temp", function (t) core_temp.update(db.temp_convert(t)) end)

    TextBox{parent=main,x=32,y=25,text="Burn Rate",height=1,width=9,fg_bg=style.label}
    local act_burn_r = DataIndicator{parent=main,x=32,label="",format="%8.2f",value=0,unit="mB/t",lu_colors=lu_cpair,width=13,fg_bg=s_field}
    act_burn_r.register(u_ps, "act_burn_rate", act_burn_r.update)

    TextBox{parent=main,x=32,y=28,text="Damage",height=1,width=6,fg_bg=style.label}
    local damage_p = DataIndicator{parent=main,x=32,label="",format="%11.0f",value=0,unit="%",lu_colors=lu_cpair,width=13,fg_bg=s_field}
    damage_p.register(u_ps, "damage", damage_p.update)

    TextBox{parent=main,x=32,y=31,text="Radiation",height=1,width=21,fg_bg=style.label}
    local radiation = RadIndicator{parent=main,x=32,label="",format="%9.3f",lu_colors=lu_cpair,width=13,fg_bg=s_field}
    radiation.register(u_ps, "radiation", radiation.update)

    -------------------
    -- system status --
    -------------------

    local u_stat = Rectangle{parent=main,border=border(1,colors.gray,true),thin=true,width=33,height=4,x=46,y=3,fg_bg=bw_fg_bg}
    local stat_line_1 = TextBox{parent=u_stat,x=1,y=1,text="UNKNOWN",width=33,height=1,alignment=ALIGN.CENTER,fg_bg=bw_fg_bg}
    local stat_line_2 = TextBox{parent=u_stat,x=1,y=2,text="awaiting data...",width=33,height=1,alignment=ALIGN.CENTER,fg_bg=gry_wht}

    stat_line_1.register(u_ps, "U_StatusLine1", stat_line_1.set_value)
    stat_line_2.register(u_ps, "U_StatusLine2", stat_line_2.set_value)

    -----------------
    -- annunciator --
    -----------------

    -- annunciator colors (generally) per IAEA-TECDOC-812 recommendations

    local annunciator = Div{parent=main,width=23,height=18,x=22,y=3}

    -- connectivity
    local plc_online = IndicatorLight{parent=annunciator,label="PLC Online",colors=cpair(ind_grn.fgd,ind_red.fgd)}
    local plc_hbeat  = IndicatorLight{parent=annunciator,label="PLC Heartbeat",colors=ind_wht}
    local rad_mon    = TriIndicatorLight{parent=annunciator,label="Radiation Monitor",c1=ind_bkg,c2=ind_yel.fgd,c3=ind_grn.fgd}

    plc_online.register(u_ps, "PLCOnline", plc_online.update)
    plc_hbeat.register(u_ps, "PLCHeartbeat", plc_hbeat.update)
    rad_mon.register(u_ps, "RadiationMonitor", rad_mon.update)

    annunciator.line_break()

    -- operating state
    local r_active = IndicatorLight{parent=annunciator,label="Active",colors=ind_grn}
    local r_auto   = IndicatorLight{parent=annunciator,label="Automatic Control",colors=ind_wht}

    r_active.register(u_ps, "status", r_active.update)
    r_auto.register(u_ps, "AutoControl", r_auto.update)

    -- main unit transient/warning annunciator panel
    local r_scram = IndicatorLight{parent=annunciator,label="Reactor SCRAM",colors=ind_red}
    local r_mscrm = IndicatorLight{parent=annunciator,label="Manual Reactor SCRAM",colors=ind_red}
    local r_ascrm = IndicatorLight{parent=annunciator,label="Auto Reactor SCRAM",colors=ind_red}
    local rad_wrn = IndicatorLight{parent=annunciator,label="Radiation Warning",colors=ind_yel}
    local r_rtrip = IndicatorLight{parent=annunciator,label="RCP Trip",colors=ind_red}
    local r_cflow = IndicatorLight{parent=annunciator,label="RCS Flow Low",colors=ind_yel}
    local r_clow  = IndicatorLight{parent=annunciator,label="Coolant Level Low",colors=ind_yel}
    local r_temp  = IndicatorLight{parent=annunciator,label="Reactor Temp. High",colors=ind_red}
    local r_rhdt  = IndicatorLight{parent=annunciator,label="Reactor High Delta T",colors=ind_yel}
    local r_firl  = IndicatorLight{parent=annunciator,label="Fuel Input Rate Low",colors=ind_yel}
    local r_wloc  = IndicatorLight{parent=annunciator,label="Waste Line Occlusion",colors=ind_yel}
    local r_hsrt  = IndicatorLight{parent=annunciator,label="Startup Rate High",colors=ind_yel}

    r_scram.register(u_ps, "ReactorSCRAM", r_scram.update)
    r_mscrm.register(u_ps, "ManualReactorSCRAM", r_mscrm.update)
    r_ascrm.register(u_ps, "AutoReactorSCRAM", r_ascrm.update)
    rad_wrn.register(u_ps, "RadiationWarning", rad_wrn.update)
    r_rtrip.register(u_ps, "RCPTrip", r_rtrip.update)
    r_cflow.register(u_ps, "RCSFlowLow", r_cflow.update)
    r_clow.register(u_ps, "CoolantLevelLow", r_clow.update)
    r_temp.register(u_ps, "ReactorTempHigh", r_temp.update)
    r_rhdt.register(u_ps, "ReactorHighDeltaT", r_rhdt.update)
    r_firl.register(u_ps, "FuelInputRateLow", r_firl.update)
    r_wloc.register(u_ps, "WasteLineOcclusion", r_wloc.update)
    r_hsrt.register(u_ps, "HighStartupRate", r_hsrt.update)

    -- RPS annunciator panel

    TextBox{parent=main,text="REACTOR PROTECTION SYSTEM",fg_bg=cpair(colors.black,colors.cyan),alignment=ALIGN.CENTER,width=33,height=1,x=46,y=8}
    local rps = Rectangle{parent=main,border=border(1,colors.cyan,true),thin=true,width=33,height=12,x=46,y=9}
    local rps_annunc = Div{parent=rps,width=31,height=10,x=2,y=1}

    local rps_trp = IndicatorLight{parent=rps_annunc,label="RPS Trip",colors=ind_red,flash=true,period=period.BLINK_250_MS}
    local rps_dmg = IndicatorLight{parent=rps_annunc,label="Damage Level High",colors=ind_red,flash=true,period=period.BLINK_250_MS}
    local rps_exh = IndicatorLight{parent=rps_annunc,label="Excess Heated Coolant",colors=ind_yel}
    local rps_exw = IndicatorLight{parent=rps_annunc,label="Excess Waste",colors=ind_yel}
    local rps_tmp = IndicatorLight{parent=rps_annunc,label="Core Temperature High",colors=ind_red,flash=true,period=period.BLINK_250_MS}
    local rps_nof = IndicatorLight{parent=rps_annunc,label="No Fuel",colors=ind_yel}
    local rps_loc = IndicatorLight{parent=rps_annunc,label="Coolant Level Low Low",colors=ind_yel}
    local rps_flt = IndicatorLight{parent=rps_annunc,label="PPM Fault",colors=ind_yel,flash=true,period=period.BLINK_500_MS}
    local rps_tmo = IndicatorLight{parent=rps_annunc,label="Connection Timeout",colors=ind_yel,flash=true,period=period.BLINK_500_MS}
    local rps_sfl = IndicatorLight{parent=rps_annunc,label="System Failure",colors=ind_red,flash=true,period=period.BLINK_500_MS}

    rps_trp.register(u_ps, "rps_tripped", rps_trp.update)
    rps_dmg.register(u_ps, "high_dmg", rps_dmg.update)
    rps_exh.register(u_ps, "ex_hcool", rps_exh.update)
    rps_exw.register(u_ps, "ex_waste", rps_exw.update)
    rps_tmp.register(u_ps, "high_temp", rps_tmp.update)
    rps_nof.register(u_ps, "no_fuel", rps_nof.update)
    rps_loc.register(u_ps, "low_cool", rps_loc.update)
    rps_flt.register(u_ps, "fault", rps_flt.update)
    rps_tmo.register(u_ps, "timeout", rps_tmo.update)
    rps_sfl.register(u_ps, "sys_fail", rps_sfl.update)

    -- cooling annunciator panel

    TextBox{parent=main,text="REACTOR COOLANT SYSTEM",fg_bg=cpair(colors.black,colors.blue),alignment=ALIGN.CENTER,width=33,height=1,x=46,y=22}
    local rcs = Rectangle{parent=main,border=border(1,colors.blue,true),thin=true,width=33,height=24,x=46,y=23}
    local rcs_annunc = Div{parent=rcs,width=27,height=22,x=3,y=1}
    local rcs_tags = Div{parent=rcs,width=2,height=16,x=1,y=7}

    local c_flt  = IndicatorLight{parent=rcs_annunc,label="RCS Hardware Fault",colors=ind_yel}
    local c_emg  = TriIndicatorLight{parent=rcs_annunc,label="Emergency Coolant",c1=ind_bkg,c2=ind_wht.fgd,c3=ind_grn.fgd}
    local c_cfm  = IndicatorLight{parent=rcs_annunc,label="Coolant Feed Mismatch",colors=ind_yel}
    local c_brm  = IndicatorLight{parent=rcs_annunc,label="Boil Rate Mismatch",colors=ind_yel}
    local c_sfm  = IndicatorLight{parent=rcs_annunc,label="Steam Feed Mismatch",colors=ind_yel}
    local c_mwrf = IndicatorLight{parent=rcs_annunc,label="Max Water Return Feed",colors=ind_yel}

    c_flt.register(u_ps, "RCSFault", c_flt.update)
    c_emg.register(u_ps, "EmergencyCoolant", c_emg.update)
    c_cfm.register(u_ps, "CoolantFeedMismatch", c_cfm.update)
    c_brm.register(u_ps, "BoilRateMismatch", c_brm.update)
    c_sfm.register(u_ps, "SteamFeedMismatch", c_sfm.update)
    c_mwrf.register(u_ps, "MaxWaterReturnFeed", c_mwrf.update)

    local available_space = 16 - (unit.num_boilers * 2 + unit.num_turbines * 4)

    local function _add_space()
        -- if we have some extra space, add padding
        rcs_tags.line_break()
        rcs_annunc.line_break()
    end

    -- boiler annunciator panel(s)

    if unit.num_boilers > 0 then
        if available_space > 0 then _add_space() end

        TextBox{parent=rcs_tags,x=1,text="B1",width=2,height=1,fg_bg=hc_text}
        local b1_wll = IndicatorLight{parent=rcs_annunc,label="Water Level Low",colors=ind_red}
        b1_wll.register(b_ps[1], "WaterLevelLow", b1_wll.update)

        TextBox{parent=rcs_tags,text="B1",width=2,height=1,fg_bg=hc_text}
        local b1_hr = IndicatorLight{parent=rcs_annunc,label="Heating Rate Low",colors=ind_yel}
        b1_hr.register(b_ps[1], "HeatingRateLow", b1_hr.update)
    end
    if unit.num_boilers > 1 then
        -- note, can't (shouldn't for sure...) have 0 turbines
        if (available_space > 2 and unit.num_turbines == 1) or
           (available_space > 3 and unit.num_turbines == 2) or
           (available_space > 4) then
            _add_space()
        end

        TextBox{parent=rcs_tags,text="B2",width=2,height=1,fg_bg=hc_text}
        local b2_wll = IndicatorLight{parent=rcs_annunc,label="Water Level Low",colors=ind_red}
        b2_wll.register(b_ps[2], "WaterLevelLow", b2_wll.update)

        TextBox{parent=rcs_tags,text="B2",width=2,height=1,fg_bg=hc_text}
        local b2_hr = IndicatorLight{parent=rcs_annunc,label="Heating Rate Low",colors=ind_yel}
        b2_hr.register(b_ps[2], "HeatingRateLow", b2_hr.update)
    end

    -- turbine annunciator panels

    if available_space > 1 then _add_space() end

    TextBox{parent=rcs_tags,text="T1",width=2,height=1,fg_bg=hc_text}
    local t1_sdo = TriIndicatorLight{parent=rcs_annunc,label="Steam Relief Valve Open",c1=ind_bkg,c2=ind_yel.fgd,c3=ind_red.fgd}
    t1_sdo.register(t_ps[1], "SteamDumpOpen", t1_sdo.update)

    TextBox{parent=rcs_tags,text="T1",width=2,height=1,fg_bg=hc_text}
    local t1_tos = IndicatorLight{parent=rcs_annunc,label="Turbine Over Speed",colors=ind_red}
    t1_tos.register(t_ps[1], "TurbineOverSpeed", t1_tos.update)

    TextBox{parent=rcs_tags,text="T1",width=2,height=1,fg_bg=hc_text}
    local t1_gtrp = IndicatorLight{parent=rcs_annunc,label="Generator Trip",colors=ind_yel,flash=true,period=period.BLINK_250_MS}
    t1_gtrp.register(t_ps[1], "GeneratorTrip", t1_gtrp.update)

    TextBox{parent=rcs_tags,text="T1",width=2,height=1,fg_bg=hc_text}
    local t1_trp = IndicatorLight{parent=rcs_annunc,label="Turbine Trip",colors=ind_red,flash=true,period=period.BLINK_250_MS}
    t1_trp.register(t_ps[1], "TurbineTrip", t1_trp.update)

    if unit.num_turbines > 1 then
        if (available_space > 2 and unit.num_turbines == 2) or available_space > 3 then
            _add_space()
        end

        TextBox{parent=rcs_tags,text="T2",width=2,height=1,fg_bg=hc_text}
        local t2_sdo = TriIndicatorLight{parent=rcs_annunc,label="Steam Relief Valve Open",c1=ind_bkg,c2=ind_yel.fgd,c3=ind_red.fgd}
        t2_sdo.register(t_ps[2], "SteamDumpOpen", t2_sdo.update)

        TextBox{parent=rcs_tags,text="T2",width=2,height=1,fg_bg=hc_text}
        local t2_tos = IndicatorLight{parent=rcs_annunc,label="Turbine Over Speed",colors=ind_red}
        t2_tos.register(t_ps[2], "TurbineOverSpeed", t2_tos.update)

        TextBox{parent=rcs_tags,text="T2",width=2,height=1,fg_bg=hc_text}
        local t2_gtrp = IndicatorLight{parent=rcs_annunc,label="Generator Trip",colors=ind_yel,flash=true,period=period.BLINK_250_MS}
        t2_gtrp.register(t_ps[2], "GeneratorTrip", t2_gtrp.update)

        TextBox{parent=rcs_tags,text="T2",width=2,height=1,fg_bg=hc_text}
        local t2_trp = IndicatorLight{parent=rcs_annunc,label="Turbine Trip",colors=ind_red,flash=true,period=period.BLINK_250_MS}
        t2_trp.register(t_ps[2], "TurbineTrip", t2_trp.update)
    end

    if unit.num_turbines > 2 then
        if available_space > 3 then _add_space() end

        TextBox{parent=rcs_tags,text="T3",width=2,height=1,fg_bg=hc_text}
        local t3_sdo = TriIndicatorLight{parent=rcs_annunc,label="Steam Relief Valve Open",c1=ind_bkg,c2=ind_yel.fgd,c3=ind_red.fgd}
        t3_sdo.register(t_ps[3], "SteamDumpOpen", t3_sdo.update)

        TextBox{parent=rcs_tags,text="T3",width=2,height=1,fg_bg=hc_text}
        local t3_tos = IndicatorLight{parent=rcs_annunc,label="Turbine Over Speed",colors=ind_red}
        t3_tos.register(t_ps[3], "TurbineOverSpeed", t3_tos.update)

        TextBox{parent=rcs_tags,text="T3",width=2,height=1,fg_bg=hc_text}
        local t3_gtrp = IndicatorLight{parent=rcs_annunc,label="Generator Trip",colors=ind_yel,flash=true,period=period.BLINK_250_MS}
        t3_gtrp.register(t_ps[3], "GeneratorTrip", t3_gtrp.update)

        TextBox{parent=rcs_tags,text="T3",width=2,height=1,fg_bg=hc_text}
        local t3_trp = IndicatorLight{parent=rcs_annunc,label="Turbine Trip",colors=ind_red,flash=true,period=period.BLINK_250_MS}
        t3_trp.register(t_ps[3], "TurbineTrip", t3_trp.update)
    end

    util.nop()

    ----------------------
    -- reactor controls --
    ----------------------

    local burn_control = Div{parent=main,x=12,y=28,width=19,height=3,fg_bg=s_hi_box}
    local burn_rate = SpinboxNumeric{parent=burn_control,x=2,y=1,whole_num_precision=4,fractional_precision=1,min=0.1,arrow_fg_bg=arrow_fg_bg,arrow_disable=style.theme.disabled}
    TextBox{parent=burn_control,x=9,y=2,text="mB/t",fg_bg=style.theme.label_fg}

    local set_burn = function () unit.set_burn(burn_rate.get_value()) end
    local set_burn_btn = PushButton{parent=burn_control,x=14,y=2,text="SET",min_width=5,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=style.wh_gray,dis_fg_bg=dis_colors,callback=set_burn}

    burn_rate.register(u_ps, "burn_rate", burn_rate.set_value)
    burn_rate.register(u_ps, "max_burn", burn_rate.set_max)

    local start = HazardButton{parent=main,x=2,y=28,text="START",accent=colors.lightBlue,dis_colors=dis_colors,callback=unit.start,fg_bg=hzd_fg_bg}
    local ack_a = HazardButton{parent=main,x=12,y=32,text="ACK \x13",accent=colors.orange,dis_colors=dis_colors,callback=unit.ack_alarms,fg_bg=hzd_fg_bg}
    local scram = HazardButton{parent=main,x=2,y=32,text="SCRAM",accent=colors.yellow,dis_colors=dis_colors,callback=unit.scram,fg_bg=hzd_fg_bg}
    local reset = HazardButton{parent=main,x=22,y=32,text="RESET",accent=colors.red,dis_colors=dis_colors,callback=unit.reset_rps,fg_bg=hzd_fg_bg}

    unit.start_ack = start.on_response
    unit.scram_ack = scram.on_response
    unit.reset_rps_ack = reset.on_response
    unit.ack_alarms_ack = ack_a.on_response

    local function start_button_en_check()
        if (unit.reactor_data ~= nil) and (unit.reactor_data.mek_status ~= nil) then
            local can_start = (not unit.reactor_data.mek_status.status) and
                                (not unit.reactor_data.rps_tripped) and
                                (unit.a_group == 0)
            if can_start then start.enable() else start.disable() end
        end
    end

    start.register(u_ps, "status", start_button_en_check)
    start.register(u_ps, "rps_tripped", start_button_en_check)
    start.register(u_ps, "auto_group_id", start_button_en_check)
    start.register(u_ps, "AutoControl", start_button_en_check)

    reset.register(u_ps, "rps_tripped", function (active) if active then reset.enable() else reset.disable() end end)

    TextBox{parent=main,text="WASTE PROCESSING",fg_bg=cpair(colors.black,colors.brown),alignment=ALIGN.CENTER,width=33,height=1,x=46,y=48}
    local waste_proc = Rectangle{parent=main,border=border(1,colors.brown,true),thin=true,width=33,height=3,x=46,y=49}
    local waste_div = Div{parent=waste_proc,x=2,y=1,width=31,height=1}

    local waste_mode = MultiButton{parent=waste_div,x=1,y=1,options=style.waste.unit_opts,callback=unit.set_waste,min_width=6}

    waste_mode.register(u_ps, "U_WasteMode", waste_mode.set_value)

    ----------------------
    -- alarm management --
    ----------------------

    local alarm_panel = Div{parent=main,x=2,y=36,width=29,height=16,fg_bg=s_hi_bright}

    local a_brc = AlarmLight{parent=alarm_panel,x=6,y=2,label="Containment Breach",c1=ind_bkg,c2=ind_red.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_250_MS}
    local a_rad = AlarmLight{parent=alarm_panel,x=6,label="Containment Radiation",c1=ind_bkg,c2=ind_red.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_250_MS}
    local a_dmg = AlarmLight{parent=alarm_panel,x=6,label="Critical Damage",c1=ind_bkg,c2=ind_red.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_250_MS}
    alarm_panel.line_break()
    local a_rcl = AlarmLight{parent=alarm_panel,x=6,label="Reactor Lost",c1=ind_bkg,c2=ind_red.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_250_MS}
    local a_rcd = AlarmLight{parent=alarm_panel,x=6,label="Reactor Damage",c1=ind_bkg,c2=ind_red.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_250_MS}
    local a_rot = AlarmLight{parent=alarm_panel,x=6,label="Reactor Over Temp",c1=ind_bkg,c2=ind_red.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_250_MS}
    local a_rht = AlarmLight{parent=alarm_panel,x=6,label="Reactor High Temp",c1=ind_bkg,c2=ind_yel.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_500_MS}
    local a_rwl = AlarmLight{parent=alarm_panel,x=6,label="Reactor Waste Leak",c1=ind_bkg,c2=ind_red.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_250_MS}
    local a_rwh = AlarmLight{parent=alarm_panel,x=6,label="Reactor Waste High",c1=ind_bkg,c2=ind_yel.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_500_MS}
    alarm_panel.line_break()
    local a_rps = AlarmLight{parent=alarm_panel,x=6,label="RPS Transient",c1=ind_bkg,c2=ind_yel.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_500_MS}
    local a_clt = AlarmLight{parent=alarm_panel,x=6,label="RCS Transient",c1=ind_bkg,c2=ind_yel.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_500_MS}
    local a_tbt = AlarmLight{parent=alarm_panel,x=6,label="Turbine Trip",c1=ind_bkg,c2=ind_red.fgd,c3=ind_grn.fgd,flash=true,period=period.BLINK_250_MS}

    a_brc.register(u_ps, "Alarm_1", a_brc.update)
    a_rad.register(u_ps, "Alarm_2", a_rad.update)
    a_dmg.register(u_ps, "Alarm_4", a_dmg.update)

    a_rcl.register(u_ps, "Alarm_3", a_rcl.update)
    a_rcd.register(u_ps, "Alarm_5", a_rcd.update)
    a_rot.register(u_ps, "Alarm_6", a_rot.update)
    a_rht.register(u_ps, "Alarm_7", a_rht.update)
    a_rwl.register(u_ps, "Alarm_8", a_rwl.update)
    a_rwh.register(u_ps, "Alarm_9", a_rwh.update)

    a_rps.register(u_ps, "Alarm_10", a_rps.update)
    a_clt.register(u_ps, "Alarm_11", a_clt.update)
    a_tbt.register(u_ps, "Alarm_12", a_tbt.update)

    -- ack's and resets

    local c = unit.alarm_callbacks
    local ack_fg_bg = cpair(colors.black, colors.orange)
    local rst_fg_bg = cpair(colors.black, colors.lime)
    local active_fg_bg = cpair(colors.white, colors.gray)

    PushButton{parent=alarm_panel,x=2,y=2,text="\x13",callback=c.c_breach.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=2,text="R",callback=c.c_breach.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=3,text="\x13",callback=c.radiation.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=3,text="R",callback=c.radiation.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=4,text="\x13",callback=c.dmg_crit.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=4,text="R",callback=c.dmg_crit.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}

    PushButton{parent=alarm_panel,x=2,y=6,text="\x13",callback=c.r_lost.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=6,text="R",callback=c.r_lost.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=7,text="\x13",callback=c.damage.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=7,text="R",callback=c.damage.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=8,text="\x13",callback=c.over_temp.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=8,text="R",callback=c.over_temp.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=9,text="\x13",callback=c.high_temp.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=9,text="R",callback=c.high_temp.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=10,text="\x13",callback=c.waste_leak.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=10,text="R",callback=c.waste_leak.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=11,text="\x13",callback=c.waste_high.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=11,text="R",callback=c.waste_high.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}

    PushButton{parent=alarm_panel,x=2,y=13,text="\x13",callback=c.rps_trans.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=13,text="R",callback=c.rps_trans.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=14,text="\x13",callback=c.rcs_trans.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=14,text="R",callback=c.rcs_trans.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=2,y=15,text="\x13",callback=c.t_trip.ack,fg_bg=ack_fg_bg,active_fg_bg=active_fg_bg}
    PushButton{parent=alarm_panel,x=4,y=15,text="R",callback=c.t_trip.reset,fg_bg=rst_fg_bg,active_fg_bg=active_fg_bg}

    -- color tags

    TextBox{parent=alarm_panel,x=5,y=13,text="\x95",width=1,height=1,fg_bg=cpair(s_hi_bright.bkg,colors.cyan)}
    TextBox{parent=alarm_panel,x=5,text="\x95",width=1,height=1,fg_bg=cpair(s_hi_bright.bkg,colors.blue)}
    TextBox{parent=alarm_panel,x=5,text="\x95",width=1,height=1,fg_bg=cpair(s_hi_bright.bkg,colors.blue)}

    --------------------------------
    -- automatic control settings --
    --------------------------------

    TextBox{parent=main,text="AUTO CTRL",fg_bg=cpair(colors.black,colors.purple),alignment=ALIGN.CENTER,width=13,height=1,x=32,y=36}
    local auto_ctl = Rectangle{parent=main,border=border(1,colors.purple,true),thin=true,width=13,height=15,x=32,y=37}
    local auto_div = Div{parent=auto_ctl,width=13,height=15,x=1,y=1}

    local ctl_opts = { "Manual", "Primary", "Secondary", "Tertiary", "Backup" }

    local group = RadioButton{parent=auto_div,options=ctl_opts,callback=function()end,radio_colors=cpair(style.theme.accent_dark,style.theme.accent_light),select_color=colors.purple}

    group.register(u_ps, "auto_group_id", function (gid) group.set_value(gid + 1) end)

    auto_div.line_break()

    local function set_group() unit.set_group(group.get_value() - 1) end
    local set_grp_btn = PushButton{parent=auto_div,text="SET",x=4,min_width=5,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=style.wh_gray,dis_fg_bg=gry_wht,callback=set_group}

    auto_div.line_break()

    TextBox{parent=auto_div,text="Prio. Group",height=1,width=11,fg_bg=style.label}
    local auto_grp = TextBox{parent=auto_div,text="Manual",height=1,width=11,fg_bg=s_field}

    auto_grp.register(u_ps, "auto_group", auto_grp.set_value)

    auto_div.line_break()

    local a_rdy = IndicatorLight{parent=auto_div,label="Ready",x=2,colors=ind_grn}
    local a_stb = IndicatorLight{parent=auto_div,label="Standby",x=2,colors=ind_wht,flash=true,period=period.BLINK_1000_MS}

    a_rdy.register(u_ps, "U_AutoReady", a_rdy.update)

    -- update standby indicator
    a_stb.register(u_ps, "status", function (active)
        a_stb.update(unit.annunciator.AutoControl and (not active))
    end)
    a_stb.register(u_ps, "AutoControl", function (auto_active)
        if auto_active then
            a_stb.update(unit.reactor_data.mek_status.status == false)
        else a_stb.update(false) end
    end)

    -- enable/disable controls based on group assignment (start button is separate)
    burn_rate.register(u_ps, "auto_group_id", function (gid)
        if gid == 0 then burn_rate.enable() else burn_rate.disable() end
    end)
    set_burn_btn.register(u_ps, "auto_group_id", function (gid)
        if gid == 0 then set_burn_btn.enable() else set_burn_btn.disable() end
    end)

    -- can't change group if auto is engaged regardless of if this unit is part of auto control
    set_grp_btn.register(f_ps, "auto_active", function (auto_active)
        if auto_active then set_grp_btn.disable() else set_grp_btn.enable() end
    end)

    return main
end

return init
