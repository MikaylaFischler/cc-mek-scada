--
-- Configuration GUI
--

local log        = require("scada-common.log")
local ppm        = require("scada-common.ppm")
local tcd        = require("scada-common.tcd")
local types      = require("scada-common.types")
local util       = require("scada-common.util")

local facility   = require("coordinator.config.facility")
local hmi        = require("coordinator.config.hmi")
local system     = require("coordinator.config.system")

local core       = require("graphics.core")
local themes     = require("graphics.themes")

local DisplayBox = require("graphics.elements.DisplayBox")
local Div        = require("graphics.elements.Div")
local ListBox    = require("graphics.elements.ListBox")
local MultiPane  = require("graphics.elements.MultiPane")
local TextBox    = require("graphics.elements.TextBox")

local PushButton = require("graphics.elements.controls.PushButton")

local println = util.println
local tri = util.trinary

local cpair = core.cpair

local CENTER = core.ALIGN.CENTER

-- changes to the config data/format to let the user know
local changes = {
    { "v1.2.4", { "Added temperature scale options" } },
    { "v1.2.12", { "Added main UI theme", "Added front panel UI theme", "Added color accessibility modes" } },
    { "v1.3.3", { "Added standard with black off state color mode", "Added blue indicator color modes" } },
    { "v1.5.1", { "Added energy scale options" } },
    { "v1.6.13", { "Added option for Po/Pu pellet green/cyan pairing" } }
}

---@class crd_configurator
local configurator = {}

local style = {}

style.root          = cpair(colors.black, colors.lightGray)
style.header        = cpair(colors.white, colors.gray)

style.colors        = themes.smooth_stone.colors

style.bw_fg_bg      = cpair(colors.black, colors.white)
style.g_lg_fg_bg    = cpair(colors.gray, colors.lightGray)
style.nav_fg_bg     = style.bw_fg_bg
style.btn_act_fg_bg = cpair(colors.white, colors.gray)
style.btn_dis_fg_bg = cpair(colors.lightGray,colors.white)

---@class _crd_cfg_tool_ctl
local tool_ctl = {
    sv_cool_conf = nil,       ---@type [ integer, integer ][] list of boiler & turbine counts

    launch_startup = false,
    start_fail = 0,
    fail_message = "",
    has_config = false,
    viewing_config = false,
    jumped_to_color = false,

    view_cfg = nil,           ---@type PushButton
    color_cfg = nil,          ---@type PushButton
    color_next = nil,         ---@type PushButton
    color_apply = nil,        ---@type PushButton
    settings_apply = nil,     ---@type PushButton

    gen_summary = nil,        ---@type function
    load_legacy = nil,        ---@type function

    -- settings elements from hmi
    dis_flow_view = nil,      ---@type Checkbox
    s_vol = nil,              ---@type NumberField
    pellet_color = nil,       ---@type RadioButton
    clock_fmt = nil,          ---@type RadioButton
    temp_scale = nil,         ---@type RadioButton
    energy_scale = nil,       ---@type RadioButton

    -- settings elements and functions from facility
    num_units = nil,          ---@type NumberField
    init_sv_connect_ui = nil, ---@type function
    is_int_min_max = nil,     ---@type function

    update_mon_reqs = nil,    ---@type function
    gen_mon_list = function () end
}

---@class crd_config
local tmp_cfg = {
    UnitCount = 1,
    SpeakerVolume = 1.0,
    Time24Hour = true,
    GreenPuPellet = false,
    TempScale = 1,          ---@type TEMP_SCALE
    EnergyScale = 1,        ---@type ENERGY_SCALE
    DisableFlowView = false,
    MainDisplay = nil,      ---@type string
    FlowDisplay = nil,      ---@type string
    UnitDisplays = {},      ---@type string[]
    SVR_Channel = nil,      ---@type integer
    CRD_Channel = nil,      ---@type integer
    PKT_Channel = nil,      ---@type integer
    SVR_Timeout = nil,      ---@type number
    API_Timeout = nil,      ---@type number
    TrustedRange = nil,     ---@type number
    AuthKey = nil,          ---@type string|nil
    LogMode = 0,            ---@type LOG_MODE
    LogPath = "",
    LogDebug = false,
    MainTheme = 1,          ---@type UI_THEME
    FrontPanelTheme = 1,    ---@type FP_THEME
    ColorMode = 1           ---@type COLOR_MODE
}

---@class crd_config
local ini_cfg = {}
---@class crd_config
local settings_cfg = {}

