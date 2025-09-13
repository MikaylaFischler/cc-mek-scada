--
-- Alarm Test App
--

local iocontrol      = require("pocket.iocontrol")
local pocket         = require("pocket.pocket")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local MultiPane      = require("graphics.elements.MultiPane")
local TextBox        = require("graphics.elements.TextBox")

local IndicatorLight = require("graphics.elements.indicators.IndicatorLight")

local Checkbox       = require("graphics.elements.controls.Checkbox")
local PushButton     = require("graphics.elements.controls.PushButton")
local SwitchButton   = require("graphics.elements.controls.SwitchButton")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

local c_wht_gray  = cpair(colors.white, colors.gray)
local c_red_gray  = cpair(colors.red, colors.gray)
local c_yel_gray  = cpair(colors.yellow, colors.gray)
local c_blue_gray = cpair(colors.blue, colors.gray)

-- create alarm test page view
---@param root Container parent
local function new_view(root)
    local db    = iocontrol.get_db()
    local ps    = db.ps
    local ttest = db.diag.tone_test

    local frame = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(APP_ID.ALARMS, frame, nil, true)

    local main     = Div{parent=frame,x=1,y=1}
    local page_div = Div{parent=main,y=2,width=main.get_width()}

    --#region alarm testing

    local alarm_page = app.new_page(nil, 1)
    alarm_page.tasks = { db.diag.tone_test.get_tone_states }

    local alarms_div = Div{parent=page_div}

    TextBox{parent=alarms_div,text="Alarm Sounder Tests",alignment=ALIGN.CENTER}

    local alarm_ready_warn = TextBox{parent=alarms_div,y=2,text="",alignment=ALIGN.CENTER,fg_bg=cpair(colors.yellow,colors.black)}
    alarm_ready_warn.register(ps, "alarm_ready_warn", alarm_ready_warn.set_value)

    local alarm_page_states = Div{parent=alarms_div,x=2,y=3,height=5,width=8}

    TextBox{parent=alarm_page_states,text="States",alignment=ALIGN.CENTER}
    local ta_1 = IndicatorLight{parent=alarm_page_states,label="1",colors=c_blue_gray}
    local ta_2 = IndicatorLight{parent=alarm_page_states,label="2",colors=c_blue_gray}
    local ta_3 = IndicatorLight{parent=alarm_page_states,label="3",colors=c_blue_gray}
    local ta_4 = IndicatorLight{parent=alarm_page_states,label="4",colors=c_blue_gray}
    local ta_5 = IndicatorLight{parent=alarm_page_states,x=6,y=2,label="5",colors=c_blue_gray}
    local ta_6 = IndicatorLight{parent=alarm_page_states,x=6,label="6",colors=c_blue_gray}
    local ta_7 = IndicatorLight{parent=alarm_page_states,x=6,label="7",colors=c_blue_gray}
    local ta_8 = IndicatorLight{parent=alarm_page_states,x=6,label="8",colors=c_blue_gray}

    local ta = { ta_1, ta_2, ta_3, ta_4, ta_5, ta_6, ta_7, ta_8 }

    for i = 1, #ta do
        ta[i].register(ps, "alarm_tone_" .. i, ta[i].update)
    end

    local alarms = Div{parent=alarms_div,x=11,y=3,height=15,fg_bg=cpair(colors.lightGray,colors.black)}

    TextBox{parent=alarms,text="Alarms (\x13)",alignment=ALIGN.CENTER,fg_bg=alarms_div.get_fg_bg()}

    local alarm_btns = {}
    alarm_btns[1]  = Checkbox{parent=alarms,label="BREACH",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_breach}
    alarm_btns[2]  = Checkbox{parent=alarms,label="RADIATION",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_rad}
    alarm_btns[3]  = Checkbox{parent=alarms,label="RCT LOST",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_lost}
    alarm_btns[4]  = Checkbox{parent=alarms,label="CRIT DAMAGE",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_crit}
    alarm_btns[5]  = Checkbox{parent=alarms,label="DAMAGE",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_dmg}
    alarm_btns[6]  = Checkbox{parent=alarms,label="OVER TEMP",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_overtemp}
    alarm_btns[7]  = Checkbox{parent=alarms,label="HIGH TEMP",min_width=15,box_fg_bg=c_yel_gray,callback=ttest.test_hightemp}
    alarm_btns[8]  = Checkbox{parent=alarms,label="WASTE LEAK",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_wasteleak}
    alarm_btns[9]  = Checkbox{parent=alarms,label="WASTE HIGH",min_width=15,box_fg_bg=c_yel_gray,callback=ttest.test_highwaste}
    alarm_btns[10] = Checkbox{parent=alarms,label="RPS TRANS",min_width=15,box_fg_bg=c_yel_gray,callback=ttest.test_rps}
    alarm_btns[11] = Checkbox{parent=alarms,label="RCS TRANS",min_width=15,box_fg_bg=c_yel_gray,callback=ttest.test_rcs}
    alarm_btns[12] = Checkbox{parent=alarms,label="TURBINE TRP",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_turbinet}

    ttest.alarm_buttons = alarm_btns

    local function stop_all_alarms()
        for i = 1, #alarm_btns do alarm_btns[i].set_value(false) end
        ttest.stop_alarms()
    end

    PushButton{parent=alarms,x=3,y=15,text="STOP \x13",min_width=8,fg_bg=cpair(colors.black,colors.red),active_fg_bg=c_wht_gray,callback=stop_all_alarms}

    --#endregion

    --#region direct tone testing

    local tones_page = app.new_page(nil, 2)
    tones_page.tasks = { db.diag.tone_test.get_tone_states }

    local tones_div = Div{parent=page_div}

    TextBox{parent=tones_div,text="Alarm Sounder Tests",alignment=ALIGN.CENTER}

    local tone_ready_warn = TextBox{parent=tones_div,y=2,text="",alignment=ALIGN.CENTER,fg_bg=cpair(colors.yellow,colors.black)}
    tone_ready_warn.register(ps, "alarm_ready_warn", tone_ready_warn.set_value)

    local tone_page_states = Div{parent=tones_div,x=3,y=3,height=5,width=8}

    TextBox{parent=tone_page_states,text="States",alignment=ALIGN.CENTER}
    local tt_1 = IndicatorLight{parent=tone_page_states,label="1",colors=c_blue_gray}
    local tt_2 = IndicatorLight{parent=tone_page_states,label="2",colors=c_blue_gray}
    local tt_3 = IndicatorLight{parent=tone_page_states,label="3",colors=c_blue_gray}
    local tt_4 = IndicatorLight{parent=tone_page_states,label="4",colors=c_blue_gray}
    local tt_5 = IndicatorLight{parent=tone_page_states,x=6,y=2,label="5",colors=c_blue_gray}
    local tt_6 = IndicatorLight{parent=tone_page_states,x=6,label="6",colors=c_blue_gray}
    local tt_7 = IndicatorLight{parent=tone_page_states,x=6,label="7",colors=c_blue_gray}
    local tt_8 = IndicatorLight{parent=tone_page_states,x=6,label="8",colors=c_blue_gray}

    local tt = { tt_1, tt_2, tt_3, tt_4, tt_5, tt_6, tt_7, tt_8 }

    for i = 1, #tt do
        tt[i].register(ps, "alarm_tone_" .. i, tt[i].update)
    end

    local tones = Div{parent=tones_div,x=14,y=3,height=10,width=8,fg_bg=cpair(colors.black,colors.yellow)}

    TextBox{parent=tones,text="Tones",alignment=ALIGN.CENTER,fg_bg=tones_div.get_fg_bg()}

    local test_btns = {}
    test_btns[1] = SwitchButton{parent=tones,text="TEST 1",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_1}
    test_btns[2] = SwitchButton{parent=tones,text="TEST 2",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_2}
    test_btns[3] = SwitchButton{parent=tones,text="TEST 3",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_3}
    test_btns[4] = SwitchButton{parent=tones,text="TEST 4",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_4}
    test_btns[5] = SwitchButton{parent=tones,text="TEST 5",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_5}
    test_btns[6] = SwitchButton{parent=tones,text="TEST 6",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_6}
    test_btns[7] = SwitchButton{parent=tones,text="TEST 7",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_7}
    test_btns[8] = SwitchButton{parent=tones,text="TEST 8",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_8}

    ttest.tone_buttons = test_btns

    local function stop_all_tones()
        for i = 1, #test_btns do test_btns[i].set_value(false) end
        ttest.stop_tones()
    end

    PushButton{parent=tones,text="STOP",min_width=8,active_fg_bg=c_wht_gray,fg_bg=cpair(colors.black,colors.red),callback=stop_all_tones}

    --#endregion

    -- setup multipane
    local u_pane = MultiPane{parent=page_div,x=1,y=1,panes={alarms_div,tones_div}}
    app.set_root_pane(u_pane)

    local list = {
        { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
        { label = " \x13 ", color = core.cpair(colors.black, colors.red), callback = function () app.switcher(1) end },
        { label = " \x0f ", color = core.cpair(colors.black, colors.yellow), callback = function () app.switcher(2) end }
    }

    app.set_sidebar(list)
end

return new_view
