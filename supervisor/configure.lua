--
-- Configuration GUI
--

local log         = require("scada-common.log")
local tcd         = require("scada-common.tcd")
local util        = require("scada-common.util")

local core        = require("graphics.core")
local themes      = require("graphics.themes")

local DisplayBox  = require("graphics.elements.displaybox")
local Div         = require("graphics.elements.div")
local ListBox     = require("graphics.elements.listbox")
local MultiPane   = require("graphics.elements.multipane")
local TextBox     = require("graphics.elements.textbox")

local CheckBox    = require("graphics.elements.controls.checkbox")
local PushButton  = require("graphics.elements.controls.push_button")
local Radio2D     = require("graphics.elements.controls.radio_2d")
local RadioButton = require("graphics.elements.controls.radio_button")

local NumberField = require("graphics.elements.form.number_field")
local TextField   = require("graphics.elements.form.text_field")

local IndLight    = require("graphics.elements.indicators.light")

local println = util.println
local tri = util.trinary

local cpair = core.cpair

local LEFT = core.ALIGN.LEFT
local CENTER = core.ALIGN.CENTER
local RIGHT = core.ALIGN.RIGHT

-- changes to the config data/format to let the user know
local changes = {
    { "v1.2.12", { "Added front panel UI theme", "Added color accessibility modes" } },
    { "v1.3.2", { "Added standard with black off state color mode", "Added blue indicator color modes" } }
}

---@class svr_configurator
local configurator = {}

local style = {}

style.root = cpair(colors.black, colors.lightGray)
style.header = cpair(colors.white, colors.gray)

style.colors = themes.smooth_stone.colors

local bw_fg_bg = cpair(colors.black, colors.white)
local g_lg_fg_bg = cpair(colors.gray, colors.lightGray)
local nav_fg_bg = bw_fg_bg
local btn_act_fg_bg = cpair(colors.white, colors.gray)

---@class _svr_cfg_tool_ctl
local tool_ctl = {
    ask_config = false,
    has_config = false,
    viewing_config = false,
    importing_legacy = false,
    jumped_to_color = false,

    view_cfg = nil,         ---@type graphics_element
    color_cfg = nil,        ---@type graphics_element
    color_next = nil,       ---@type graphics_element
    color_apply = nil,      ---@type graphics_element
    settings_apply = nil,   ---@type graphics_element

    gen_summary = nil,      ---@type function
    show_current_cfg = nil, ---@type function
    load_legacy = nil,      ---@type function

    show_auth_key = nil,    ---@type function
    show_key_btn = nil,     ---@type graphics_element
    auth_key_textbox = nil, ---@type graphics_element
    auth_key_value = "",

    cooling_elems = {},
    tank_elems = {},

    vis_ftanks = {},
    vis_utanks = {}
}