-- all settings fields, their nice names, and their default values
local fields = {
    { "UnitCount", "Number of Reactors", 1 },
    { "MainDisplay", "Main Monitor", nil },
    { "FlowDisplay", "Flow Monitor", nil },
    { "UnitDisplays", "Unit Monitors", {} },
    { "SpeakerVolume", "Speaker Volume", 1.0 },
    { "Time24Hour", "Use 24-hour Time Format", true },
    { "GreenPuPellet", "Pellet Colors", false },
    { "TempScale", "Temperature Scale", types.TEMP_SCALE.KELVIN },
    { "EnergyScale", "Energy Scale", types.ENERGY_SCALE.FE },
    { "DisableFlowView", "Disable Flow Monitor (legacy, discouraged)", false },
    { "SVR_Channel", "SVR Channel", 16240 },
    { "CRD_Channel", "CRD Channel", 16243 },
    { "PKT_Channel", "PKT Channel", 16244 },
    { "SVR_Timeout", "Supervisor Connection Timeout", 5 },
    { "API_Timeout", "API Connection Timeout", 5 },
    { "TrustedRange", "Trusted Range", 0 },
    { "AuthKey", "Facility Auth Key" , ""},
    { "LogMode", "Log Mode", log.MODE.APPEND },
    { "LogPath", "Log Path", "/log.txt" },
    { "LogDebug", "Log Debug Messages", false },
    { "MainTheme", "Main UI Theme", themes.UI_THEME.SMOOTH_STONE },
    { "FrontPanelTheme", "Front Panel Theme", themes.FP_THEME.SANDSTONE },
    { "ColorMode", "Color Mode", themes.COLOR_MODE.STANDARD }
}

-- load tmp_cfg fields from ini_cfg fields for displays
local function preset_monitor_fields()
    tmp_cfg.DisableFlowView = ini_cfg.DisableFlowView

    tmp_cfg.MainDisplay = ini_cfg.MainDisplay
    tmp_cfg.FlowDisplay = ini_cfg.FlowDisplay
    for i = 1, ini_cfg.UnitCount do
        tmp_cfg.UnitDisplays[i] = ini_cfg.UnitDisplays[i]
    end
end

-- load data from the settings file
---@param target crd_config
---@param raw boolean? true to not use default values
local function load_settings(target, raw)
    for _, v in pairs(fields) do settings.unset(v[1]) end

    local loaded = settings.load("/coordinator.settings")

    for _, v in pairs(fields) do target[v[1]] = settings.get(v[1], tri(raw, nil, v[3])) end

    return loaded
end

-- create the config view
---@param display DisplayBox
local function config_view(display)
    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

