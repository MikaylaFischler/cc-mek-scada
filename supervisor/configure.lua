--
-- Configuration GUI
--

local log         = require("scada-common.log")
local tcd         = require("scada-common.tcd")
local util        = require("scada-common.util")
local rsio        = require("scada-common.rsio")

local core        = require("graphics.core")

local DisplayBox  = require("graphics.elements.displaybox")
local Div         = require("graphics.elements.div")
local ListBox     = require("graphics.elements.listbox")
local MultiPane   = require("graphics.elements.multipane")
local PipeNet     = require("graphics.elements.pipenet")
local TextBox     = require("graphics.elements.textbox")

local CheckBox    = require("graphics.elements.controls.checkbox")
local PushButton  = require("graphics.elements.controls.push_button")
local Radio2D     = require("graphics.elements.controls.radio_2d")
local RadioButton = require("graphics.elements.controls.radio_button")

local NumberField = require("graphics.elements.form.number_field")
local TextField   = require("graphics.elements.form.text_field")

local println = util.println
local tri = util.trinary

local cpair = core.cpair

local LEFT = core.ALIGN.LEFT
local CENTER = core.ALIGN.CENTER
local RIGHT = core.ALIGN.RIGHT

log.init("log.txt", log.MODE.APPEND, true)

-- changes to the config data/format to let the user know
local changes = {}

---@class svr_configurator
local configurator = {}

local style = {}

style.root = cpair(colors.black, colors.lightGray)
style.header = cpair(colors.white, colors.gray)

style.colors = {
    { c = colors.red,       hex = 0xdf4949 },
    { c = colors.orange,    hex = 0xffb659 },
    { c = colors.yellow,    hex = 0xfffc79 },
    { c = colors.lime,      hex = 0x80ff80 },
    { c = colors.green,     hex = 0x4aee8a },
    { c = colors.cyan,      hex = 0x34bac8 },
    { c = colors.lightBlue, hex = 0x6cc0f2 },
    { c = colors.blue,      hex = 0x0096ff },
    { c = colors.purple,    hex = 0xb156ee },
    { c = colors.pink,      hex = 0xf26ba2 },
    { c = colors.magenta,   hex = 0xf9488a },
    { c = colors.lightGray, hex = 0xcacaca },
    { c = colors.gray,      hex = 0x575757 }
}

local bw_fg_bg = cpair(colors.black, colors.white)
local g_lg_fg_bg = cpair(colors.gray, colors.lightGray)
local nav_fg_bg = bw_fg_bg
local btn_act_fg_bg = cpair(colors.white, colors.gray)

local tool_ctl = {
    ask_config = false,
    has_config = false,
    viewing_config = false,
    importing_legacy = false,

    view_cfg = nil,         ---@type graphics_element
    settings_apply = nil,   ---@type graphics_element

    gen_summary = nil,      ---@type function
    show_current_cfg = nil, ---@type function
    load_legacy = nil,      ---@type function

    show_auth_key = nil,    ---@type function
    show_key_btn = nil,     ---@type graphics_element
    auth_key_textbox = nil, ---@type graphics_element
    auth_key_value = "",

    cooling_elems = {},
    tank_elems = {}
}

---@class svr_config
local tmp_cfg = {
    UnitCount = 1,
    CoolingConfig = {},
    FacilityTankMode = 0,
    FacilityTankDefs = nil,
    SVR_Channel = nil,
    PLC_Channel = nil,
    RTU_Channel = nil,
    CRD_Channel = nil,
    PKT_Channel = nil,
    PLC_Timeout = nil,
    RTU_Timeout = nil,
    CRD_Timeout = nil,
    PKT_Timeout = nil,
    TrustedRange = nil,
    AuthKey = nil,
    LogMode = 0,
    LogPath = "",
    LogDebug = false,
}

---@class svr_config
local ini_cfg = {}
---@class svr_config
local settings_cfg = {}

-- all settings fields, their nice names, and their default values
local fields = {
    { "UnitCount", "Number of Reactors", 1 },
    { "CoolingConfig", "Cooling Configuration", {} },
    { "FacilityTankMode", "Facility Tank Mode", 0 },
    { "FacilityTankDefs", "Facility Tank Definitions", {} },
    { "SVR_Channel", "SVR Channel", 16240 },
    { "PLC_Channel", "PLC Channel", 16241 },
    { "RTU_Channel", "RTU Channel", 16242 },
    { "CRD_Channel", "CRD Channel", 16243 },
    { "PKT_Channel", "PKT Channel", 16244 },
    { "PLC_Timeout", "PLC Connection Timeout", 5 },
    { "RTU_Timeout", "RTU Connection Timeout", 5 },
    { "CRD_Timeout", "CRD Connection Timeout", 5 },
    { "PKT_Timeout", "PKT Connection Timeout", 5 },
    { "TrustedRange", "Trusted Range", 0 },
    { "AuthKey", "Facility Auth Key" , ""},
    { "LogMode", "Log Mode", log.MODE.APPEND },
    { "LogPath", "Log Path", "/log.txt" },
    { "LogDebug","Log Debug Messages", false }
}

