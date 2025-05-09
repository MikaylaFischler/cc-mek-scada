--
-- Configuration GUI
--

local log         = require("scada-common.log")
local ppm         = require("scada-common.ppm")
local tcd         = require("scada-common.tcd")
local util        = require("scada-common.util")

local check       = require("rtu.config.check")
local peripherals = require("rtu.config.peripherals")
local redstone    = require("rtu.config.redstone")
local system      = require("rtu.config.system")

local core        = require("graphics.core")
local themes      = require("graphics.themes")

local DisplayBox  = require("graphics.elements.DisplayBox")
local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local PushButton  = require("graphics.elements.controls.PushButton")

local println = util.println
local tri = util.trinary

local cpair = core.cpair

local CENTER = core.ALIGN.CENTER

-- changes to the config data/format to let the user know
local changes = {
    { "v1.7.9", { "ConnTimeout can now have a fractional part" } },
    { "v1.7.15", { "Added front panel UI theme", "Added color accessibility modes" } },
    { "v1.9.2", { "Added standard with black off state color mode", "Added blue indicator color modes" } },
    { "v1.10.2", { "Re-organized peripheral configuration UI, resulting in some input fields being re-ordered" } },
    { "v1.11.8", { "Added advanced option to invert digital redstone signals" } },
    { "v1.12.0", { "Added support for redstone relays" } }
}

---@class rtu_configurator
local configurator = {}

local style = {}

style.root          = cpair(colors.black, colors.lightGray)
style.header        = cpair(colors.white, colors.gray)

style.colors        = themes.smooth_stone.colors

style.bw_fg_bg      = cpair(colors.black, colors.white)
style.g_lg_fg_bg    = cpair(colors.gray, colors.lightGray)
style.nav_fg_bg     = style.bw_fg_bg
style.btn_act_fg_bg = cpair(colors.white, colors.gray)
style.btn_dis_fg_bg = cpair(colors.lightGray, colors.white)

---@class _rtu_cfg_tool_ctl
local tool_ctl = {
    launch_startup = false,
    ask_config = false,
    has_config = false,
    viewing_config = false,
    jumped_to_color = false,

    view_gw_cfg = nil,        ---@type PushButton
    dev_cfg = nil,            ---@type PushButton
    rs_cfg = nil,             ---@type PushButton
    color_cfg = nil,          ---@type PushButton
    color_next = nil,         ---@type PushButton
    color_apply = nil,        ---@type PushButton
    settings_apply = nil,     ---@type PushButton
    settings_confirm = nil,   ---@type PushButton

    go_home = nil,            ---@type function
    gen_summary = nil,        ---@type function
    load_legacy = nil,        ---@type function
    update_peri_list = nil,   ---@type function
    update_relay_list = nil,  ---@type function
    gen_peri_summary = nil,   ---@type function
    gen_rs_summary = nil,     ---@type function
}

---@class rtu_config
local tmp_cfg = {
    SpeakerVolume = 1.0,
    Peripherals = {},    ---@type rtu_peri_definition[]
    Redstone = {},       ---@type rtu_rs_definition[]
    SVR_Channel = nil,   ---@type integer
    RTU_Channel = nil,   ---@type integer
    ConnTimeout = nil,   ---@type number
    TrustedRange = nil,  ---@type number
    AuthKey = nil,       ---@type string|nil
    LogMode = 0,         ---@type LOG_MODE
    LogPath = "",
    LogDebug = false,
    FrontPanelTheme = 1, ---@type FP_THEME
    ColorMode = 1        ---@type COLOR_MODE
}

---@class rtu_config
local ini_cfg = {}
---@class rtu_config
local settings_cfg = {}