---@diagnostic disable-next-line: undefined-field
    local function exit() os.queueEvent("terminate") end

    TextBox{parent=display,y=1,text="Coordinator Configurator",alignment=CENTER,fg_bg=style.header}

    local root_pane_div = Div{parent=display,x=1,y=2}

    local main_page = Div{parent=root_pane_div,x=1,y=1}
    local net_cfg = Div{parent=root_pane_div,x=1,y=1}
    local fac_cfg = Div{parent=root_pane_div,x=1,y=1}
    local mon_cfg = Div{parent=root_pane_div,x=1,y=1}
    local spkr_cfg = Div{parent=root_pane_div,x=1,y=1}
    local crd_cfg = Div{parent=root_pane_div,x=1,y=1}
    local log_cfg = Div{parent=root_pane_div,x=1,y=1}
    local clr_cfg = Div{parent=root_pane_div,x=1,y=1}
    local summary = Div{parent=root_pane_div,x=1,y=1}
    local changelog = Div{parent=root_pane_div,x=1,y=1}

    local main_pane = MultiPane{parent=root_pane_div,x=1,y=1,panes={main_page,net_cfg,fac_cfg,mon_cfg,spkr_cfg,crd_cfg,log_cfg,clr_cfg,summary,changelog}}

    --#region Main Page

    local y_start = 5

    TextBox{parent=main_page,x=2,y=2,height=2,text="Welcome to the Coordinator configurator! Please select one of the following options."}

    if tool_ctl.start_fail == 2 then
        local msg = util.c("Notice: There is a problem with your monitor configuration. ", tool_ctl.fail_message, " Please reconfigure monitors or correct their sizes.")
        TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text=msg,fg_bg=cpair(colors.red,colors.lightGray)}
        y_start = y_start + 5
    elseif tool_ctl.start_fail > 0 then
        TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text="Notice: This device is not configured for this version of the coordinator. If you previously had a valid config, it's not lost. You may want to check the Change Log to see what changed.",fg_bg=cpair(colors.red,colors.lightGray)}
        y_start = y_start + 5
    end

    local function view_config()
        tool_ctl.viewing_config = true
        tool_ctl.gen_summary(settings_cfg)
        tool_ctl.settings_apply.hide(true)
        main_pane.set_value(9)
    end

    if fs.exists("/coordinator/config.lua") then
        PushButton{parent=main_page,x=2,y=y_start,min_width=28,text="Import Legacy 'config.lua'",callback=function()tool_ctl.load_legacy()end,fg_bg=cpair(colors.black,colors.cyan),active_fg_bg=btn_act_fg_bg}
        y_start = y_start + 2
    end

    PushButton{parent=main_page,x=2,y=y_start,min_width=18,text="Configure System",callback=function()main_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    tool_ctl.view_cfg = PushButton{parent=main_page,x=2,y=y_start+2,min_width=20,text="View Configuration",callback=view_config,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}

    local function jump_color()
        tool_ctl.jumped_to_color = true
        tool_ctl.color_next.hide(true)
        tool_ctl.color_apply.show()
        main_pane.set_value(8)
    end

    local function startup()
        tool_ctl.launch_startup = true
        exit()
    end

    PushButton{parent=main_page,x=2,y=17,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
    local start_btn = PushButton{parent=main_page,x=42,y=17,min_width=9,text="Startup",callback=startup,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    tool_ctl.color_cfg = PushButton{parent=main_page,x=36,y=y_start,min_width=15,text="Color Options",callback=jump_color,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    PushButton{parent=main_page,x=39,y=y_start+2,min_width=12,text="Change Log",callback=function()main_pane.set_value(10)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    if tool_ctl.start_fail ~= 0 then start_btn.disable() end

    if not tool_ctl.has_config then
        tool_ctl.view_cfg.disable()
        tool_ctl.color_cfg.disable()
    end

    --#endregion

    local settings = { settings_cfg, ini_cfg, tmp_cfg, fields, load_settings }

    --#region Facility Configuration

    local fac_pane = facility.create(tool_ctl, main_pane, settings, fac_cfg, style)

    --#endregion

    --#region HMI Configuration

    local mon_pane = hmi.create(tool_ctl, main_pane, settings, { mon_cfg, spkr_cfg, crd_cfg }, style)

    --#endregion

    --#region System Configuration

    local divs = { net_cfg, log_cfg, clr_cfg, summary }
    local ext  = { fac_pane, mon_pane, preset_monitor_fields, exit }

    system.create(tool_ctl, main_pane, settings, divs, ext, style)

    --#endregion

    --#region Config Change Log

    local cl = Div{parent=changelog,x=2,y=4,width=49}

    TextBox{parent=changelog,x=1,y=2,text=" Config Change Log",fg_bg=bw_fg_bg}

    local c_log = ListBox{parent=cl,x=1,y=1,height=12,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    for _, change in ipairs(changes) do
        TextBox{parent=c_log,text=change[1],fg_bg=bw_fg_bg}
        for _, v in ipairs(change[2]) do
            local e = Div{parent=c_log,height=#util.strwrap(v,46)}
            TextBox{parent=e,y=1,x=1,text="- ",fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=e,y=1,x=3,text=v,height=e.get_height(),fg_bg=cpair(colors.gray,colors.white)}
        end
    end

    PushButton{parent=cl,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion
end

-- reset terminal screen
local function reset_term()
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

-- run the coordinator configurator<br>
-- start_fail of 0 is OK (default if not provided), 1 is bad config, 2 is bad monitor config
---@param start_code? 0|1|2 indicate error state when called from the startup app
---@param message? any string message to display on a start_fail of 2
function configurator.configure(start_code, message)
    tool_ctl.start_fail = start_code or 0
    tool_ctl.fail_message = util.trinary(type(message) == "string", message, "")

    load_settings(settings_cfg, true)
    tool_ctl.has_config = load_settings(ini_cfg)

    -- copy in some important values to start with
    preset_monitor_fields()

    reset_term()

    ppm.mount_all()

    -- set overridden colors
    for i = 1, #style.colors do
        term.setPaletteColor(style.colors[i].c, style.colors[i].hex)
    end

    local status, error = pcall(function ()
        local display = DisplayBox{window=term.current(),fg_bg=style.root}
        config_view(display)

        tool_ctl.gen_mon_list()

        while true do
            local event, param1, param2, param3, param4, param5 = util.pull_event()

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
            elseif event == "peripheral_detach" then
---@diagnostic disable-next-line: discard-returns
                ppm.handle_unmount(param1)
                tool_ctl.gen_mon_list()
            elseif event == "peripheral" then
---@diagnostic disable-next-line: discard-returns
                ppm.mount(param1)
                tool_ctl.gen_mon_list()
            elseif event == "monitor_resize" then
                tool_ctl.gen_mon_list()
            elseif event == "modem_message" then
                facility.receive_sv(param1, param2, param3, param4, param5)
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

    return status, error, tool_ctl.launch_startup
end

return configurator