-- load data from the settings file
---@param target svr_config
---@param raw boolean? true to not use default values
local function load_settings(target, raw)
    for _, v in pairs(fields) do settings.unset(v[1]) end

    local loaded = settings.load("/supervisor.settings")

    for _, v in pairs(fields) do target[v[1]] = settings.get(v[1], tri(raw, nil, v[3])) end

    return loaded
end

-- create the config view
---@param display graphics_element
local function config_view(display)
---@diagnostic disable-next-line: undefined-field
    local function exit() os.queueEvent("terminate") end

    TextBox{parent=display,y=1,text="Supervisor Configurator",alignment=CENTER,height=1,fg_bg=style.header}

    local root_pane_div = Div{parent=display,x=1,y=2}

    local main_page = Div{parent=root_pane_div,x=1,y=1}
    local svr_cfg = Div{parent=root_pane_div,x=1,y=1}
    local net_cfg = Div{parent=root_pane_div,x=1,y=1}
    local log_cfg = Div{parent=root_pane_div,x=1,y=1}
    local summary = Div{parent=root_pane_div,x=1,y=1}
    local changelog = Div{parent=root_pane_div,x=1,y=1}

    local main_pane = MultiPane{parent=root_pane_div,x=1,y=1,panes={main_page,svr_cfg,net_cfg,log_cfg,summary,changelog}}

    -- MAIN PAGE

    local y_start = 5

    TextBox{parent=main_page,x=2,y=2,height=2,text="Welcome to the Supervisor configurator! Please select one of the following options."}

    if tool_ctl.ask_config then
        TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text="Notice: This device has no valid config so the configurator has been automatically started. If you previously had a valid config, you may want to check the Change Log to see what changed.",fg_bg=cpair(colors.red,colors.lightGray)}
        y_start = y_start + 5
    end

    local function view_config()
        tool_ctl.viewing_config = true
        tool_ctl.gen_summary(settings_cfg)
        tool_ctl.settings_apply.hide(true)
        main_pane.set_value(5)
    end

    if fs.exists("/supervisor/config.lua") then
        PushButton{parent=main_page,x=2,y=y_start,min_width=28,text="Import Legacy 'config.lua'",callback=function()tool_ctl.load_legacy()end,fg_bg=cpair(colors.black,colors.cyan),active_fg_bg=btn_act_fg_bg}
        y_start = y_start + 2
    end

    PushButton{parent=main_page,x=2,y=y_start,min_width=18,text="Configure System",callback=function()main_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    tool_ctl.view_cfg = PushButton{parent=main_page,x=2,y=y_start+2,min_width=20,text="View Configuration",callback=view_config,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}

    if not tool_ctl.has_config then tool_ctl.view_cfg.disable() end

    PushButton{parent=main_page,x=2,y=17,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=main_page,x=39,y=17,min_width=12,text="Change Log",callback=function()main_pane.set_value(6)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    -- SUPERVISOR CONFIG

    local svr_c_1 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_2 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_3 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_4 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_5 = Div{parent=svr_cfg,x=2,y=4,width=49}

    local svr_pane = MultiPane{parent=svr_cfg,x=1,y=4,panes={svr_c_1,svr_c_2,svr_c_3,svr_c_4,svr_c_5}}

    TextBox{parent=svr_cfg,x=1,y=2,height=1,text=" Facility Configuration",fg_bg=cpair(colors.black,colors.green)}

    TextBox{parent=svr_c_1,x=1,y=1,height=3,text="Please enter the number of reactors you have, also referred to as reactor units or 'units' for short. A maximum of 4 is currently supported."}
    local num_units = NumberField{parent=svr_c_1,x=1,y=5,width=5,max_digits=2,default=ini_cfg.UnitCount,min=1,max=4,fg_bg=bw_fg_bg}
    TextBox{parent=svr_c_1,x=7,y=5,height=1,text="reactors"}

    local nu_error = TextBox{parent=svr_c_1,x=8,y=14,height=1,width=35,text="Please set the number of reactors.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_num_units()
        local count = tonumber(num_units.get_value())
        if count ~= nil and count > 0 and count < 5 then
            nu_error.hide(true)
            tmp_cfg.UnitCount = count

            local confs = tool_ctl.cooling_elems
            if count >= 2 then confs[2].line.show() else confs[2].line.hide(true) end
            if count >= 3 then confs[3].line.show() else confs[3].line.hide(true) end
            if count == 4 then confs[4].line.show() else confs[4].line.hide(true) end

            svr_pane.set_value(2)
        else nu_error.show() end
    end

    PushButton{parent=svr_c_1,x=1,y=14,min_width=6,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_1,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_num_units,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_2,x=1,y=1,height=4,text="Please provide the reactor cooling configuration below. This includes the number of turbines, boilers, and if that reactor has a connection to a dynamic tank for emergency coolant."}
    TextBox{parent=svr_c_2,x=1,y=6,height=1,text="UNIT    TURBINES   BOILERS   HAS TANK CONNECTION?",fg_bg=g_lg_fg_bg}

    for i = 1, 4 do
        local num_t, num_b, has_t = 1, 0, false

        if ini_cfg.CoolingConfig[1] then
            local conf = ini_cfg.CoolingConfig[1]
            if util.is_int(conf.TurbineCount) then num_t = math.min(3, math.max(1, conf.TurbineCount or 1)) end
            if util.is_int(conf.BoilerCount) then num_b = math.min(2, math.max(1, conf.BoilerCount or 0)) end
            has_t = conf.TankConnection == true
        end

        local line = Div{parent=svr_c_2,x=1,y=7+i,height=1}

        TextBox{parent=line,text="Unit "..i,width=6}
        local turbines = NumberField{parent=line,x=9,y=1,width=5,max_digits=2,default=num_t,min=1,max=3,fg_bg=bw_fg_bg}
        local boilers = NumberField{parent=line,x=20,y=1,width=5,max_digits=2,default=num_b,min=0,max=2,fg_bg=bw_fg_bg}
        local tank = CheckBox{parent=line,x=30,y=1,label="Is Connected",default=has_t,box_fg_bg=cpair(colors.green,colors.black)}

        tool_ctl.cooling_elems[i] = { line = line, turbines = turbines, boilers = boilers, tank = tank }
    end

    local cool_err = TextBox{parent=svr_c_2,x=8,y=14,height=1,width=33,text="Please fill out all fields.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_cooling()
        local any_missing = false
        for i = 1, tmp_cfg.UnitCount do
            local conf = tool_ctl.cooling_elems[i]
            any_missing = any_missing or (tonumber(conf.turbines.get_value()) == nil)
            any_missing = any_missing or (tonumber(conf.boilers.get_value()) == nil)
        end

        if any_missing then
            cool_err.show()
        else
            local any_has_tank = false
            tool_ctl.num_tank_conns = 0

            tmp_cfg.CoolingConfig = {}
            for i = 1, tmp_cfg.UnitCount do
                local conf = tool_ctl.cooling_elems[i]
                tmp_cfg.CoolingConfig[i] = { TurbineCount = tonumber(conf.turbines.get_value()), BoilerCount = tonumber(conf.boilers.get_value()), TankConnection = conf.tank.get_value() }
                if conf.tank.get_value() then
                    any_has_tank = true
                    tool_ctl.num_tank_conns = tool_ctl.num_tank_conns + 1
                end
            end

            for i = 1, 4 do
                local elem = tool_ctl.tank_elems[i]
                if i <= tmp_cfg.UnitCount then
                    elem.div.show()
                    if tmp_cfg.CoolingConfig[i].TankConnection then
                        elem.no_tank.hide()
                        elem.tank_opt.show()
                    else
                        elem.tank_opt.hide(true)
                        elem.no_tank.show()
                    end
                else elem.div.hide(true) end
            end

            -- if any_has_tank then svr_pane.set_value(3) else main_pane.set_value(3) end
            svr_pane.set_value(3)
        end
    end

    PushButton{parent=svr_c_2,x=1,y=14,min_width=6,text="\x1b Back",callback=function()svr_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_2,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_cooling,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_3,x=1,y=1,height=6,text="You have set one or more of your units to use dynamic tanks for emergency coolant. You have two paths for configuration. The first is to assign dynamic tanks to reactor units; one tank per reactor, only connected to that reactor. RTU configurations must also assign it as such."}
    TextBox{parent=svr_c_3,x=1,y=8,height=3,text="Alternatively, you can configure them as facility tanks to connect to multiple reactor units. These can intermingle with unit-specific tanks."}

    local en_fac_tanks = CheckBox{parent=svr_c_3,x=1,y=12,label="Use Facility Dynamic Tanks",default=ini_cfg.FacilityTankMode~=0,box_fg_bg=cpair(colors.green,colors.black)}

    local function submit_en_fac_tank()
        -- if en_fac_tanks.get_value() then
        --     assert(tool_ctl.num_tank_conns >= 1, "attempted to enable facility tanks with no tank connections assigned")
        --     if tool_ctl.num_tank_conns == 1 then
        --         -- nothing special for the user to do, set it automatically
        --         tmp_cfg.FacilityTankMode = 1
        --         tmp_cfg.FacilityTankDefs = { 2 }
        --         main_pane.set_value(3)
        --     else
        --         svr_pane.set_value(4)
        --     end
        -- else
        --     tmp_cfg.FacilityTankMode = 0
        --     tmp_cfg.FacilityTankDefs = {}
        --     main_pane.set_value(3)
        -- end

        svr_pane.set_value(4) -- for testing
    end

    PushButton{parent=svr_c_3,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_3,x=44,y=14,text="Next \x1a",callback=submit_en_fac_tank,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_4,x=1,y=1,height=4,text="Please set unit connections to dynamic tanks, selecting at least one facility tank. The layout for facility tanks will be configured next."}

    for i = 1, 4 do
        local div = Div{parent=svr_c_4,x=1,y=3+(2*i),height=2}

        TextBox{parent=div,x=1,y=1,width=33,height=1,text="Unit "..i.." will be connected to..."}
        TextBox{parent=div,x=6,y=2,width=3,height=1,text="..."}
        local tank_opt = Radio2D{parent=div,x=10,y=2,rows=1,columns=2,default=2,options={"its own Unit Tank","a Facility Tank"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.green,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
        local no_tank = TextBox{parent=div,x=9,y=2,width=34,height=1,text="no tank (as you set two steps ago)",fg_bg=cpair(colors.gray,colors.lightGray),hidden=true}

        tool_ctl.tank_elems[i] = { div = div, tank_opt = tank_opt, no_tank = no_tank }
    end

    local tank_err = TextBox{parent=svr_c_4,x=8,y=14,height=1,width=33,text="You selected no facility tanks.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_tank_defs()
        local any_fac = false

        tmp_cfg.FacilityTankDefs = {}
        for i = 1, tmp_cfg.UnitCount do
            if tmp_cfg.CoolingConfig[i].TankConnection then
                tmp_cfg.FacilityTankDefs[i] = tool_ctl.tank_elems[i].tank_opt.get_value()
                any_fac = any_fac or (tmp_cfg.FacilityTankDefs[i] == 2)
            else tmp_cfg.FacilityTankDefs[i] = 0 end
        end

        -- if any_fac then
        --     tank_err.hide(true)
        --     svr_pane.set_value(5)
        -- else tank_err.show() end
        svr_pane.set_value(5)
    end

    PushButton{parent=svr_c_4,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_4,x=44,y=14,text="Next \x1a",callback=submit_tank_defs,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_5,x=1,y=1,height=1,text="Please select your dynamic tank layout."}
    TextBox{parent=svr_c_5,x=12,y=3,height=1,text="Facility Tanks             Unit Tanks",fg_bg=g_lg_fg_bg}
    local vis = Div{parent=svr_c_5,x=15,y=5}
    local tanks = TextBox{parent=vis,x=1,y=1,width=6,height=7,text="Tank A"}
    local units = TextBox{parent=vis,x=14,y=1,width=6,height=7,text="Unit 1\n\nUnit 2\n\nUnit 3\n\nUnit 4"}

    for i = 1, 4 do
        local line = Div{parent=vis,x=21,y=(i*2)-1,width=12,height=1}
        TextBox{parent=line,width=5,height=1,text="\x8c\x8c\x8c\x8c\x8c",fg_bg=cpair(colors.blue,colors.lightGray)}
        local label = TextBox{parent=line,x=7,y=1,width=6,height=1,text="Tank ?"}
    end

    local m1_pipes = { core.pipe(0,0,4,0,colors.blue,true), core.pipe(3,0,4,2,colors.blue,true), core.pipe(3,2,4,4,colors.blue,true), core.pipe(3,4,4,6,colors.blue,true) }
    local m2_pipes = { core.pipe(0,0,4,0,colors.blue,true), core.pipe(3,0,4,2,colors.blue,true), core.pipe(3,2,4,4,colors.blue,true), core.pipe(0,6,4,6,colors.blue,true) }
    local m3_pipes = { core.pipe(0,0,4,0,colors.blue,true), core.pipe(3,0,4,2,colors.blue,true), core.pipe(0,4,4,4,colors.blue,true), core.pipe(3,4,4,6,colors.blue,true) }
    local m4_pipes = { core.pipe(0,0,4,0,colors.blue,true), core.pipe(0,2,4,2,colors.blue,true), core.pipe(3,2,4,4,colors.blue,true), core.pipe(3,4,4,6,colors.blue,true) }
    local m5_pipes = { core.pipe(0,0,4,0,colors.blue,true), core.pipe(3,0,4,2,colors.blue,true), core.pipe(0,4,4,4,colors.blue,true), core.pipe(0,6,4,6,colors.blue,true) }
    local m6_pipes = { core.pipe(0,0,4,0,colors.blue,true), core.pipe(0,2,4,2,colors.blue,true), core.pipe(3,2,4,4,colors.blue,true), core.pipe(0,6,4,6,colors.blue,true) }
    local m7_pipes = { core.pipe(0,0,4,0,colors.blue,true), core.pipe(0,2,4,2,colors.blue,true), core.pipe(0,4,4,4,colors.blue,true), core.pipe(3,4,4,6,colors.blue,true) }
    local m8_pipes = { core.pipe(0,0,4,0,colors.blue,true), core.pipe(0,2,4,2,colors.blue,true), core.pipe(0,4,4,4,colors.blue,true), core.pipe(0,6,4,6,colors.blue,true) }

    local pnet_m1 = PipeNet{parent=vis,x=8,y=1,width=5,height=7,pipes=m1_pipes}
    local pnet_m2 = PipeNet{parent=vis,x=8,y=1,width=5,height=7,pipes=m2_pipes}
    local pnet_m3 = PipeNet{parent=vis,x=8,y=1,width=5,height=7,pipes=m3_pipes}
    local pnet_m4 = PipeNet{parent=vis,x=8,y=1,width=5,height=7,pipes=m4_pipes}
    local pnet_m5 = PipeNet{parent=vis,x=8,y=1,width=5,height=7,pipes=m5_pipes}
    local pnet_m6 = PipeNet{parent=vis,x=8,y=1,width=5,height=7,pipes=m6_pipes}
    local pnet_m7 = PipeNet{parent=vis,x=8,y=1,width=5,height=7,pipes=m7_pipes}
    local pnet_m8 = PipeNet{parent=vis,x=8,y=1,width=5,height=7,pipes=m8_pipes}

    local pipe_pane = MultiPane{parent=vis,x=8,y=1,width=5,height=7,panes={pnet_m1,pnet_m2,pnet_m3,pnet_m4,pnet_m5,pnet_m6,pnet_m7,pnet_m8}}

    local hide_pipes_1u = Div{parent=vis,x=1,y=2,width=19,height=6,hidden=true}

    local function show_pipes(val)
        local text = {
            "Tank A",
            "Tank A\n\n\n\n\n\nTank B",
            "Tank A\n\n\n\nTank B",
            "Tank A\n\nTank B",
            "Tank A\n\n\n\nTank B\n\nTank C",
            "Tank A\n\nTank B\n\n\n\nTank C",
            "Tank A\n\nTank B\n\nTank C",
            "Tank A\n\nTank B\n\nTank C\n\nTank D"
        }

        tanks.set_value(text[val])
        pipe_pane.set_value(val)
    end

    -- local ftm_modes_1u = { "Mode 1" }
    -- local ftm_modes_2u = { "Mode 1", "Mode 4" }
    -- local ftm_modes_3u = { "Mode 1", "Mode 3", "Mode 4", "Mode 7" }
    local ftm_modes_4u = { "Mode 1", "Mode 2", "Mode 3", "Mode 4", "Mode 5", "Mode 6", "Mode 7", "Mode 8" }
    -- local ftm_btn_2u = RadioButton{parent=svr_c_4,x=1,y=2,callback=show_pipes,default=math.min(1,ini_cfg.FacilityTankMode)+1,options=ftm_modes_2u,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.green}
    -- local ftm_btn_3u = RadioButton{parent=svr_c_4,x=1,y=2,callback=show_pipes,default=math.min(1,ini_cfg.FacilityTankMode)+1,options=ftm_modes_3u,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.green}
    local ftm_btn_4u = RadioButton{parent=svr_c_5,x=1,y=4,callback=show_pipes,default=math.min(1,ini_cfg.FacilityTankMode)+1,options=ftm_modes_4u,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.green}

    -- TextBox{parent=plc_c_4,x=1,y=5,height=1,text="Bundled Redstone Configuration"}
    -- local bundled = CheckBox{parent=plc_c_4,x=1,y=6,label="Is Bundled?",default=ini_cfg.EmerCoolColor~=nil,box_fg_bg=cpair(colors.orange,colors.black),callback=function(v)tool_ctl.bundled_emcool(v)end}
    -- local color = Radio2D{parent=plc_c_4,x=1,y=8,rows=4,columns=4,default=color_to_idx(ini_cfg.EmerCoolColor),options=color_options,radio_colors=cpair(colors.lightGray,colors.black),color_map=color_options_map,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
    -- if ini_cfg.EmerCoolColor == nil then color.disable() end

    -- local function submit_emcool()
    --     tmp_cfg.EmerCoolSide = side_options_map[side.get_value()]
    --     tmp_cfg.EmerCoolColor = util.trinary(bundled.get_value(), color_options_map[color.get_value()], nil)
    --     next_from_plc()
    -- end

    PushButton{parent=svr_c_5,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_5,x=44,y=14,text="Next \x1a",callback=function()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    -- NET CONFIG

    local net_c_1 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_2 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_3 = Div{parent=net_cfg,x=2,y=4,width=49}

    local net_pane = MultiPane{parent=net_cfg,x=1,y=4,panes={net_c_1,net_c_2,net_c_3}}

    TextBox{parent=net_cfg,x=1,y=2,height=1,text=" Network Configuration",fg_bg=cpair(colors.black,colors.lightBlue)}

    TextBox{parent=net_c_1,x=1,y=1,height=1,text="Please set the network channels below."}
    TextBox{parent=net_c_1,x=1,y=3,height=4,text="Each of the 5 uniquely named channels, including the 2 below, must be the same for each device in this SCADA network. For multiplayer servers, it is recommended to not use the default channels.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=8,height=1,text="Supervisor Channel"}
    local svr_chan = NumberField{parent=net_c_1,x=1,y=9,width=7,default=ini_cfg.SVR_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=9,height=4,text="[SVR_CHANNEL]",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_1,x=1,y=11,height=1,text="PLC Channel"}
    local plc_chan = NumberField{parent=net_c_1,x=1,y=12,width=7,default=ini_cfg.PLC_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=12,height=4,text="[PLC_CHANNEL]",fg_bg=g_lg_fg_bg}

    local chan_err = TextBox{parent=net_c_1,x=8,y=14,height=1,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_channels()
        local svr_c = tonumber(svr_chan.get_value())
        local plc_c = tonumber(plc_chan.get_value())
        if svr_c ~= nil and plc_c ~= nil then
            tmp_cfg.SVR_Channel = svr_c
            tmp_cfg.PLC_Channel = plc_c
            net_pane.set_value(2)
            chan_err.hide(true)
        elseif svr_c == nil then
            chan_err.set_value("Please set the supervisor channel.")
            chan_err.show()
        else
            chan_err.set_value("Please set the PLC channel.")
            chan_err.show()
        end
    end

    PushButton{parent=net_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_1,x=44,y=14,text="Next \x1a",callback=submit_channels,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_2,x=1,y=1,height=1,text="Connection Timeout"}
    local timeout = NumberField{parent=net_c_2,x=1,y=2,width=7,default=ini_cfg.ConnTimeout,min=2,max=25,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_2,x=9,y=2,height=2,text="seconds (default 5)",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_2,x=1,y=3,height=4,text="You generally do not want or need to modify this. On slow servers, you can increase this to make the system wait longer before assuming a disconnection.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_2,x=1,y=8,height=1,text="Trusted Range"}
    local range = NumberField{parent=net_c_2,x=1,y=9,width=10,default=ini_cfg.TrustedRange,min=0,max_digits=20,allow_decimal=true,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_2,x=1,y=10,height=4,text="Setting this to a value larger than 0 prevents connections with devices that many meters (blocks) away in any direction.",fg_bg=g_lg_fg_bg}

    local p2_err = TextBox{parent=net_c_2,x=8,y=14,height=1,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_ct_tr()
        local timeout_val = tonumber(timeout.get_value())
        local range_val = tonumber(range.get_value())
        if timeout_val ~= nil and range_val ~= nil then
            tmp_cfg.ConnTimeout = timeout_val
            tmp_cfg.TrustedRange = range_val
            net_pane.set_value(3)
            p2_err.hide(true)
        elseif timeout_val == nil then
            p2_err.set_value("Please set the connection timeout.")
            p2_err.show()
        else
            p2_err.set_value("Please set the trusted range.")
            p2_err.show()
        end
    end

    PushButton{parent=net_c_2,x=1,y=14,text="\x1b Back",callback=function()net_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_2,x=44,y=14,text="Next \x1a",callback=submit_ct_tr,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_3,x=1,y=1,height=2,text="Optionally, set the facility authentication key below. Do NOT use one of your passwords."}
    TextBox{parent=net_c_3,x=1,y=4,height=6,text="This enables verifying that messages are authentic, so it is intended for security on multiplayer servers. All devices on the same network MUST use the same key if any device has a key. This does result in some extra compution (can slow things down).",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_3,x=1,y=11,height=1,text="Facility Auth Key"}
    local key, _, censor = TextField{parent=net_c_3,x=1,y=12,max_len=64,value=ini_cfg.AuthKey,width=32,height=1,fg_bg=bw_fg_bg}

    local function censor_key(enable) censor(util.trinary(enable, "*", nil)) end

    local hide_key = CheckBox{parent=net_c_3,x=34,y=12,label="Hide",box_fg_bg=cpair(colors.lightBlue,colors.black),callback=censor_key}

    hide_key.set_value(true)
    censor_key(true)

    local key_err = TextBox{parent=net_c_3,x=8,y=14,height=1,width=35,text="Key must be at least 8 characters.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_auth()
        local v = key.get_value()
        if string.len(v) == 0 or string.len(v) >= 8 then
            tmp_cfg.AuthKey = key.get_value()
            main_pane.set_value(4)
            key_err.hide(true)
        else key_err.show() end
    end

    PushButton{parent=net_c_3,x=1,y=14,text="\x1b Back",callback=function()net_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_3,x=44,y=14,text="Next \x1a",callback=submit_auth,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    -- LOG CONFIG

    local log_c_1 = Div{parent=log_cfg,x=2,y=4,width=49}

    TextBox{parent=log_cfg,x=1,y=2,height=1,text=" Logging Configuration",fg_bg=cpair(colors.black,colors.pink)}

    TextBox{parent=log_c_1,x=1,y=1,height=1,text="Please configure logging below."}

    TextBox{parent=log_c_1,x=1,y=3,height=1,text="Log File Mode"}
    local mode = RadioButton{parent=log_c_1,x=1,y=4,default=ini_cfg.LogMode+1,options={"Append on Startup","Replace on Startup"},callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.pink}

    TextBox{parent=log_c_1,x=1,y=7,height=1,text="Log File Path"}
    local path = TextField{parent=log_c_1,x=1,y=8,width=49,height=1,value=ini_cfg.LogPath,max_len=128,fg_bg=bw_fg_bg}

    local en_dbg = CheckBox{parent=log_c_1,x=1,y=10,default=ini_cfg.LogDebug,label="Enable Logging Debug Messages",box_fg_bg=cpair(colors.pink,colors.black)}
    TextBox{parent=log_c_1,x=3,y=11,height=2,text="This results in much larger log files. It is best to only use this when there is a problem.",fg_bg=g_lg_fg_bg}

    local path_err = TextBox{parent=log_c_1,x=8,y=14,height=1,width=35,text="Please provide a log file path.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_log()
        if path.get_value() ~= "" then
            path_err.hide(true)
            tmp_cfg.LogMode = mode.get_value() - 1
            tmp_cfg.LogPath = path.get_value()
            tmp_cfg.LogDebug = en_dbg.get_value()
            tool_ctl.gen_summary(tmp_cfg)
            tool_ctl.viewing_config = false
            tool_ctl.importing_legacy = false
            tool_ctl.settings_apply.show()
            main_pane.set_value(5)
        else path_err.show() end
    end

    local function back_from_log()
        if tmp_cfg.Networked then main_pane.set_value(3) else main_pane.set_value(2) end
    end

    PushButton{parent=log_c_1,x=1,y=14,text="\x1b Back",callback=back_from_log,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=log_c_1,x=44,y=14,text="Next \x1a",callback=submit_log,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    -- SUMMARY OF CHANGES

    local sum_c_1 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_2 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_3 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_4 = Div{parent=summary,x=2,y=4,width=49}

    local sum_pane = MultiPane{parent=summary,x=1,y=4,panes={sum_c_1,sum_c_2,sum_c_3,sum_c_4}}

    TextBox{parent=summary,x=1,y=2,height=1,text=" Summary",fg_bg=cpair(colors.black,colors.green)}

    local setting_list = ListBox{parent=sum_c_1,x=1,y=1,height=12,width=51,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function back_from_settings()
        if tool_ctl.viewing_config or tool_ctl.importing_legacy then
            main_pane.set_value(1)
            tool_ctl.viewing_config = false
            tool_ctl.importing_legacy = false
            tool_ctl.settings_apply.show()
        else
            main_pane.set_value(4)
        end
    end

    ---@param element graphics_element
    ---@param data any
    local function try_set(element, data)
        if data ~= nil then element.set_value(data) end
    end

    local function save_and_continue()
        -- for k, v in pairs(tmp_cfg) do settings.set(k, v) end

        -- if settings.save("reactor-plc.settings") then
        --     load_settings(settings_cfg, true)
        --     load_settings(ini_cfg)

        --     try_set(networked, ini_cfg.Networked)
        --     try_set(u_id, ini_cfg.UnitID)
        --     try_set(en_em_cool, ini_cfg.EmerCoolEnable)
        --     try_set(side, side_to_idx(ini_cfg.EmerCoolSide))
        --     try_set(bundled, ini_cfg.EmerCoolColor ~= nil)
        --     if ini_cfg.EmerCoolColor ~= nil then try_set(color, color_to_idx(ini_cfg.EmerCoolColor)) end
        --     try_set(svr_chan, ini_cfg.SVR_Channel)
        --     try_set(plc_chan, ini_cfg.PLC_Channel)
        --     try_set(timeout, ini_cfg.ConnTimeout)
        --     try_set(range, ini_cfg.TrustedRange)
        --     try_set(key, ini_cfg.AuthKey)
        --     try_set(mode, ini_cfg.LogMode)
        --     try_set(path, ini_cfg.LogPath)
        --     try_set(en_dbg, ini_cfg.LogDebug)

        --     tool_ctl.view_cfg.enable()

        --     if tool_ctl.importing_legacy then
        --         tool_ctl.importing_legacy = false
        --         sum_pane.set_value(3)
        --     else
        --         sum_pane.set_value(2)
        --     end
        -- else
        --     sum_pane.set_value(4)
        -- end
    end

    PushButton{parent=sum_c_1,x=1,y=14,text="\x1b Back",callback=back_from_settings,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.show_key_btn = PushButton{parent=sum_c_1,x=8,y=14,min_width=17,text="Unhide Auth Key",callback=function()tool_ctl.show_auth_key()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    tool_ctl.settings_apply = PushButton{parent=sum_c_1,x=43,y=14,min_width=7,text="Apply",callback=save_and_continue,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_2,x=1,y=1,height=1,text="Settings saved!"}

    local function go_home()
        main_pane.set_value(1)
        svr_pane.set_value(1)
        net_pane.set_value(1)
        sum_pane.set_value(1)
    end

    PushButton{parent=sum_c_2,x=1,y=14,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_2,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_3,x=1,y=1,height=2,text="The old config.lua file will now be deleted, then the configurator will exit."}

    local function delete_legacy()
        fs.delete("/supervisor/config.lua")
        exit()
    end

    PushButton{parent=sum_c_3,x=1,y=14,min_width=8,text="Cancel",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_3,x=44,y=14,min_width=6,text="OK",callback=delete_legacy,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_4,x=1,y=1,height=5,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=sum_c_4,x=1,y=14,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_4,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    -- CONFIG CHANGE LOG

    local cl = Div{parent=changelog,x=2,y=4,width=49}

    TextBox{parent=changelog,x=1,y=2,height=1,text=" Config Change Log",fg_bg=bw_fg_bg}

    local c_log = ListBox{parent=cl,x=1,y=1,height=12,width=51,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    for _, change in ipairs(changes) do
        TextBox{parent=c_log,text=change[1],height=1,fg_bg=bw_fg_bg}
        for _, v in ipairs(change[2]) do
            local e = Div{parent=c_log,height=#util.strwrap(v,46)}
            TextBox{parent=e,y=1,x=1,text="- ",height=1,fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=e,y=1,x=3,text=v,height=e.get_height(),fg_bg=cpair(colors.gray,colors.white)}
        end
    end

    PushButton{parent=cl,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    -- set tool functions now that we have the elements

    -- load a legacy config file
    function tool_ctl.load_legacy()
        local config = require("reactor-plc.config")

        tmp_cfg.Networked = config.NETWORKED
        tmp_cfg.UnitID = config.REACTOR_ID
        tmp_cfg.EmerCoolEnable = type(config.EMERGENCY_COOL) == "table"

        if tmp_cfg.EmerCoolEnable then
            tmp_cfg.EmerCoolSide = config.EMERGENCY_COOL.side
            tmp_cfg.EmerCoolColor = config.EMERGENCY_COOL.color
        else
            tmp_cfg.EmerCoolSide = nil
            tmp_cfg.EmerCoolColor = nil
        end

        tmp_cfg.SVR_Channel = config.SVR_CHANNEL
        tmp_cfg.PLC_Channel = config.PLC_CHANNEL
        tmp_cfg.ConnTimeout = config.COMMS_TIMEOUT
        tmp_cfg.TrustedRange = config.TRUSTED_RANGE
        tmp_cfg.AuthKey = config.AUTH_KEY or ""
        tmp_cfg.LogMode = config.LOG_MODE
        tmp_cfg.LogPath = config.LOG_PATH
        tmp_cfg.LogDebug = config.LOG_DEBUG or false

        tool_ctl.gen_summary(tmp_cfg)
        sum_pane.set_value(1)
        main_pane.set_value(5)
        tool_ctl.importing_legacy = true
    end

    -- expose the auth key on the summary page
    function tool_ctl.show_auth_key()
        tool_ctl.show_key_btn.disable()
        tool_ctl.auth_key_textbox.set_value(tool_ctl.auth_key_value)
    end

    -- generate the summary list
    ---@param cfg plc_config
    function tool_ctl.gen_summary(cfg)
        setting_list.remove_all()

        local alternate = false
        local inner_width = setting_list.get_width() - 1

        tool_ctl.show_key_btn.enable()
        tool_ctl.auth_key_value = cfg.AuthKey or "" -- to show auth key

        for i = 1, #fields do
            local f = fields[i]
            local height = 1
            local label_w = string.len(f[2])
            local val_max_w = (inner_width - label_w) + 1
            local raw = cfg[f[1]]
            local val = util.strval(raw)

            if f[1] == "AuthKey" then val = string.rep("*", string.len(val)) end
            if f[1] == "LogMode" then val = util.trinary(raw == log.MODE.APPEND, "append", "replace") end
            if f[1] == "EmerCoolColor" and raw ~= nil then val = rsio.color_name(raw) end
            if val == "nil" then val = "<not set>" end

            local c = util.trinary(alternate, g_lg_fg_bg, cpair(colors.gray,colors.white))
            alternate = not alternate

            if string.len(val) > val_max_w then
                local lines = util.strwrap(val, inner_width)
                height = #lines + 1
            end

            local line = Div{parent=setting_list,height=height,fg_bg=c}
            TextBox{parent=line,text=f[2],width=string.len(f[2]),fg_bg=cpair(colors.black,line.get_fg_bg().bkg)}

            local textbox
            if height > 1 then
                textbox = TextBox{parent=line,x=1,y=2,text=val,height=height-1,alignment=LEFT}
            else
                textbox = TextBox{parent=line,x=label_w+1,y=1,text=val,alignment=RIGHT}
            end

            if f[1] == "AuthKey" then tool_ctl.auth_key_textbox = textbox end
        end
    end
end

-- reset terminal screen
local function reset_term()
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

-- run the supervisor configurator
---@param ask_config? boolean indicate if this is being called by the supervisor startup app due to an invalid configuration
function configurator.configure(ask_config)
    tool_ctl.ask_config = ask_config == true

    load_settings(settings_cfg, true)
    tool_ctl.has_config = load_settings(ini_cfg)

    reset_term()

    -- set overridden colors
    for i = 1, #style.colors do
        term.setPaletteColor(style.colors[i].c, style.colors[i].hex)
    end

    local status, error = pcall(function ()
        local display = DisplayBox{window=term.current(),fg_bg=style.root}
        config_view(display)

        while true do
            local event, param1, param2, param3 = util.pull_event()

            -- handle event
            if event == "timer" then
                tcd.handle(param1)
            elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or event == "double_click" then
                local m_e = core.events.new_mouse_event(event, param1, param2, param3)
                if m_e then display.handle_mouse(m_e) end
            elseif event == "char" or event == "key" or event == "key_up" then
                local k_e = core.events.new_key_event(event, param1, param2)
                if k_e then display.handle_key(k_e) end
            elseif event == "paste" then
                display.handle_paste(param1)
            end

            if event == "terminate" then return end
        end
    end)

    -- restore colors
    for i = 1, #style.colors do
        local r, g, b = term.nativePaletteColor(style.colors[i].c)
        term.setPaletteColor(style.colors[i].c, r, g, b)
    end

    reset_term()
    if not status then
        println("configurator error: " .. error)
    end

    return status, error
end

return configurator