local fields = {
    { "SpeakerVolume", "Speaker Volume", 1.0 },
    { "SVR_Channel", "SVR Channel", 16240 },
    { "RTU_Channel", "RTU Channel", 16242 },
    { "ConnTimeout", "Connection Timeout", 5 },
    { "TrustedRange", "Trusted Range", 0 },
    { "AuthKey", "Facility Auth Key", "" },
    { "LogMode", "Log Mode", log.MODE.APPEND },
    { "LogPath", "Log Path", "/log.txt" },
    { "LogDebug", "Log Debug Messages", false },
    { "FrontPanelTheme", "Front Panel Theme", themes.FP_THEME.SANDSTONE },
    { "ColorMode", "Color Mode", themes.COLOR_MODE.STANDARD }
}

-- deep copy peripherals defs
---@param data rtu_peri_definition[]
function tool_ctl.deep_copy_peri(data)
    local array = {}
    for _, d in ipairs(data) do table.insert(array, { unit = d.unit, index = d.index, name = d.name }) end
    return array
end

-- deep copy redstone defs
---@param data rtu_rs_definition[]
function tool_ctl.deep_copy_rs(data)
    local array = {}
    for _, d in ipairs(data) do table.insert(array, { unit = d.unit, port = d.port, relay = d.relay, side = d.side, color = d.color, invert = d.invert }) end
    return array
end

