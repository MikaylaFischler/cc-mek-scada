--
-- Configuration GUI
--

local log         = require("scada-common.log")
local rsio        = require("scada-common.rsio")
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
    { "v1.6.2", { "AuthKey minimum length is now 8 (if set)" } },
    { "v1.6.8", { "ConnTimeout can now have a fractional part" } },
    { "v1.6.15", { "Added front panel UI theme", "Added color accessibility modes" } },
    { "v1.7.3", { "Added standard with black off state color mode", "Added blue indicator color modes" } }
}

---@class plc_configurator
local configurator = {}

local style = {}

style.root = cpair(colors.black, colors.lightGray)
style.header = cpair(colors.white, colors.gray)

style.colors = themes.smooth_stone.colors

local bw_fg_bg = cpair(colors.black, colors.white)
local g_lg_fg_bg = cpair(colors.gray, colors.lightGray)
local nav_fg_bg = bw_fg_bg
local btn_act_fg_bg = cpair(colors.white, colors.gray)

---@class _plc_cfg_tool_ctl
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

    set_networked = nil,    ---@type function
    bundled_emcool = nil,   ---@type function
    gen_summary = nil,      ---@type function
    show_current_cfg = nil, ---@type function
    load_legacy = nil,      ---@type function

    show_auth_key = nil,    ---@type function
    show_key_btn = nil,     ---@type graphics_element
    auth_key_textbox = nil, ---@type graphics_element
    auth_key_value = ""
}

---@class plc_config
local tmp_cfg = {
    Networked = false,
    UnitID = 0,
    EmerCoolEnable = false,
    EmerCoolSide = nil,     ---@type string|nil
    EmerCoolColor = nil,    ---@type color|nil
    SVR_Channel = nil,      ---@type integer
    PLC_Channel = nil,      ---@type integer
    ConnTimeout = nil,      ---@type number
    TrustedRange = nil,     ---@type number
    AuthKey = nil,          ---@type string|nil
    LogMode = 0,
    LogPath = "",
    LogDebug = false,
    FrontPanelTheme = 1,
    ColorMode = 1
}

---@class plc_config
local ini_cfg = {}
---@class plc_config
local settings_cfg = {}

-- all settings fields, their nice names, and their default values
local fields = {
    { "Networked", "Networked", false },
    { "UnitID", "Unit ID", 1 },
    { "EmerCoolEnable", "Emergency Coolant", false },
    { "EmerCoolSide", "Emergency Coolant Side", nil },
    { "EmerCoolColor", "Emergency Coolant Color", nil },
    { "SVR_Channel", "SVR Channel", 16240 },
    { "PLC_Channel", "PLC Channel", 16241 },
    { "ConnTimeout", "Connection Timeout", 5 },
    { "TrustedRange", "Trusted Range", 0 },
    { "AuthKey", "Facility Auth Key" , ""},
    { "LogMode", "Log Mode", log.MODE.APPEND },
    { "LogPath", "Log Path", "/log.txt" },
    { "LogDebug", "Log Debug Messages", false },
    { "FrontPanelTheme", "Front Panel Theme", themes.FP_THEME.SANDSTONE },
    { "ColorMode", "Color Mode", themes.COLOR_MODE.STANDARD }
}

local side_options = { "Top", "Bottom", "Left", "Right", "Front", "Back" }
local side_options_map = { "top", "bottom", "left", "right", "front", "back" }
local color_options = { "Red", "Orange", "Yellow", "Lime", "Green", "Cyan", "Light Blue", "Blue", "Purple", "Magenta", "Pink", "White", "Light Gray", "Gray", "Black", "Brown" }
local color_options_map = { colors.red, colors.orange, colors.yellow, colors.lime, colors.green, colors.cyan, colors.lightBlue, colors.blue, colors.purple, colors.magenta, colors.pink, colors.white, colors.lightGray, colors.gray, colors.black, colors.brown }

-- convert text representation to index
---@param side string
local function side_to_idx(side)
    for k, v in ipairs(side_options_map) do
        if v == side then return k end
    end
end

-- convert color to index
---@param color color
local function color_to_idx(color)
    for k, v in ipairs(color_options_map) do
        if v == color then return k end
    end
end

-- load data from the settings file
---@param target plc_config
---@param raw boolean? true to not use default values
local function load_settings(target, raw)
    for _, v in pairs(fields) do settings.unset(v[1]) end

    local loaded = settings.load("/reactor-plc.settings")

    for _, v in pairs(fields) do target[v[1]] = settings.get(v[1], tri(raw, nil, v[3])) end

    return loaded
end

-- create the config view
---@param display graphics_element
local function config_view(display)

