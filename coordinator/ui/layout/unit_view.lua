--
-- Reactor Unit SCADA Coordinator GUI
--

local tcallbackdsp      = require("scada-common.tcallbackdsp")

local iocontrol         = require("coordinator.iocontrol")

local style             = require("coordinator.ui.style")

local core              = require("graphics.core")

local DisplayBox        = require("graphics.elements.displaybox")
local Div               = require("graphics.elements.div")
local TextBox           = require("graphics.elements.textbox")
local ColorMap          = require("graphics.elements.colormap")

local CoreMap           = require("graphics.elements.indicators.coremap")
local DataIndicator     = require("graphics.elements.indicators.data")
local HorizontalBar     = require("graphics.elements.indicators.hbar")
local IndicatorLight    = require("graphics.elements.indicators.light")
local StateIndicator    = require("graphics.elements.indicators.state")
local TriIndicatorLight = require("graphics.elements.indicators.trilight")
local VerticalBar       = require("graphics.elements.indicators.vbar")

local MultiButton       = require("graphics.elements.controls.multi_button")
local PushButton        = require("graphics.elements.controls.push_button")
local SCRAMButton       = require("graphics.elements.controls.scram_button")
local StartButton       = require("graphics.elements.controls.start_button")
local SpinboxNumeric    = require("graphics.elements.controls.spinbox_numeric")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border