-- load data from the settings file
---@param target rtu_config
---@param raw boolean? true to not use default values
local function load_settings(target, raw)
    for k, _ in pairs(tmp_cfg) do settings.unset(k) end

    local loaded = settings.load("/rtu.settings")

    for _, v in pairs(fields) do target[v[1]] = settings.get(v[1], tri(raw, nil, v[3])) end

    target.Peripherals = settings.get("Peripherals", tri(raw, nil, {}))
    target.Redstone = settings.get("Redstone", tri(raw, nil, {}))

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

    TextBox{parent=display,y=1,text="RTU Gateway Configurator",alignment=CENTER,fg_bg=style.header}

    local root_pane_div = Div{parent=display,x=1,y=2}

    local main_page = Div{parent=root_pane_div,x=1,y=1}
    local spkr_cfg = Div{parent=root_pane_div,x=1,y=1}
    local net_cfg = Div{parent=root_pane_div,x=1,y=1}
    local log_cfg = Div{parent=root_pane_div,x=1,y=1}
    local clr_cfg = Div{parent=root_pane_div,x=1,y=1}
    local summary = Div{parent=root_pane_div,x=1,y=1}
    local changelog = Div{parent=root_pane_div,x=1,y=1}
    local peri_cfg = Div{parent=root_pane_div,x=1,y=1}
    local rs_cfg = Div{parent=root_pane_div,x=1,y=1}
    local check_sys = Div{parent=root_pane_div,x=1,y=1}

    local main_pane = MultiPane{parent=root_pane_div,x=1,y=1,panes={main_page,spkr_cfg,net_cfg,log_cfg,clr_cfg,summary,changelog,peri_cfg,rs_cfg,check_sys}}

    --#region Main Page

    local y_start = 2

    if tool_ctl.ask_config then
        TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text="Notice: This device is not configured for this version of the RTU gateway. If you previously had a valid config, it's not lost. You may want to check the Change Log to see what changed.",fg_bg=cpair(colors.red,colors.lightGray)}
        y_start = y_start + 5
    else
        TextBox{parent=main_page,x=2,y=2,height=2,text="Welcome to the RTU gateway configurator! Please select one of the following options."}
        y_start = y_start + 3
    end

    local function view_config()
        tool_ctl.viewing_config = true
        tool_ctl.gen_summary(settings_cfg)
        tool_ctl.settings_apply.hide(true)
        tool_ctl.settings_confirm.hide(true)
        main_pane.set_value(6)
    end

    if fs.exists("/rtu/config.lua") then
        PushButton{parent=main_page,x=2,y=y_start,min_width=28,text="Import Legacy 'config.lua'",callback=function()tool_ctl.load_legacy()end,fg_bg=cpair(colors.black,colors.cyan),active_fg_bg=btn_act_fg_bg}
        y_start = y_start + 2
    end

    local function show_peri_conns()
        tool_ctl.gen_peri_summary()
        main_pane.set_value(8)
    end

    local function show_rs_conns()
        main_pane.set_value(9)
    end

    PushButton{parent=main_page,x=2,y=y_start,min_width=19,text="Configure Gateway",callback=function()main_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    tool_ctl.view_gw_cfg = PushButton{parent=main_page,x=2,y=y_start+2,min_width=28,text="View Gateway Configuration",callback=view_config,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    tool_ctl.dev_cfg = PushButton{parent=main_page,x=2,y=y_start+4,min_width=24,text="Peripheral Connections",callback=show_peri_conns,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    tool_ctl.rs_cfg = PushButton{parent=main_page,x=2,y=y_start+6,min_width=22,text="Redstone Connections",callback=show_rs_conns,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}

    local function jump_color()
        tool_ctl.jumped_to_color = true
        tool_ctl.color_next.hide(true)
        tool_ctl.color_apply.show()
        main_pane.set_value(5)
    end

    local function startup()
        tool_ctl.launch_startup = true
        exit()
    end

    PushButton{parent=main_page,x=2,y=17,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
    local start_btn = PushButton{parent=main_page,x=42,y=17,min_width=9,text="Startup",callback=startup,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    PushButton{parent=main_page,x=39,y=y_start,min_width=12,text="Self-Check",callback=function()main_pane.set_value(10)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    tool_ctl.color_cfg = PushButton{parent=main_page,x=36,y=y_start+2,min_width=15,text="Color Options",callback=jump_color,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    PushButton{parent=main_page,x=39,y=y_start+4,min_width=12,text="Change Log",callback=function()main_pane.set_value(7)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    if tool_ctl.ask_config then start_btn.disable() end

    if not tool_ctl.has_config then
        tool_ctl.view_gw_cfg.disable()
        tool_ctl.dev_cfg.disable()
        tool_ctl.rs_cfg.disable()
        tool_ctl.color_cfg.disable()
    end

    --#endregion

    local settings = { settings_cfg, ini_cfg, tmp_cfg, fields, load_settings }

    --#region Peripherals Configuration

    local peri_pane, NEEDS_UNIT = peripherals.create(tool_ctl, main_pane, settings, peri_cfg, style)

    --#endregion

    --#region Redstone Configuration

    local rs_pane = redstone.create(tool_ctl, main_pane, settings, rs_cfg, style)

    --#endregion

    --#region System Configuration

    local divs = { spkr_cfg, net_cfg, log_cfg, clr_cfg, summary }
    local ext  = { peri_pane, rs_pane, NEEDS_UNIT, show_peri_conns, show_rs_conns, exit }

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

    --#region Self-Check

    check.create(main_pane, settings_cfg, check_sys, style)

    --#endregion
end

-- reset terminal screen
local function reset_term()
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

-- run the RTU gateway configurator
---@param ask_config? boolean indicate if this is being called by the startup app due to an invalid configuration
function configurator.configure(ask_config)
    tool_ctl.ask_config = ask_config == true

    load_settings(settings_cfg, true)
    tool_ctl.has_config = load_settings(ini_cfg)
    tmp_cfg.Peripherals = tool_ctl.deep_copy_peri(ini_cfg.Peripherals)
    tmp_cfg.Redstone = tool_ctl.deep_copy_rs(ini_cfg.Redstone)

    reset_term()

    ppm.mount_all()

    -- set overridden colors
    for i = 1, #style.colors do
        term.setPaletteColor(style.colors[i].c, style.colors[i].hex)
    end

    local status, error = pcall(function ()
        local display = DisplayBox{window=term.current(),fg_bg=style.root}
        config_view(display)

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
            elseif event == "modem_message" then
                check.receive_sv(param1, param2, param3, param4, param5)
            elseif event == "peripheral_detach" then
---@diagnostic disable-next-line: discard-returns
                ppm.handle_unmount(param1)
                tool_ctl.update_peri_list()
                tool_ctl.update_relay_list()
            elseif event == "peripheral" then
---@diagnostic disable-next-line: discard-returns
                ppm.mount(param1)
                tool_ctl.update_peri_list()
                tool_ctl.update_relay_list()
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