---@diagnostic disable-next-line: undefined-field
    local function exit() os.queueEvent("terminate") end

    TextBox{parent=display,y=1,text="Reactor PLC Configurator",alignment=CENTER,height=1,fg_bg=style.header}

    local root_pane_div = Div{parent=display,x=1,y=2}

    local main_page = Div{parent=root_pane_div,x=1,y=1}
    local plc_cfg = Div{parent=root_pane_div,x=1,y=1}
    local net_cfg = Div{parent=root_pane_div,x=1,y=1}
    local log_cfg = Div{parent=root_pane_div,x=1,y=1}
    local clr_cfg = Div{parent=root_pane_div,x=1,y=1}
    local summary = Div{parent=root_pane_div,x=1,y=1}
    local changelog = Div{parent=root_pane_div,x=1,y=1}

    local main_pane = MultiPane{parent=root_pane_div,x=1,y=1,panes={main_page,plc_cfg,net_cfg,log_cfg,clr_cfg,summary,changelog}}

    -- Main Page

    local y_start = 5

    TextBox{parent=main_page,x=2,y=2,height=2,text="Welcome to the Reactor PLC configurator! Please select one of the following options."}

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

    if fs.exists("/reactor-plc/config.lua") then
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

    --#region PLC

    local plc_c_1 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_2 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_3 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_4 = Div{parent=plc_cfg,x=2,y=4,width=49}

    local plc_pane = MultiPane{parent=plc_cfg,x=1,y=4,panes={plc_c_1,plc_c_2,plc_c_3,plc_c_4}}

    TextBox{parent=plc_cfg,x=1,y=2,height=1,text=" PLC Configuration",fg_bg=cpair(colors.black,colors.orange)}

    TextBox{parent=plc_c_1,x=1,y=1,height=1,text="Would you like to set this PLC as networked?"}
    TextBox{parent=plc_c_1,x=1,y=3,height=4,text="If you have a supervisor, select the box. You will later be prompted to select the network configuration. If you instead want to use this as a standalone safety system, don't select the box.",fg_bg=g_lg_fg_bg}

    local networked = CheckBox{parent=plc_c_1,x=1,y=8,label="Networked",default=ini_cfg.Networked,box_fg_bg=cpair(colors.orange,colors.black)}

    local function submit_networked()
        tool_ctl.set_networked(networked.get_value())
        plc_pane.set_value(2)
    end

    PushButton{parent=plc_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_1,x=44,y=14,text="Next \x1a",callback=submit_networked,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=plc_c_2,x=1,y=1,height=1,text="Please enter the reactor unit ID for this PLC."}
    TextBox{parent=plc_c_2,x=1,y=3,height=3,text="If this is a networked PLC, currently only IDs 1 through 4 are acceptable.",fg_bg=g_lg_fg_bg}

    TextBox{parent=plc_c_2,x=1,y=6,height=1,text="Unit #"}
    local u_id = NumberField{parent=plc_c_2,x=7,y=6,width=5,max_chars=3,default=ini_cfg.UnitID,min=1,fg_bg=bw_fg_bg}

    local u_id_err = TextBox{parent=plc_c_2,x=8,y=14,height=1,width=35,text="Please set a unit ID.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_id()
        local unit_id = tonumber(u_id.get_value())
        if unit_id ~= nil then
            u_id_err.hide(true)
            tmp_cfg.UnitID = unit_id
            plc_pane.set_value(3)
        else u_id_err.show() end
    end

    PushButton{parent=plc_c_2,x=1,y=14,text="\x1b Back",callback=function()plc_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_2,x=44,y=14,text="Next \x1a",callback=submit_id,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=plc_c_3,x=1,y=1,height=4,text="When networked, the supervisor takes care of emergency coolant via RTUs. However, you can configure independent emergency coolant via the PLC."}
    TextBox{parent=plc_c_3,x=1,y=6,height=5,text="This independent control can be used with or without a supervisor. To configure, you would next select the interface of the redstone output connected to one or more mekanism pipes.",fg_bg=g_lg_fg_bg}

    local en_em_cool = CheckBox{parent=plc_c_3,x=1,y=11,label="Enable PLC Emergency Coolant Control",default=ini_cfg.EmerCoolEnable,box_fg_bg=cpair(colors.orange,colors.black)}

    local function next_from_plc()
        if tmp_cfg.Networked then main_pane.set_value(3) else main_pane.set_value(4) end
    end

    local function submit_en_emcool()
        tmp_cfg.EmerCoolEnable = en_em_cool.get_value()
        if tmp_cfg.EmerCoolEnable then plc_pane.set_value(4) else next_from_plc() end
    end

    PushButton{parent=plc_c_3,x=1,y=14,text="\x1b Back",callback=function()plc_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_3,x=44,y=14,text="Next \x1a",callback=submit_en_emcool,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=plc_c_4,x=1,y=1,height=1,text="Emergency Coolant Redstone Output Side"}
    local side = Radio2D{parent=plc_c_4,x=1,y=2,rows=2,columns=3,default=side_to_idx(ini_cfg.EmerCoolSide),options=side_options,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.orange}

    TextBox{parent=plc_c_4,x=1,y=5,height=1,text="Bundled Redstone Configuration"}
    local bundled = CheckBox{parent=plc_c_4,x=1,y=6,label="Is Bundled?",default=ini_cfg.EmerCoolColor~=nil,box_fg_bg=cpair(colors.orange,colors.black),callback=function(v)tool_ctl.bundled_emcool(v)end}
    local color = Radio2D{parent=plc_c_4,x=1,y=8,rows=4,columns=4,default=color_to_idx(ini_cfg.EmerCoolColor),options=color_options,radio_colors=cpair(colors.lightGray,colors.black),color_map=color_options_map,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
    if ini_cfg.EmerCoolColor == nil then color.disable() end

    local function submit_emcool()
        tmp_cfg.EmerCoolSide = side_options_map[side.get_value()]
        tmp_cfg.EmerCoolColor = util.trinary(bundled.get_value(), color_options_map[color.get_value()], nil)
        next_from_plc()
    end

    PushButton{parent=plc_c_4,x=1,y=14,text="\x1b Back",callback=function()plc_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_4,x=44,y=14,text="Next \x1a",callback=submit_emcool,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Network

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
    local timeout = NumberField{parent=net_c_2,x=1,y=2,width=7,default=ini_cfg.ConnTimeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_2,x=9,y=2,height=2,text="seconds (default 5)",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_2,x=1,y=3,height=4,text="You generally do not want or need to modify this. On slow servers, you can increase this to make the system wait longer before assuming a disconnection.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_2,x=1,y=8,height=1,text="Trusted Range"}
    local range = NumberField{parent=net_c_2,x=1,y=9,width=10,default=ini_cfg.TrustedRange,min=0,max_chars=20,allow_decimal=true,fg_bg=bw_fg_bg}
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

    local function back_from_log()
        if tmp_cfg.Networked then main_pane.set_value(3) else main_pane.set_value(2) end
    end

    PushButton{parent=log_c_1,x=1,y=14,text="\x1b Back",callback=back_from_log,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
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

            if settings.save("/reactor-plc.settings") then
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

        if settings.save("/reactor-plc.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)

            try_set(networked, ini_cfg.Networked)
            try_set(u_id, ini_cfg.UnitID)
            try_set(en_em_cool, ini_cfg.EmerCoolEnable)
            try_set(side, side_to_idx(ini_cfg.EmerCoolSide))
            try_set(bundled, ini_cfg.EmerCoolColor ~= nil)
            if ini_cfg.EmerCoolColor ~= nil then try_set(color, color_to_idx(ini_cfg.EmerCoolColor)) end
            try_set(svr_chan, ini_cfg.SVR_Channel)
            try_set(plc_chan, ini_cfg.PLC_Channel)
            try_set(timeout, ini_cfg.ConnTimeout)
            try_set(range, ini_cfg.TrustedRange)
            try_set(key, ini_cfg.AuthKey)
            try_set(mode, ini_cfg.LogMode)
            try_set(path, ini_cfg.LogPath)
            try_set(en_dbg, ini_cfg.LogDebug)
            try_set(fp_theme, ini_cfg.FrontPanelTheme)
            try_set(c_mode, ini_cfg.ColorMode)

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
        plc_pane.set_value(1)
        net_pane.set_value(1)
        clr_pane.set_value(1)
        sum_pane.set_value(1)
    end

    PushButton{parent=sum_c_2,x=1,y=14,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_2,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_3,x=1,y=1,height=2,text="The old config.lua file will now be deleted, then the configurator will exit."}

    local function delete_legacy()
        fs.delete("/reactor-plc/config.lua")
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

    -- set tool functions now that we have the elements

    function tool_ctl.set_networked(enable)
        tmp_cfg.Networked = enable
        if enable then u_id.set_max(4) else u_id.set_max(999) end
    end

    function tool_ctl.bundled_emcool(en) if en then color.enable() else color.disable() end end

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
        main_pane.set_value(6)
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

        if cfg.AuthKey then tool_ctl.show_key_btn.enable() else tool_ctl.show_key_btn.disable() end
        tool_ctl.auth_key_value = cfg.AuthKey or "" -- to show auth key

        for i = 1, #fields do
            local f = fields[i]
            local height = 1
            local label_w = string.len(f[2])
            local val_max_w = (inner_width - label_w) + 1
            local raw = cfg[f[1]]
            local val = util.strval(raw)

            if f[1] == "AuthKey" and raw then val = string.rep("*", string.len(val))
            elseif f[1] == "LogMode" then val = util.trinary(raw == log.MODE.APPEND, "append", "replace")
            elseif f[1] == "EmerCoolColor" and raw ~= nil then val = rsio.color_name(raw)
            elseif f[1] == "FrontPanelTheme" then
                val = util.strval(themes.fp_theme_name(raw))
            elseif f[1] == "ColorMode" then
                val = util.strval(themes.color_mode_name(raw))
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

-- run the reactor PLC configurator
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