-- create a unit view
---@param monitor table
---@param id integer
local function init(monitor, id)
    local unit = iocontrol.get_db().units[id]   ---@type ioctl_entry
    local r_ps = unit.reactor_ps
    local b_ps = unit.boiler_ps_tbl
    local t_ps = unit.turbine_ps_tbl

    local main = DisplayBox{window=monitor,fg_bg=style.root}

    TextBox{parent=main,text="Reactor Unit #" .. id,alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    local scram_fg_bg = cpair(colors.white, colors.gray)
    local lu_cpair    = cpair(colors.gray, colors.gray)

    -- main stats and core map --

    ---@todo need to be checking actual reactor dimensions somehow
    local core_map = CoreMap{parent=main,x=2,y=3,reactor_l=18,reactor_w=18}
    r_ps.subscribe("temp", core_map.update)

    local stat_fg_bg = cpair(colors.black,colors.white)

    TextBox{parent=main,x=21,y=3,text="Core Temp",height=1,fg_bg=style.label}
    local core_temp = DataIndicator{parent=main,x=21,label="",format="%9.2f",value=0,unit="K",lu_colors=lu_cpair,width=12,fg_bg=stat_fg_bg}
    r_ps.subscribe("temp", core_temp.update)
    main.line_break()

    TextBox{parent=main,x=21,text="Burn Rate",height=1,width=12,fg_bg=style.label}
    local act_burn_r = DataIndicator{parent=main,x=21,label="",format="%6.1f",value=0,unit="mB/t",lu_colors=lu_cpair,width=12,fg_bg=stat_fg_bg}
    r_ps.subscribe("act_burn_rate", act_burn_r.update)
    main.line_break()

    TextBox{parent=main,x=21,text="Commanded Burn Rate",height=2,width=12,fg_bg=style.label}
    local burn_r = DataIndicator{parent=main,x=21,label="",format="%6.1f",value=0,unit="mB/t",lu_colors=lu_cpair,width=12,fg_bg=stat_fg_bg}
    r_ps.subscribe("burn_rate", burn_r.update)
    main.line_break()

    TextBox{parent=main,x=21,text="Heating Rate",height=1,width=12,fg_bg=style.label}
    local heating_r = DataIndicator{parent=main,x=21,label="",format="%11.0f",value=0,unit="",lu_colors=lu_cpair,width=12,fg_bg=stat_fg_bg}
    r_ps.subscribe("heating_rate", heating_r.update)
    main.line_break()

    TextBox{parent=main,x=21,text="Containment Integrity",height=2,width=12,fg_bg=style.label}
    local integ = DataIndicator{parent=main,x=21,label="",format="%9.0f",value=100,unit="%",lu_colors=lu_cpair,width=12,fg_bg=stat_fg_bg}
    r_ps.subscribe("damage", function (x) integ.update(1.0 - (x / 100.0)) end)
    main.line_break()

    -- TextBox{parent=main,text="FL",x=21,y=19,height=1,width=2,fg_bg=style.label}
    -- TextBox{parent=main,text="WS",x=24,y=19,height=1,width=2,fg_bg=style.label}
    -- TextBox{parent=main,text="CL",x=28,y=19,height=1,width=2,fg_bg=style.label}
    -- TextBox{parent=main,text="HC",x=31,y=19,height=1,width=2,fg_bg=style.label}

    -- local fuel  = VerticalBar{parent=main,x=21,y=12,fg_bg=cpair(colors.black,colors.gray),height=6,width=2}
    -- local waste = VerticalBar{parent=main,x=24,y=12,fg_bg=cpair(colors.brown,colors.gray),height=6,width=2}
    -- local ccool = VerticalBar{parent=main,x=28,y=12,fg_bg=cpair(colors.lightBlue,colors.gray),height=6,width=2}
    -- local hcool = VerticalBar{parent=main,x=31,y=12,fg_bg=cpair(colors.orange,colors.gray),height=6,width=2}

    -- annunciator --

    local annunciator = Div{parent=main,x=34,y=3}

    -- annunciator colors per IAEA-TECDOC-812 recommendations

    -- connectivity/basic state
    local plc_online = IndicatorLight{parent=annunciator,label="PLC Online",colors=cpair(colors.green,colors.red)}
    local plc_hbeat  = IndicatorLight{parent=annunciator,label="PLC Heartbeat",colors=cpair(colors.white,colors.gray)}
    local r_active   = IndicatorLight{parent=annunciator,label="Active",colors=cpair(colors.green,colors.gray)}
    ---@todo auto control as info sent here
    local r_auto     = IndicatorLight{parent=annunciator,label="Auto Control",colors=cpair(colors.blue,colors.gray)}

    r_ps.subscribe("PLCOnline", plc_online.update)
    r_ps.subscribe("PLCHeartbeat", plc_hbeat.update)
    r_ps.subscribe("status", r_active.update)

    annunciator.line_break()

    -- annunciator fields
    local r_scram = IndicatorLight{parent=annunciator,label="Reactor SCRAM",colors=cpair(colors.red,colors.gray)}
    local r_mscrm = IndicatorLight{parent=annunciator,label="Manual Reactor SCRAM",colors=cpair(colors.red,colors.gray)}
    local r_rtrip = IndicatorLight{parent=annunciator,label="RCP Trip",colors=cpair(colors.red,colors.gray)}
    local r_cflow = IndicatorLight{parent=annunciator,label="RCS Flow Low",colors=cpair(colors.yellow,colors.gray)}
    local r_temp  = IndicatorLight{parent=annunciator,label="Reactor Temp. High",colors=cpair(colors.red,colors.gray)}
    local r_rhdt  = IndicatorLight{parent=annunciator,label="Reactor High Delta T",colors=cpair(colors.yellow,colors.gray)}
    local r_firl  = IndicatorLight{parent=annunciator,label="Fuel Input Rate Low",colors=cpair(colors.yellow,colors.gray)}
    local r_wloc  = IndicatorLight{parent=annunciator,label="Waste Line Occlusion",colors=cpair(colors.yellow,colors.gray)}
    local r_hsrt  = IndicatorLight{parent=annunciator,label="High Startup Rate",colors=cpair(colors.yellow,colors.gray)}

    r_ps.subscribe("ReactorSCRAM", r_scram.update)
    r_ps.subscribe("ManualReactorSCRAM", r_mscrm.update)
    r_ps.subscribe("RCPTrip", r_rtrip.update)
    r_ps.subscribe("RCSFlowLow", r_cflow.update)
    r_ps.subscribe("ReactorTempHigh", r_temp.update)
    r_ps.subscribe("ReactorHighDeltaT", r_rhdt.update)
    r_ps.subscribe("FuelInputRateLow", r_firl.update)
    r_ps.subscribe("WasteLineOcclusion", r_wloc.update)
    r_ps.subscribe("HighStartupRate", r_hsrt.update)

    annunciator.line_break()

    -- RPS
    local rps_trp = IndicatorLight{parent=annunciator,label="RPS Trip",colors=cpair(colors.red,colors.gray)}
    local rps_dmg = IndicatorLight{parent=annunciator,label="Damage Critical",colors=cpair(colors.yellow,colors.gray)}
    local rps_exh = IndicatorLight{parent=annunciator,label="Excess Heated Coolant",colors=cpair(colors.yellow,colors.gray)}
    local rps_exw = IndicatorLight{parent=annunciator,label="Excess Waste",colors=cpair(colors.yellow,colors.gray)}
    local rps_tmp = IndicatorLight{parent=annunciator,label="High Core Temp",colors=cpair(colors.yellow,colors.gray)}
    local rps_nof = IndicatorLight{parent=annunciator,label="No Fuel",colors=cpair(colors.yellow,colors.gray)}
    local rps_noc = IndicatorLight{parent=annunciator,label="No Coolant",colors=cpair(colors.yellow,colors.gray)}
    local rps_flt = IndicatorLight{parent=annunciator,label="PPM Fault",colors=cpair(colors.yellow,colors.gray)}
    local rps_tmo = IndicatorLight{parent=annunciator,label="Timeout",colors=cpair(colors.yellow,colors.gray)}

    r_ps.subscribe("rps_tripped", rps_trp.update)
    r_ps.subscribe("dmg_crit", rps_dmg.update)
    r_ps.subscribe("ex_hcool", rps_exh.update)
    r_ps.subscribe("ex_waste", rps_exw.update)
    r_ps.subscribe("high_temp", rps_tmp.update)
    r_ps.subscribe("no_fuel", rps_nof.update)
    r_ps.subscribe("no_cool", rps_noc.update)
    r_ps.subscribe("fault", rps_flt.update)
    r_ps.subscribe("timeout", rps_tmo.update)

    annunciator.line_break()

    -- cooling
    local c_brm  = IndicatorLight{parent=annunciator,label="Boil Rate Mismatch",colors=cpair(colors.yellow,colors.gray)}
    local c_cfm  = IndicatorLight{parent=annunciator,label="Coolant Feed Mismatch",colors=cpair(colors.yellow,colors.gray)}
    local c_sfm  = IndicatorLight{parent=annunciator,label="Steam Feed Mismatch",colors=cpair(colors.yellow,colors.gray)}
    local c_mwrf = IndicatorLight{parent=annunciator,label="Max Water Return Feed",colors=cpair(colors.yellow,colors.gray)}
    local c_tbnt = IndicatorLight{parent=annunciator,label="Turbine Trip",colors=cpair(colors.red,colors.gray)}

    r_ps.subscribe("BoilRateMismatch", c_brm.update)
    r_ps.subscribe("CoolantFeedMismatch", c_cfm.update)
    r_ps.subscribe("SteamFeedMismatch", c_sfm.update)
    r_ps.subscribe("MaxWaterReturnFeed", c_mwrf.update)
    r_ps.subscribe("TurbineTrip", c_tbnt.update)

    annunciator.line_break()

    -- machine-specific indicators
    if unit.num_boilers > 0 then
        TextBox{parent=main,x=32,y=34,text="B1",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local b1_hr = IndicatorLight{parent=annunciator,label="Heating Rate Low",colors=cpair(colors.yellow,colors.gray)}
        b_ps[1].subscribe("HeatingRateLow", b1_hr.update)
    end
    if unit.num_boilers > 1 then
        TextBox{parent=main,x=32,text="B2",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local b2_hr = IndicatorLight{parent=annunciator,label="Heating Rate Low",colors=cpair(colors.yellow,colors.gray)}
        b_ps[2].subscribe("HeatingRateLow", b2_hr.update)
    end

    if unit.num_boilers > 0 then
        main.line_break()
        annunciator.line_break()
    end

    TextBox{parent=main,x=32,text="T1",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
    local t1_sdo = TriIndicatorLight{parent=annunciator,label="Steam Dump Open",c1=colors.gray,c2=colors.yellow,c3=colors.red}
    t_ps[1].subscribe("SteamDumpOpen", t1_sdo.update)

    TextBox{parent=main,x=32,text="T1",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
    local t1_tos = IndicatorLight{parent=annunciator,label="Turbine Over Speed",colors=cpair(colors.red,colors.gray)}
    t_ps[1].subscribe("TurbineOverSpeed", t1_tos.update)

    TextBox{parent=main,x=32,text="T1",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
    local t1_trp = IndicatorLight{parent=annunciator,label="Turbine Trip",colors=cpair(colors.red,colors.gray)}
    t_ps[1].subscribe("TurbineTrip", t1_trp.update)

    main.line_break()
    annunciator.line_break()

    if unit.num_turbines > 1 then
        TextBox{parent=main,x=32,text="T2",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t2_sdo = TriIndicatorLight{parent=annunciator,label="Steam Dump Open",c1=colors.gray,c2=colors.yellow,c3=colors.red}
        t_ps[2].subscribe("SteamDumpOpen", t2_sdo.update)

        TextBox{parent=main,x=32,text="T2",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t2_tos = IndicatorLight{parent=annunciator,label="Turbine Over Speed",colors=cpair(colors.red,colors.gray)}
        t_ps[2].subscribe("TurbineOverSpeed", t2_tos.update)

        TextBox{parent=main,x=32,text="T2",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t2_trp = IndicatorLight{parent=annunciator,label="Turbine Trip",colors=cpair(colors.red,colors.gray)}
        t_ps[2].subscribe("TurbineTrip", t2_trp.update)

        main.line_break()
        annunciator.line_break()
    end

    if unit.num_turbines > 2 then
        TextBox{parent=main,x=32,text="T3",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t3_sdo = TriIndicatorLight{parent=annunciator,label="Steam Dump Open",c1=colors.gray,c2=colors.yellow,c3=colors.red}
        t_ps[3].subscribe("SteamDumpOpen", t3_sdo.update)

        TextBox{parent=main,x=32,text="T3",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t3_tos = IndicatorLight{parent=annunciator,label="Turbine Over Speed",colors=cpair(colors.red,colors.gray)}
        t_ps[3].subscribe("TurbineOverSpeed", t3_tos.update)

        TextBox{parent=main,x=32,text="T3",width=2,height=1,fg_bg=cpair(colors.black, colors.white)}
        local t3_trp = IndicatorLight{parent=annunciator,label="Turbine Trip",colors=cpair(colors.red,colors.gray)}
        t_ps[3].subscribe("TurbineTrip", t3_trp.update)

        annunciator.line_break()
    end

    ---@todo radiation monitor
    IndicatorLight{parent=annunciator,label="Radiation Monitor",colors=cpair(colors.green,colors.gray)}
    IndicatorLight{parent=annunciator,label="Radiation Alarm",colors=cpair(colors.red,colors.gray)}
    DataIndicator{parent=main,x=34,y=51,label="",format="%10.1f",value=0,unit="mSv/h",lu_colors=lu_cpair,width=18,fg_bg=stat_fg_bg}

    -- reactor controls --

    StartButton{parent=main,x=12,y=44,callback=unit.start,fg_bg=scram_fg_bg}
    SCRAMButton{parent=main,x=22,y=44,callback=unit.scram,fg_bg=scram_fg_bg}

    local burn_control = Div{parent=main,x=12,y=40,width=19,height=3,fg_bg=cpair(colors.gray,colors.white)}
    local burn_rate = SpinboxNumeric{parent=burn_control,x=2,y=1,whole_num_precision=4,fractional_precision=1,arrow_fg_bg=cpair(colors.gray,colors.white),fg_bg=cpair(colors.black,colors.white)}
    TextBox{parent=burn_control,x=9,y=2,text="mB/t"}
    local set_burn = function () unit.set_burn(burn_rate.get_value()) end
    PushButton{parent=burn_control,x=14,y=2,text="SET",min_width=5,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=cpair(colors.white,colors.gray),callback=set_burn}

    local opts = {
        {
            text = "Auto",
            fg_bg = cpair(colors.black, colors.lightGray),
            active_fg_bg = cpair(colors.white, colors.gray)
        },
        {
            text = "Pu",
            fg_bg = cpair(colors.black, colors.lightGray),
            active_fg_bg = cpair(colors.black, colors.lime)
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

    ---@todo waste selection
    local waste_sel_f = function (s) print("waste: " .. s) end
    local waste_sel = Div{parent=main,x=2,y=48,width=29,height=2,fg_bg=cpair(colors.black, colors.white)}

    MultiButton{parent=waste_sel,x=1,y=1,options=opts,callback=waste_sel_f,min_width=6,fg_bg=cpair(colors.black, colors.white)}
    TextBox{parent=waste_sel,text="Waste Processing",alignment=TEXT_ALIGN.CENTER,x=1,y=1,height=1}

    ---@fixme test code
    main.line_break()
    ColorMap{parent=main,x=2,y=51}

    ---@fixme test code
    local rps = true
    local function _test_toggle()
        rps_trp.update(rps)
        rps = not rps
        tcallbackdsp.dispatch(0.25, _test_toggle)
    end

    ---@fixme test code
    tcallbackdsp.dispatch(0.25, _test_toggle)

    return main
end

return init