---@class svr_config
local tmp_cfg = {
    UnitCount = 1,
    CoolingConfig = {},
    FacilityTankMode = 0,
    FacilityTankDefs = {},
    ExtChargeIdling = false,
    SVR_Channel = nil,  ---@type integer
    PLC_Channel = nil,  ---@type integer
    RTU_Channel = nil,  ---@type integer
    CRD_Channel = nil,  ---@type integer
    PKT_Channel = nil,  ---@type integer
    PLC_Timeout = nil,  ---@type number
    RTU_Timeout = nil,  ---@type number
    CRD_Timeout = nil,  ---@type number
    PKT_Timeout = nil,  ---@type number
    TrustedRange = nil, ---@type number
    AuthKey = nil,      ---@type string|nil
    LogMode = 0,
    LogPath = "",
    LogDebug = false,
    FrontPanelTheme = 1,
    ColorMode = 1
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
    { "ExtChargeIdling", "Extended Charge Idling", false },
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
    { "LogDebug", "Log Debug Messages", false },
    { "FrontPanelTheme", "Front Panel Theme", themes.FP_THEME.SANDSTONE },
    { "ColorMode", "Color Mode", themes.COLOR_MODE.STANDARD }
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
    local clr_cfg = Div{parent=root_pane_div,x=1,y=1}
    local summary = Div{parent=root_pane_div,x=1,y=1}
    local changelog = Div{parent=root_pane_div,x=1,y=1}
    local import_err = Div{parent=root_pane_div,x=1,y=1}

    local main_pane = MultiPane{parent=root_pane_div,x=1,y=1,panes={main_page,svr_cfg,net_cfg,log_cfg,clr_cfg,summary,changelog,import_err}}

    -- Main Page

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
        main_pane.set_value(6)
    end

    if fs.exists("/supervisor/config.lua") then
        PushButton{parent=main_page,x=2,y=y_start,min_width=28,text="Import Legacy 'config.lua'",callback=function()tool_ctl.load_legacy()end,fg_bg=cpair(colors.black,colors.cyan),active_fg_bg=btn_act_fg_bg}
        y_start = y_start + 2
    end

    PushButton{parent=main_page,x=2,y=y_start,min_width=18,text="Configure System",callback=function()main_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    tool_ctl.view_cfg = PushButton{parent=main_page,x=2,y=y_start+2,min_width=20,text="View Configuration",callback=view_config,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}

    local function jump_color()
        tool_ctl.jumped_to_color = true
        tool_ctl.color_next.hide(true)
        tool_ctl.color_apply.show()
        main_pane.set_value(5)
    end

    PushButton{parent=main_page,x=2,y=17,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
    tool_ctl.color_cfg = PushButton{parent=main_page,x=23,y=17,min_width=15,text="Color Options",callback=jump_color,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    PushButton{parent=main_page,x=39,y=17,min_width=12,text="Change Log",callback=function()main_pane.set_value(7)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    if not tool_ctl.has_config then
        tool_ctl.view_cfg.disable()
        tool_ctl.color_cfg.disable()
    end

    --#region Facility

    local svr_c_1 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_2 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_3 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_4 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_5 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_6 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_7 = Div{parent=svr_cfg,x=2,y=4,width=49}

    local svr_pane = MultiPane{parent=svr_cfg,x=1,y=4,panes={svr_c_1,svr_c_2,svr_c_3,svr_c_4,svr_c_5,svr_c_6,svr_c_7}}

    TextBox{parent=svr_cfg,x=1,y=2,height=1,text=" Facility Configuration",fg_bg=cpair(colors.black,colors.yellow)}

    TextBox{parent=svr_c_1,x=1,y=1,height=3,text="Please enter the number of reactors you have, also referred to as reactor units or 'units' for short. A maximum of 4 is currently supported."}
    local num_units = NumberField{parent=svr_c_1,x=1,y=5,width=5,max_chars=2,default=ini_cfg.UnitCount,min=1,max=4,fg_bg=bw_fg_bg}
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

    PushButton{parent=svr_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_1,x=44,y=14,text="Next \x1a",callback=submit_num_units,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_2,x=1,y=1,height=4,text="Please provide the reactor cooling configuration below. This includes the number of turbines, boilers, and if that reactor has a connection to a dynamic tank for emergency coolant."}
    TextBox{parent=svr_c_2,x=1,y=6,height=1,text="UNIT    TURBINES   BOILERS   HAS TANK CONNECTION?",fg_bg=g_lg_fg_bg}

    for i = 1, 4 do
        local num_t, num_b, has_t = 1, 0, false

        if ini_cfg.CoolingConfig[i] then
            local conf = ini_cfg.CoolingConfig[i]
            if util.is_int(conf.TurbineCount) then num_t = math.min(3, math.max(1, conf.TurbineCount or 1)) end
            if util.is_int(conf.BoilerCount) then num_b = math.min(2, math.max(0, conf.BoilerCount or 0)) end
            has_t = conf.TankConnection == true
        end

        local line = Div{parent=svr_c_2,x=1,y=7+i,height=1}

        TextBox{parent=line,text="Unit "..i,width=6}
        local turbines = NumberField{parent=line,x=9,y=1,width=5,max_chars=2,default=num_t,min=1,max=3,fg_bg=bw_fg_bg}
        local boilers = NumberField{parent=line,x=20,y=1,width=5,max_chars=2,default=num_b,min=0,max=2,fg_bg=bw_fg_bg}
        local tank = CheckBox{parent=line,x=30,y=1,label="Is Connected",default=has_t,box_fg_bg=cpair(colors.yellow,colors.black)}

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

            tmp_cfg.CoolingConfig = {}
            for i = 1, tmp_cfg.UnitCount do
                local conf = tool_ctl.cooling_elems[i]
                tmp_cfg.CoolingConfig[i] = { TurbineCount = tonumber(conf.turbines.get_value()), BoilerCount = tonumber(conf.boilers.get_value()), TankConnection = conf.tank.get_value() }
                if conf.tank.get_value() then any_has_tank = true end
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

            if any_has_tank then svr_pane.set_value(3) else main_pane.set_value(3) end
        end
    end

    PushButton{parent=svr_c_2,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_2,x=44,y=14,text="Next \x1a",callback=submit_cooling,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_3,x=1,y=1,height=6,text="You have set one or more of your units to use dynamic tanks for emergency coolant. You have two paths for configuration. The first is to assign dynamic tanks to reactor units; one tank per reactor, only connected to that reactor. RTU configurations must also assign it as such."}
    TextBox{parent=svr_c_3,x=1,y=8,height=3,text="Alternatively, you can configure them as facility tanks to connect to multiple reactor units. These can intermingle with unit-specific tanks."}

    local en_fac_tanks = CheckBox{parent=svr_c_3,x=1,y=12,label="Use Facility Dynamic Tanks",default=ini_cfg.FacilityTankMode>0,box_fg_bg=cpair(colors.yellow,colors.black)}

    local function submit_en_fac_tank()
        if en_fac_tanks.get_value() then
            svr_pane.set_value(4)
            tmp_cfg.FacilityTankMode = util.trinary(tmp_cfg.FacilityTankMode == 0, 1, math.min(8, math.max(1, ini_cfg.FacilityTankMode)))
        else
            tmp_cfg.FacilityTankMode = 0
            tmp_cfg.FacilityTankDefs = {}
            svr_pane.set_value(7)
        end
    end

    PushButton{parent=svr_c_3,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_3,x=44,y=14,text="Next \x1a",callback=submit_en_fac_tank,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_4,x=1,y=1,height=4,text="Please set unit connections to dynamic tanks, selecting at least one facility tank. The layout for facility tanks will be configured next."}

    for i = 1, 4 do
        local val = math.max(1, ini_cfg.FacilityTankDefs[i] or 2)
        local div = Div{parent=svr_c_4,x=1,y=3+(2*i),height=2}

        TextBox{parent=div,x=1,y=1,width=33,height=1,text="Unit "..i.." will be connected to..."}
        TextBox{parent=div,x=6,y=2,width=3,height=1,text="..."}
        local tank_opt = Radio2D{parent=div,x=9,y=2,rows=1,columns=2,default=val,options={"its own Unit Tank","a Facility Tank"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
        local no_tank = TextBox{parent=div,x=9,y=2,width=34,height=1,text="no tank (as you set two steps ago)",fg_bg=cpair(colors.gray,colors.lightGray),hidden=true}

        tool_ctl.tank_elems[i] = { div = div, tank_opt = tank_opt, no_tank = no_tank }
    end

    local tank_err = TextBox{parent=svr_c_4,x=8,y=14,height=1,width=33,text="You selected no facility tanks.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function hide_fconn(i)
        if i > 1 then tool_ctl.vis_ftanks[i].pipe_conn.hide(true)
        else tool_ctl.vis_ftanks[i].line.hide(true) end
    end

    local function submit_tank_defs()
        local any_fac = false

        tmp_cfg.FacilityTankDefs = {}
        for i = 1, tmp_cfg.UnitCount do
            local def

            if tmp_cfg.CoolingConfig[i].TankConnection then
                def = tool_ctl.tank_elems[i].tank_opt.get_value()
                any_fac = any_fac or (def == 2)
            else def = 0 end

            if def == 1 then
                tool_ctl.vis_utanks[i].line.show()
                tool_ctl.vis_utanks[i].label.set_value("Tank U" .. i)
                hide_fconn(i)
            else
                if def == 2 then
                    if i > 1 then tool_ctl.vis_ftanks[i].pipe_conn.show()
                    else tool_ctl.vis_ftanks[i].line.show() end
                else hide_fconn(i) end
                tool_ctl.vis_utanks[i].line.hide(true)
            end

            tmp_cfg.FacilityTankDefs[i] = def
        end

        for i = tmp_cfg.UnitCount + 1, 4 do
            tool_ctl.vis_utanks[i].line.hide(true)
        end

        tool_ctl.vis_draw(tmp_cfg.FacilityTankMode)

        if any_fac then
            tank_err.hide(true)
            svr_pane.set_value(5)
        else tank_err.show() end
    end

    PushButton{parent=svr_c_4,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_4,x=44,y=14,text="Next \x1a",callback=submit_tank_defs,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_5,x=1,y=1,height=1,text="Please select your dynamic tank layout."}
    TextBox{parent=svr_c_5,x=12,y=3,height=1,text="Facility Tanks             Unit Tanks",fg_bg=g_lg_fg_bg}

    --#region Tank Layout Visualizer

    local pipe_cpair = cpair(colors.blue,colors.lightGray)

    local vis = Div{parent=svr_c_5,x=14,y=5,height=7}

    local vis_unit_list = TextBox{parent=vis,x=15,y=1,width=6,height=7,text="Unit 1\n\nUnit 2\n\nUnit 3\n\nUnit 4"}

    -- draw unit tanks and their pipes
    for i = 1, 4 do
        local line = Div{parent=vis,x=22,y=(i*2)-1,width=13,height=1}
        TextBox{parent=line,width=5,height=1,text=string.rep("\x8c",5),fg_bg=pipe_cpair}
        local label = TextBox{parent=line,x=7,y=1,width=7,height=1,text="Tank ?"}
        tool_ctl.vis_utanks[i] = { line = line, label = label }
    end

    -- draw facility tank connections

    local ftank_1 = Div{parent=vis,x=1,y=1,width=13,height=1}
    TextBox{parent=ftank_1,width=7,height=1,text="Tank F1"}
    tool_ctl.vis_ftanks[1] = {
        line = ftank_1, pipe_direct = TextBox{parent=ftank_1,x=9,y=1,width=5,text=string.rep("\x8c",5),fg_bg=pipe_cpair}
    }

    for i = 2, 4 do
        local line = Div{parent=vis,x=1,y=(i-1)*2,width=13,height=2}
        local pipe_conn = TextBox{parent=line,x=13,y=2,width=1,height=1,text="\x8c",fg_bg=pipe_cpair}
        local pipe_chain = TextBox{parent=line,x=12,y=1,width=1,height=2,text="\x95\n\x8d",fg_bg=pipe_cpair}
        local pipe_direct = TextBox{parent=line,x=9,y=2,width=4,height=1,text="\x8c\x8c\x8c\x8c",fg_bg=pipe_cpair}
        local label = TextBox{parent=line,x=1,y=2,width=7,height=1,text=""}
        tool_ctl.vis_ftanks[i] = { line = line, pipe_conn = pipe_conn, pipe_chain = pipe_chain, pipe_direct = pipe_direct, label = label }
    end

    -- draw the pipe visualization
    ---@param mode integer pipe mode
    function tool_ctl.vis_draw(mode)
        -- is a facility tank connected to this unit
        ---@param i integer unit 1 - 4
        ---@return boolean connected
        local function is_ft(i) return tmp_cfg.FacilityTankDefs[i] == 2 end

        local u_text = ""
        for i = 1, tmp_cfg.UnitCount do
            u_text = u_text .. "Unit " .. i .. "\n\n"
        end

        vis_unit_list.set_value(u_text)

        local next_idx = 1

        if is_ft(1) then
            next_idx = 2

            if (mode == 1 and (is_ft(2) or is_ft(3) or is_ft(4))) or (mode == 2 and (is_ft(2) or is_ft(3))) or ((mode == 3 or mode == 5) and is_ft(2)) then
                tool_ctl.vis_ftanks[1].pipe_direct.set_value("\x8c\x8c\x8c\x9c\x8c")
            else
                tool_ctl.vis_ftanks[1].pipe_direct.set_value(string.rep("\x8c",5))
            end
        end

        local _2_12_need_passt = (mode == 1 and (is_ft(3) or is_ft(4))) or (mode == 2 and is_ft(3))
        local _2_46_need_chain = (mode == 4 and (is_ft(3) or is_ft(4))) or (mode == 6 and is_ft(3))

        if is_ft(2) then
            tool_ctl.vis_ftanks[2].label.set_value("Tank F" .. next_idx)

            if (mode < 4 or mode == 5) and is_ft(1) then
                tool_ctl.vis_ftanks[2].label.hide(true)
                tool_ctl.vis_ftanks[2].pipe_direct.hide(true)
                if _2_12_need_passt then
                    tool_ctl.vis_ftanks[2].pipe_chain.set_value("\x95\n\x9d")
                else
                    tool_ctl.vis_ftanks[2].pipe_chain.set_value("\x95\n\x8d")
                end
                tool_ctl.vis_ftanks[2].pipe_chain.show()
            else
                tool_ctl.vis_ftanks[2].label.show()
                next_idx = next_idx + 1

                tool_ctl.vis_ftanks[2].pipe_chain.hide(true)
                if _2_12_need_passt or _2_46_need_chain then
                    tool_ctl.vis_ftanks[2].pipe_direct.set_value("\x8c\x8c\x8c\x9c")
                else
                    tool_ctl.vis_ftanks[2].pipe_direct.set_value("\x8c\x8c\x8c\x8c")
                end
                tool_ctl.vis_ftanks[2].pipe_direct.show()
            end

            tool_ctl.vis_ftanks[2].line.show()
        elseif is_ft(1) and _2_12_need_passt then
            tool_ctl.vis_ftanks[2].label.hide(true)
            tool_ctl.vis_ftanks[2].pipe_direct.hide(true)
            tool_ctl.vis_ftanks[2].pipe_chain.set_value("\x95\n\x95")
            tool_ctl.vis_ftanks[2].pipe_chain.show()
            tool_ctl.vis_ftanks[2].line.show()
        else
            tool_ctl.vis_ftanks[2].line.hide(true)
        end

        if is_ft(3) then
            tool_ctl.vis_ftanks[3].label.set_value("Tank F" .. next_idx)

            if (mode < 3 and (is_ft(1) or is_ft(2))) or ((mode == 4 or mode == 6) and is_ft(2)) then
                tool_ctl.vis_ftanks[3].label.hide(true)
                tool_ctl.vis_ftanks[3].pipe_direct.hide(true)
                if (mode == 1 or mode == 4) and is_ft(4) then
                    tool_ctl.vis_ftanks[3].pipe_chain.set_value("\x95\n\x9d")
                else
                    tool_ctl.vis_ftanks[3].pipe_chain.set_value("\x95\n\x8d")
                end
                tool_ctl.vis_ftanks[3].pipe_chain.show()
            else
                tool_ctl.vis_ftanks[3].label.show()
                next_idx = next_idx + 1

                tool_ctl.vis_ftanks[3].pipe_chain.hide(true)
                if (mode == 1 or mode == 3 or mode == 4 or mode == 7) and is_ft(4) then
                    tool_ctl.vis_ftanks[3].pipe_direct.set_value("\x8c\x8c\x8c\x9c")
                else
                    tool_ctl.vis_ftanks[3].pipe_direct.set_value("\x8c\x8c\x8c\x8c")
                end
                tool_ctl.vis_ftanks[3].pipe_direct.show()
            end

            tool_ctl.vis_ftanks[3].line.show()
        elseif (mode == 1 and is_ft(4) and (is_ft(1) or is_ft(2))) or (mode == 4 and is_ft(2) and is_ft(4)) then
            tool_ctl.vis_ftanks[3].label.hide(true)
            tool_ctl.vis_ftanks[3].pipe_direct.hide(true)
            tool_ctl.vis_ftanks[3].pipe_chain.set_value("\x95\n\x95")
            tool_ctl.vis_ftanks[3].pipe_chain.show()
            tool_ctl.vis_ftanks[3].line.show()
        else
            tool_ctl.vis_ftanks[3].line.hide(true)
        end

        if is_ft(4) then
            tool_ctl.vis_ftanks[4].label.set_value("Tank F" .. next_idx)

            if (mode == 1 and (is_ft(1) or is_ft(2) or is_ft(3))) or ((mode == 3 or mode == 7) and is_ft(3)) or (mode == 4 and (is_ft(2) or is_ft(3))) then
                tool_ctl.vis_ftanks[4].label.hide(true)
                tool_ctl.vis_ftanks[4].pipe_direct.hide(true)
                tool_ctl.vis_ftanks[4].pipe_chain.show()
            else
                tool_ctl.vis_ftanks[4].label.show()
                tool_ctl.vis_ftanks[4].pipe_chain.hide(true)
                tool_ctl.vis_ftanks[4].pipe_direct.show()
            end

            tool_ctl.vis_ftanks[4].line.show()
        else
            tool_ctl.vis_ftanks[4].line.hide(true)
        end
    end

    local tank_modes = { "Mode 1", "Mode 2", "Mode 3", "Mode 4", "Mode 5", "Mode 6", "Mode 7", "Mode 8" }
    local tank_mode = RadioButton{parent=svr_c_5,x=1,y=4,callback=tool_ctl.vis_draw,default=math.max(1,ini_cfg.FacilityTankMode),options=tank_modes,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow}

    --#endregion

    local function submit_mode()
        tmp_cfg.FacilityTankMode = tank_mode.get_value()
        svr_pane.set_value(7)
    end

    PushButton{parent=svr_c_5,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_5,x=44,y=14,text="Next \x1a",callback=submit_mode,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    PushButton{parent=svr_c_5,x=8,y=14,min_width=7,text="About",callback=function()svr_pane.set_value(6)end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_6,height=3,text="This visualization tool shows the pipe connections required for a particular dynamic tank configuration you have selected."}
    TextBox{parent=svr_c_6,y=5,height=4,text="Examples: A U2 tank should be configured on an RTU as the dynamic tank for unit #2. An F3 tank should be configured on an RTU as the #3 dynamic tank for the facility."}
    TextBox{parent=svr_c_6,y=10,height=3,text="Some modes may look the same if you are not using 4 total reactor units. The wiki has details. Modes that look the same will function the same.",fg_bg=g_lg_fg_bg}

    PushButton{parent=svr_c_6,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(5)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_7,height=6,text="Charge control provides automatic control to maintain an induction matrix charge level. In order to have smoother control, reactors that were activated will be held on at 0.01 mB/t for a short period before allowing them to turn off. This minimizes overshooting the charge target."}
    TextBox{parent=svr_c_7,y=8,height=3,text="You can extend this to a full minute to minimize reactors flickering on/off, but there may be more overshoot of the target."}

    local ext_idling = CheckBox{parent=svr_c_7,x=1,y=12,label="Enable Extended Idling",default=ini_cfg.ExtChargeIdling,box_fg_bg=cpair(colors.yellow,colors.black)}

    local function back_from_idling()
        svr_pane.set_value(util.trinary(tmp_cfg.FacilityTankMode == 0, 3, 5))
    end

    local function submit_idling()
        tmp_cfg.ExtChargeIdling = ext_idling.get_value()
        main_pane.set_value(3)
    end

    PushButton{parent=svr_c_7,x=1,y=14,text="\x1b Back",callback=back_from_idling,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_7,x=44,y=14,text="Next \x1a",callback=submit_idling,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Network

    local net_c_1 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_2 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_3 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_4 = Div{parent=net_cfg,x=2,y=4,width=49}

    local net_pane = MultiPane{parent=net_cfg,x=1,y=4,panes={net_c_1,net_c_2,net_c_3,net_c_4}}

    TextBox{parent=net_cfg,x=1,y=2,height=1,text=" Network Configuration",fg_bg=cpair(colors.black,colors.lightBlue)}

    TextBox{parent=net_c_1,x=1,y=1,height=1,text="Please set the network channels below."}
    TextBox{parent=net_c_1,x=1,y=3,height=4,text="Each of the 5 uniquely named channels must be the same for each device in this SCADA network. For multiplayer servers, it is recommended to not use the default channels.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=8,height=1,width=18,text="Supervisor Channel"}
    local svr_chan = NumberField{parent=net_c_1,x=21,y=8,width=7,default=ini_cfg.SVR_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=29,y=8,height=4,text="[SVR_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=9,height=1,width=11,text="PLC Channel"}
    local plc_chan = NumberField{parent=net_c_1,x=21,y=9,width=7,default=ini_cfg.PLC_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=29,y=9,height=4,text="[PLC_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=10,height=1,width=19,text="RTU Gateway Channel"}
    local rtu_chan = NumberField{parent=net_c_1,x=21,y=10,width=7,default=ini_cfg.RTU_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=29,y=10,height=4,text="[RTU_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=11,height=1,width=19,text="Coordinator Channel"}
    local crd_chan = NumberField{parent=net_c_1,x=21,y=11,width=7,default=ini_cfg.CRD_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=29,y=11,height=4,text="[CRD_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=12,height=1,width=14,text="Pocket Channel"}
    local pkt_chan = NumberField{parent=net_c_1,x=21,y=12,width=7,default=ini_cfg.PKT_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=29,y=12,height=4,text="[PKT_CHANNEL]",fg_bg=g_lg_fg_bg}

    local chan_err = TextBox{parent=net_c_1,x=8,y=14,height=1,width=35,text="Please set all channels.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_channels()
        local svr_c, plc_c, rtu_c = tonumber(svr_chan.get_value()), tonumber(plc_chan.get_value()), tonumber(rtu_chan.get_value())
        local crd_c, pkt_c = tonumber(crd_chan.get_value()), tonumber(pkt_chan.get_value())
        if svr_c ~= nil and plc_c ~= nil and rtu_c ~= nil and crd_c ~= nil and pkt_c ~= nil then
            tmp_cfg.SVR_Channel, tmp_cfg.PLC_Channel, tmp_cfg.RTU_Channel = svr_c, plc_c, rtu_c
            tmp_cfg.CRD_Channel, tmp_cfg.PKT_Channel = crd_c, pkt_c
            net_pane.set_value(2)
            chan_err.hide(true)
        else chan_err.show() end
    end

    PushButton{parent=net_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_1,x=44,y=14,text="Next \x1a",callback=submit_channels,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_2,x=1,y=1,height=1,text="Please set the connection timeouts below."}
    TextBox{parent=net_c_2,x=1,y=3,height=4,text="You generally should not need to modify these. On slow servers, you can try to increase this to make the system wait longer before assuming a disconnection. The default for all is 5 seconds.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_2,x=1,y=8,height=1,width=11,text="PLC Timeout"}
    local plc_timeout = NumberField{parent=net_c_2,x=21,y=8,width=7,default=ini_cfg.PLC_Timeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=net_c_2,x=1,y=9,height=1,width=19,text="RTU Gateway Timeout"}
    local rtu_timeout = NumberField{parent=net_c_2,x=21,y=9,width=7,default=ini_cfg.RTU_Timeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=net_c_2,x=1,y=10,height=1,width=19,text="Coordinator Timeout"}
    local crd_timeout = NumberField{parent=net_c_2,x=21,y=10,width=7,default=ini_cfg.CRD_Timeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=net_c_2,x=1,y=11,height=1,width=14,text="Pocket Timeout"}
    local pkt_timeout = NumberField{parent=net_c_2,x=21,y=11,width=7,default=ini_cfg.PKT_Timeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=net_c_2,x=29,y=8,height=4,width=7,text="seconds\nseconds\nseconds\nseconds",fg_bg=g_lg_fg_bg}

    local ct_err = TextBox{parent=net_c_2,x=8,y=14,height=1,width=35,text="Please set all connection timeouts.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_timeouts()
        local plc_cto, rtu_cto, crd_cto, pkt_cto = tonumber(plc_timeout.get_value()), tonumber(rtu_timeout.get_value()), tonumber(crd_timeout.get_value()), tonumber(pkt_timeout.get_value())
        if plc_cto ~= nil and rtu_cto ~= nil and crd_cto ~= nil and pkt_cto ~= nil then
            tmp_cfg.PLC_Timeout, tmp_cfg.RTU_Timeout, tmp_cfg.CRD_Timeout, tmp_cfg.PKT_Timeout = plc_cto, rtu_cto, crd_cto, pkt_cto
            net_pane.set_value(3)
            ct_err.hide(true)
        else ct_err.show() end
    end

    PushButton{parent=net_c_2,x=1,y=14,text="\x1b Back",callback=function()net_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_2,x=44,y=14,text="Next \x1a",callback=submit_timeouts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_3,x=1,y=1,height=1,text="Please set the trusted range below."}
    TextBox{parent=net_c_3,x=1,y=3,height=3,text="Setting this to a value larger than 0 prevents connections with devices that many meters (blocks) away in any direction.",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_3,x=1,y=7,height=2,text="This is optional. You can disable this functionality by setting the value to 0.",fg_bg=g_lg_fg_bg}

    local range = NumberField{parent=net_c_3,x=1,y=10,width=10,default=ini_cfg.TrustedRange,min=0,max_chars=20,allow_decimal=true,fg_bg=bw_fg_bg}

    local tr_err = TextBox{parent=net_c_3,x=8,y=14,height=1,width=35,text="Please set the trusted range.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_tr()
        local range_val = tonumber(range.get_value())
        if range_val ~= nil then
            tmp_cfg.TrustedRange = range_val
            net_pane.set_value(4)
            tr_err.hide(true)
        else tr_err.show() end
    end

    PushButton{parent=net_c_3,x=1,y=14,text="\x1b Back",callback=function()net_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_3,x=44,y=14,text="Next \x1a",callback=submit_tr,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_4,x=1,y=1,height=2,text="Optionally, set the facility authentication key below. Do NOT use one of your passwords."}
    TextBox{parent=net_c_4,x=1,y=4,height=6,text="This enables verifying that messages are authentic, so it is intended for security on multiplayer servers. All devices on the same network MUST use the same key if any device has a key. This does result in some extra compution (can slow things down).",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_4,x=1,y=11,height=1,text="Facility Auth Key"}
    local key, _, censor = TextField{parent=net_c_4,x=1,y=12,max_len=64,value=ini_cfg.AuthKey,width=32,height=1,fg_bg=bw_fg_bg}

    local function censor_key(enable) censor(util.trinary(enable, "*", nil)) end

    local hide_key = CheckBox{parent=net_c_4,x=34,y=12,label="Hide",box_fg_bg=cpair(colors.lightBlue,colors.black),callback=censor_key}

    hide_key.set_value(true)
    censor_key(true)

    local key_err = TextBox{parent=net_c_4,x=8,y=14,height=1,width=35,text="Key must be at least 8 characters.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_auth()
        local v = key.get_value()
        if string.len(v) == 0 or string.len(v) >= 8 then
            tmp_cfg.AuthKey = key.get_value()
            main_pane.set_value(4)
            key_err.hide(true)
        else key_err.show() end
    end

    PushButton{parent=net_c_4,x=1,y=14,text="\x1b Back",callback=function()net_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_4,x=44,y=14,text="Next \x1a",callback=submit_auth,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Logging

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
            tool_ctl.color_apply.hide(true)
            tool_ctl.color_next.show()
            main_pane.set_value(5)
        else path_err.show() end
    end

    PushButton{parent=log_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=log_c_1,x=44,y=14,text="Next \x1a",callback=submit_log,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Color Options

    local clr_c_1 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_2 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_3 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_4 = Div{parent=clr_cfg,x=2,y=4,width=49}

    local clr_pane = MultiPane{parent=clr_cfg,x=1,y=4,panes={clr_c_1,clr_c_2,clr_c_3,clr_c_4}}

    TextBox{parent=clr_cfg,x=1,y=2,height=1,text=" Color Configuration",fg_bg=cpair(colors.black,colors.magenta)}

    TextBox{parent=clr_c_1,x=1,y=1,height=2,text="Here you can select the color theme for the front panel."}
    TextBox{parent=clr_c_1,x=1,y=4,height=2,text="Click 'Accessibility' below to access colorblind assistive options.",fg_bg=g_lg_fg_bg}

    TextBox{parent=clr_c_1,x=1,y=7,height=1,text="Front Panel Theme"}
    local fp_theme = RadioButton{parent=clr_c_1,x=1,y=8,default=ini_cfg.FrontPanelTheme,options=themes.FP_THEME_NAMES,callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.magenta}

    TextBox{parent=clr_c_2,x=1,y=1,height=6,text="This system uses color heavily to distinguish ok and not, with some indicators using many colors. By selecting a mode below, indicators will change as shown. For non-standard modes, indicators with more than two colors will be split up."}

    TextBox{parent=clr_c_2,x=21,y=7,height=1,text="Preview"}
    local _ = IndLight{parent=clr_c_2,x=21,y=8,label="Good",colors=cpair(colors.black,colors.green)}
    _ = IndLight{parent=clr_c_2,x=21,y=9,label="Warning",colors=cpair(colors.black,colors.yellow)}
    _ = IndLight{parent=clr_c_2,x=21,y=10,label="Bad",colors=cpair(colors.black,colors.red)}
    local b_off = IndLight{parent=clr_c_2,x=21,y=11,label="Off",colors=cpair(colors.black,colors.black),hidden=true}
    local g_off = IndLight{parent=clr_c_2,x=21,y=11,label="Off",colors=cpair(colors.gray,colors.gray),hidden=true}

    local function recolor(value)
        local c = themes.smooth_stone.color_modes[value]

        if value == themes.COLOR_MODE.STANDARD or value == themes.COLOR_MODE.BLUE_IND then
            b_off.hide()
            g_off.show()
        else
            g_off.hide()
            b_off.show()
        end

        if #c == 0 then
            for i = 1, #style.colors do term.setPaletteColor(style.colors[i].c, style.colors[i].hex) end
        else
            term.setPaletteColor(colors.green, c[1].hex)
            term.setPaletteColor(colors.yellow, c[2].hex)
            term.setPaletteColor(colors.red, c[3].hex)
        end
    end

    TextBox{parent=clr_c_2,x=1,y=7,height=1,width=10,text="Color Mode"}
    local c_mode = RadioButton{parent=clr_c_2,x=1,y=8,default=ini_cfg.ColorMode,options=themes.COLOR_MODE_NAMES,callback=recolor,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.magenta}

    TextBox{parent=clr_c_2,x=21,y=13,height=2,width=18,text="Note: exact color varies by theme.",fg_bg=g_lg_fg_bg}

    PushButton{parent=clr_c_2,x=44,y=14,min_width=6,text="Done",callback=function()clr_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    local function back_from_colors()
        main_pane.set_value(util.trinary(tool_ctl.jumped_to_color, 1, 4))
        tool_ctl.jumped_to_color = false
        recolor(1)
    end

    local function show_access()
        clr_pane.set_value(2)
        recolor(c_mode.get_value())
    end

    local function submit_colors()
        tmp_cfg.FrontPanelTheme = fp_theme.get_value()
        tmp_cfg.ColorMode = c_mode.get_value()

        if tool_ctl.jumped_to_color then
            settings.set("FrontPanelTheme", tmp_cfg.FrontPanelTheme)
            settings.set("ColorMode", tmp_cfg.ColorMode)

            if settings.save("/supervisor.settings") then
                load_settings(settings_cfg, true)
                load_settings(ini_cfg)
                clr_pane.set_value(3)
            else
                clr_pane.set_value(4)
            end
        else
            tool_ctl.gen_summary(tmp_cfg)
            tool_ctl.viewing_config = false
            tool_ctl.importing_legacy = false
            tool_ctl.settings_apply.show()
            main_pane.set_value(6)
        end
    end

    PushButton{parent=clr_c_1,x=1,y=14,text="\x1b Back",callback=back_from_colors,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=clr_c_1,x=8,y=14,min_width=15,text="Accessibility",callback=show_access,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.color_next = PushButton{parent=clr_c_1,x=44,y=14,text="Next \x1a",callback=submit_colors,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.color_apply = PushButton{parent=clr_c_1,x=43,y=14,min_width=7,text="Apply",callback=submit_colors,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    tool_ctl.color_apply.hide(true)

    local function c_go_home()
        main_pane.set_value(1)
        clr_pane.set_value(1)
    end

    TextBox{parent=clr_c_3,x=1,y=1,height=1,text="Settings saved!"}
    PushButton{parent=clr_c_3,x=1,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}
    PushButton{parent=clr_c_3,x=44,y=14,min_width=6,text="Home",callback=c_go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=clr_c_4,x=1,y=1,height=5,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=clr_c_4,x=1,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}
    PushButton{parent=clr_c_4,x=44,y=14,min_width=6,text="Home",callback=c_go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Summary and Saving

    local sum_c_1 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_2 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_3 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_4 = Div{parent=summary,x=2,y=4,width=49}

    local sum_pane = MultiPane{parent=summary,x=1,y=4,panes={sum_c_1,sum_c_2,sum_c_3,sum_c_4}}

    TextBox{parent=summary,x=1,y=2,height=1,text=" Summary",fg_bg=cpair(colors.black,colors.green)}

    local setting_list = ListBox{parent=sum_c_1,x=1,y=1,height=12,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function back_from_settings()
        if tool_ctl.viewing_config or tool_ctl.importing_legacy then
            main_pane.set_value(1)
            tool_ctl.viewing_config = false
            tool_ctl.importing_legacy = false
            tool_ctl.settings_apply.show()
        else
            main_pane.set_value(5)
        end
    end

    ---@param element graphics_element
    ---@param data any
    local function try_set(element, data)
        if data ~= nil then element.set_value(data) end
    end

    local function save_and_continue()
        for k, v in pairs(tmp_cfg) do settings.set(k, v) end

        if settings.save("/supervisor.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)

            try_set(num_units, ini_cfg.UnitCount)
            try_set(tank_mode, ini_cfg.FacilityTankMode)
            try_set(svr_chan, ini_cfg.SVR_Channel)
            try_set(plc_chan, ini_cfg.PLC_Channel)
            try_set(rtu_chan, ini_cfg.RTU_Channel)
            try_set(crd_chan, ini_cfg.CRD_Channel)
            try_set(pkt_chan, ini_cfg.PKT_Channel)
            try_set(plc_timeout, ini_cfg.PLC_Timeout)
            try_set(rtu_timeout, ini_cfg.RTU_Timeout)
            try_set(crd_timeout, ini_cfg.CRD_Timeout)
            try_set(pkt_timeout, ini_cfg.PKT_Timeout)
            try_set(range, ini_cfg.TrustedRange)
            try_set(key, ini_cfg.AuthKey)
            try_set(mode, ini_cfg.LogMode)
            try_set(path, ini_cfg.LogPath)
            try_set(en_dbg, ini_cfg.LogDebug)
            try_set(fp_theme, ini_cfg.FrontPanelTheme)
            try_set(c_mode, ini_cfg.ColorMode)

            for i = 1, #ini_cfg.CoolingConfig do
                local cfg, elems = ini_cfg.CoolingConfig[i], tool_ctl.cooling_elems[i]
                try_set(elems.boilers, cfg.BoilerCount)
                try_set(elems.turbines, cfg.TurbineCount)
                try_set(elems.tank, cfg.TankConnection)
            end

            for i = 1, #ini_cfg.FacilityTankDefs do
                try_set(tool_ctl.tank_elems[i].tank_opt, ini_cfg.FacilityTankDefs[i])
            end

            en_fac_tanks.set_value(ini_cfg.FacilityTankMode > 0)

            tool_ctl.view_cfg.enable()

            if tool_ctl.importing_legacy then
                tool_ctl.importing_legacy = false
                sum_pane.set_value(3)
            else
                sum_pane.set_value(2)
            end
        else
            sum_pane.set_value(4)
        end
    end

    PushButton{parent=sum_c_1,x=1,y=14,text="\x1b Back",callback=back_from_settings,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.show_key_btn = PushButton{parent=sum_c_1,x=8,y=14,min_width=17,text="Unhide Auth Key",callback=function()tool_ctl.show_auth_key()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    tool_ctl.settings_apply = PushButton{parent=sum_c_1,x=43,y=14,min_width=7,text="Apply",callback=save_and_continue,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_2,x=1,y=1,height=1,text="Settings saved!"}

    local function go_home()
        main_pane.set_value(1)
        svr_pane.set_value(1)
        net_pane.set_value(1)
        clr_pane.set_value(1)
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

    --#endregion

    -- Config Change Log

    local cl = Div{parent=changelog,x=2,y=4,width=49}

    TextBox{parent=changelog,x=1,y=2,height=1,text=" Config Change Log",fg_bg=bw_fg_bg}

    local c_log = ListBox{parent=cl,x=1,y=1,height=12,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    for _, change in ipairs(changes) do
        TextBox{parent=c_log,text=change[1],height=1,fg_bg=bw_fg_bg}
        for _, v in ipairs(change[2]) do
            local e = Div{parent=c_log,height=#util.strwrap(v,46)}
            TextBox{parent=e,y=1,x=1,text="- ",height=1,fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=e,y=1,x=3,text=v,height=e.get_height(),fg_bg=cpair(colors.gray,colors.white)}
        end
    end

    PushButton{parent=cl,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    -- Import Error

    local i_err = Div{parent=import_err,x=2,y=4,width=49}

    TextBox{parent=import_err,x=1,y=2,height=1,text=" Import Error",fg_bg=cpair(colors.black,colors.red)}
    TextBox{parent=i_err,x=1,y=1,height=1,text="There is a problem with your config.lua file:"}

    local import_err_msg = TextBox{parent=i_err,x=1,y=3,height=6,text=""}

    PushButton{parent=i_err,x=1,y=14,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=i_err,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    -- set tool functions now that we have the elements

    -- load a legacy config file
    function tool_ctl.load_legacy()
        local config = require("supervisor.config")

        tmp_cfg.UnitCount = config.NUM_REACTORS

        if config.REACTOR_COOLING == nil or tmp_cfg.UnitCount ~= #config.REACTOR_COOLING then
            import_err_msg.set_value("Cooling configuration table length must match the number of units.")
            main_pane.set_value(8)
            return
        end

        for i = 1, tmp_cfg.UnitCount do
            local cfg = config.REACTOR_COOLING[i]

            if type(cfg) ~= "table" then
                import_err_msg.set_value("Cooling configuration for unit " .. i .. " must be a table.")
                main_pane.set_value(8)
                return
            end

            tmp_cfg.CoolingConfig[i] = { BoilerCount = cfg.BOILERS or 0, TurbineCount = cfg.TURBINES or 1, TankConnection = cfg.TANK or false }
        end

        tmp_cfg.FacilityTankMode = config.FAC_TANK_MODE

        if not (util.is_int(tmp_cfg.FacilityTankMode) and tmp_cfg.FacilityTankMode >= 0 and tmp_cfg.FacilityTankMode <= 8) then
            import_err_msg.set_value("Invalid tank mode present in config. FAC_TANK_MODE must be a number 0 through 8.")
            main_pane.set_value(8)
            return
        end

        if config.FAC_TANK_MODE > 0 then
            if config.FAC_TANK_DEFS == nil or tmp_cfg.UnitCount ~= #config.FAC_TANK_DEFS then
                import_err_msg.set_value("Facility tank definitions table length must match the number of units when using facility tanks.")
                main_pane.set_value(8)
                return
            end

            for i = 1, tmp_cfg.UnitCount do
                tmp_cfg.FacilityTankDefs[i] = config.FAC_TANK_DEFS[i]
            end
        else
            tmp_cfg.FacilityTankMode = 0
            tmp_cfg.FacilityTankDefs = {}
        end

        tmp_cfg.SVR_Channel = config.SVR_CHANNEL
        tmp_cfg.PLC_Channel = config.PLC_CHANNEL
        tmp_cfg.RTU_Channel = config.RTU_CHANNEL
        tmp_cfg.CRD_Channel = config.CRD_CHANNEL
        tmp_cfg.PKT_Channel = config.PKT_CHANNEL

        tmp_cfg.PLC_Timeout = config.PLC_TIMEOUT
        tmp_cfg.RTU_Timeout = config.RTU_TIMEOUT
        tmp_cfg.CRD_Timeout = config.CRD_TIMEOUT
        tmp_cfg.PKT_Timeout = config.PKT_TIMEOUT

        tmp_cfg.TrustedRange = config.TRUSTED_RANGE
        tmp_cfg.AuthKey = config.AUTH_KEY or ""
        tmp_cfg.LogMode = config.LOG_MODE
        tmp_cfg.LogPath = config.LOG_PATH
        tmp_cfg.LogDebug = config.LOG_DEBUG or false

        tool_ctl.gen_summary(tmp_cfg)
        sum_pane.set_value(1)
        main_pane.set_value(6)
        tool_ctl.importing_legacy = true
    end

    -- expose the auth key on the summary page
    function tool_ctl.show_auth_key()
        tool_ctl.show_key_btn.disable()
        tool_ctl.auth_key_textbox.set_value(tool_ctl.auth_key_value)
    end

    -- generate the summary list
    ---@param cfg svr_config
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

            if f[1] == "AuthKey" then val = string.rep("*", string.len(val))
            elseif f[1] == "LogMode" then val = util.trinary(raw == log.MODE.APPEND, "append", "replace")
            elseif f[1] == "FrontPanelTheme" then
                val = util.strval(themes.fp_theme_name(raw))
            elseif f[1] == "ColorMode" then
                val = util.strval(themes.color_mode_name(raw))
            elseif f[1] == "CoolingConfig" and type(cfg.CoolingConfig) == "table" then
                val = ""

                for idx = 1, #cfg.CoolingConfig do
                    local ccfg = cfg.CoolingConfig[idx]
                    local b_plural = util.trinary(ccfg.BoilerCount == 1, "", "s")
                    local t_plural = util.trinary(ccfg.TurbineCount == 1, "", "s")
                    local tank = util.trinary(ccfg.TankConnection, "has tank conn", "no tank conn")
                    val = val .. util.trinary(idx == 1, "", "\n") ..
                            util.sprintf(" \x07 unit %d - %d boiler%s, %d turbine%s, %s", idx, ccfg.BoilerCount, b_plural, ccfg.TurbineCount, t_plural, tank)
                end

                if val == "" then val = "no facility tanks" end
            elseif f[1] == "FacilityTankMode" and raw == 0 then val = "0 (n/a, unit mode)"
            elseif f[1] == "FacilityTankDefs" and type(cfg.FacilityTankDefs) == "table" then
                val = ""

                for idx = 1, #cfg.FacilityTankDefs do
                    local t_mode = "not connected to a tank"
                    if cfg.FacilityTankDefs[idx] == 1 then
                        t_mode = "connected to its unit tank"
                    elseif cfg.FacilityTankDefs[idx] == 2 then
                        t_mode = "connected to a facility tank"
                    end

                    val = val .. util.trinary(idx == 1, "", "\n") .. util.sprintf(" \x07 unit %d - %s", idx, t_mode)
                end

                if val == "" then val = "no facility tanks" end
            end

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
---@param ask_config? boolean indicate if this is being called by the startup app due to an invalid configuration
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
