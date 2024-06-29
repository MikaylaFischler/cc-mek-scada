--
-- Configuration GUI
--

local constants   = require("scada-common.constants")
local log         = require("scada-common.log")
local ppm         = require("scada-common.ppm")
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

local IO = rsio.IO
local IO_LVL = rsio.IO_LVL
local IO_MODE = rsio.IO_MODE

local LEFT = core.ALIGN.LEFT
local CENTER = core.ALIGN.CENTER
local RIGHT = core.ALIGN.RIGHT

-- rsio port descriptions
local PORT_DESC_MAP = {
    { IO.F_SCRAM, "Facility SCRAM" },
    { IO.F_ACK, "Facility Acknowledge" },
    { IO.R_SCRAM, "Reactor SCRAM" },
    { IO.R_RESET, "Reactor RPS Reset" },
    { IO.R_ENABLE, "Reactor Enable" },
    { IO.U_ACK, "Unit Acknowledge" },
    { IO.F_ALARM, "Facility Alarm (high prio)" },
    { IO.F_ALARM_ANY, "Facility Alarm (any)" },
    { IO.F_MATRIX_LOW, "Induction Matrix < " .. (100 * constants.RS_THRESHOLDS.IMATRIX_CHARGE_LOW) .. "%" },
    { IO.F_MATRIX_HIGH, "Induction Matrix > " .. (100 * constants.RS_THRESHOLDS.IMATRIX_CHARGE_HIGH) .. "%" },
    { IO.F_MATRIX_CHG, "Induction Matrix Charge %" },
    { IO.WASTE_PU, "Waste Plutonium Valve" },
    { IO.WASTE_PO, "Waste Polonium Valve" },
    { IO.WASTE_POPL, "Waste Po Pellets Valve" },
    { IO.WASTE_AM, "Waste Antimatter Valve" },
    { IO.R_ACTIVE, "Reactor Active" },
    { IO.R_AUTO_CTRL, "Reactor in Auto Control" },
    { IO.R_SCRAMMED, "RPS Tripped" },
    { IO.R_AUTO_SCRAM, "RPS Auto SCRAM" },
    { IO.R_HIGH_DMG, "RPS High Damage" },
    { IO.R_HIGH_TEMP, "RPS High Temperature" },
    { IO.R_LOW_COOLANT, "RPS Low Coolant" },
    { IO.R_EXCESS_HC, "RPS Excess Heated Coolant" },
    { IO.R_EXCESS_WS, "RPS Excess Waste" },
    { IO.R_INSUFF_FUEL, "RPS Insufficient Fuel" },
    { IO.R_PLC_FAULT, "RPS PLC Fault" },
    { IO.R_PLC_TIMEOUT, "RPS Supervisor Timeout" },
    { IO.U_ALARM, "Unit Alarm" },
    { IO.U_EMER_COOL, "Unit Emergency Cool. Valve" }
}

-- designation (0 = facility, 1 = unit)
local PORT_DSGN = { [-1] = 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0 }

assert(#PORT_DESC_MAP == rsio.NUM_PORTS)
assert(#PORT_DSGN == rsio.NUM_PORTS)

-- changes to the config data/format to let the user know
local changes = {
    { "v1.7.9", { "ConnTimeout can now have a fractional part" } },
    { "v1.7.15", { "Added front panel UI theme", "Added color accessibility modes" } },
    { "v1.9.2", { "Added standard with black off state color mode", "Added blue indicator color modes" } }
}

---@class rtu_rs_definition
---@field unit integer|nil
---@field port IO_PORT
---@field side side
---@field color color|nil

---@class rtu_peri_definition
---@field unit integer|nil
---@field index integer|nil
---@field name string

local RTU_DEV_TYPES = { "boilerValve", "turbineValve", "dynamicValve", "inductionPort", "spsPort", "solarNeutronActivator", "environmentDetector" }
local NEEDS_UNIT = { "boilerValve", "turbineValve", "dynamicValve", "solarNeutronActivator", "environmentDetector" }

---@class rtu_configurator
local configurator = {}

local style = {}

style.root = cpair(colors.black, colors.lightGray)
style.header = cpair(colors.white, colors.gray)

style.colors = themes.smooth_stone.colors

local bw_fg_bg = cpair(colors.black, colors.white)
local g_lg_fg_bg = cpair(colors.gray, colors.lightGray)
local nav_fg_bg = bw_fg_bg
local btn_act_fg_bg = cpair(colors.white, colors.gray)

---@class _rtu_cfg_tool_ctl
local tool_ctl = {
    ask_config = false,
    has_config = false,
    viewing_config = false,
    importing_legacy = false,
    importing_any_dc = false,
    jumped_to_color = false,
    peri_cfg_editing = false, ---@type integer|false
    peri_cfg_manual = false,
    rs_cfg_port = IO.F_SCRAM, ---@type IO_PORT
    rs_cfg_editing = false,   ---@type integer|false

    view_gw_cfg = nil,        ---@type graphics_element
    dev_cfg = nil,            ---@type graphics_element
    rs_cfg = nil,             ---@type graphics_element
    color_cfg = nil,          ---@type graphics_element
    color_next = nil,         ---@type graphics_element
    color_apply = nil,        ---@type graphics_element
    settings_apply = nil,     ---@type graphics_element
    settings_confirm = nil,   ---@type graphics_element

    go_home = nil,            ---@type function
    gen_summary = nil,        ---@type function
    show_current_cfg = nil,   ---@type function
    load_legacy = nil,        ---@type function
    p_assign = nil,           ---@type function
    update_peri_list = nil,   ---@type function
    gen_peri_summary = nil,   ---@type function
    gen_rs_summary = nil,     ---@type function

    show_auth_key = nil,      ---@type function
    show_key_btn = nil,       ---@type graphics_element
    auth_key_textbox = nil,   ---@type graphics_element
    auth_key_value = "",

    ppm_devs = nil,           ---@type graphics_element
    p_name_msg = nil,         ---@type graphics_element
    p_prompt = nil,           ---@type graphics_element
    p_idx = nil,              ---@type graphics_element
    p_unit = nil,             ---@type graphics_element
    p_assign_btn = nil,       ---@type graphics_element
    p_assign_end = nil,       ---@type graphics_element
    p_desc = nil,             ---@type graphics_element
    p_desc_ext = nil,         ---@type graphics_element
    p_err = nil,              ---@type graphics_element

    rs_cfg_selection = nil,   ---@type graphics_element
    rs_cfg_unit_l = nil,      ---@type graphics_element
    rs_cfg_unit = nil,        ---@type graphics_element
    rs_cfg_side_l = nil,      ---@type graphics_element
    rs_cfg_color = nil,       ---@type graphics_element
    rs_cfg_shortcut = nil     ---@type graphics_element
}

---@class rtu_config
local tmp_cfg = {
    SpeakerVolume = 1.0,
    Peripherals = {},
    Redstone = {},
    SVR_Channel = nil,  ---@type integer
    RTU_Channel = nil,  ---@type integer
    ConnTimeout = nil,  ---@type number
    TrustedRange = nil, ---@type number
    AuthKey = nil,      ---@type string|nil
    LogMode = 0,
    LogPath = "",
    LogDebug = false,
    FrontPanelTheme = 1,
    ColorMode = 1
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

-- deep copy peripherals defs
local function deep_copy_peri(data)
    local array = {}
    for _, d in ipairs(data) do table.insert(array, { unit = d.unit, index = d.index, name = d.name }) end
    return array
end

-- deep copy redstone defs
local function deep_copy_rs(data)
    local array = {}
    for _, d in ipairs(data) do table.insert(array, { unit = d.unit, port = d.port, side = d.side, color = d.color }) end
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
---@param display graphics_element
local function config_view(display)
---@diagnostic disable-next-line: undefined-field
    local function exit() os.queueEvent("terminate") end

    TextBox{parent=display,y=1,text="RTU Gateway Configurator",alignment=CENTER,height=1,fg_bg=style.header}

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

    local main_pane = MultiPane{parent=root_pane_div,x=1,y=1,panes={main_page,spkr_cfg,net_cfg,log_cfg,clr_cfg,summary,changelog,peri_cfg,rs_cfg}}

    --#region Main Page

    local y_start = 2

    if tool_ctl.ask_config then
        TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text="Notice: This device has no valid config so the configurator has been automatically started. If you previously had a valid config, you may want to check the Change Log to see what changed.",fg_bg=cpair(colors.red,colors.lightGray)}
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
        tool_ctl.gen_peri_summary(ini_cfg)
        main_pane.set_value(8)
    end

    local function show_rs_conns()
        tool_ctl.gen_rs_summary(ini_cfg)
        main_pane.set_value(9)
    end

    PushButton{parent=main_page,x=2,y=y_start,min_width=19,text="Configure Gateway",callback=function()main_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    tool_ctl.view_gw_cfg = PushButton{parent=main_page,x=2,y=y_start+2,min_width=28,text="View Gateway Configuration",callback=view_config,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    tool_ctl.dev_cfg = PushButton{parent=main_page,x=2,y=y_start+4,min_width=24,text="Peripheral Connections",callback=show_peri_conns,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    tool_ctl.rs_cfg = PushButton{parent=main_page,x=2,y=y_start+6,min_width=22,text="Redstone Connections",callback=show_rs_conns,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}

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
        tool_ctl.view_gw_cfg.disable()
        tool_ctl.dev_cfg.disable()
        tool_ctl.rs_cfg.disable()
        tool_ctl.color_cfg.disable()
    end

    --#endregion

    --#region Speakers

    local spkr_c = Div{parent=spkr_cfg,x=2,y=4,width=49}

    TextBox{parent=spkr_cfg,x=1,y=2,height=1,text=" Speaker Configuration",fg_bg=cpair(colors.black,colors.cyan)}

    TextBox{parent=spkr_c,x=1,y=1,height=2,text="Speakers can be connected to this RTU gateway without RTU unit configuration entries."}
    TextBox{parent=spkr_c,x=1,y=4,height=3,text="You can change the speaker audio volume from the default. The range is 0.0 to 3.0, where 1.0 is standard volume."}

    local s_vol = NumberField{parent=spkr_c,x=1,y=8,width=9,max_chars=7,allow_decimal=true,default=ini_cfg.SpeakerVolume,min=0,max=3,fg_bg=bw_fg_bg}

    TextBox{parent=spkr_c,x=1,y=10,height=3,text="Note: alarm sine waves are at half scale so that multiple will be required to reach full scale.",fg_bg=g_lg_fg_bg}

    local s_vol_err = TextBox{parent=spkr_c,x=8,y=14,height=1,width=35,text="Please set a volume.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_vol()
        local vol = tonumber(s_vol.get_value())
        if vol ~= nil then
            s_vol_err.hide(true)
            tmp_cfg.SpeakerVolume = vol
            main_pane.set_value(3)
        else s_vol_err.show() end
    end

    PushButton{parent=spkr_c,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=spkr_c,x=44,y=14,text="Next \x1a",callback=submit_vol,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

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
    TextBox{parent=net_c_1,x=1,y=11,height=1,text="RTU Channel"}
    local rtu_chan = NumberField{parent=net_c_1,x=1,y=12,width=7,default=ini_cfg.RTU_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=12,height=4,text="[RTU_CHANNEL]",fg_bg=g_lg_fg_bg}

    local chan_err = TextBox{parent=net_c_1,x=8,y=14,height=1,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_channels()
        local svr_c = tonumber(svr_chan.get_value())
        local rtu_c = tonumber(rtu_chan.get_value())
        if svr_c ~= nil and rtu_c ~= nil then
            tmp_cfg.SVR_Channel = svr_c
            tmp_cfg.RTU_Channel = rtu_c
            net_pane.set_value(2)
            chan_err.hide(true)
        elseif svr_c == nil then
            chan_err.set_value("Please set the supervisor channel.")
            chan_err.show()
        else
            chan_err.set_value("Please set the RTU channel.")
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

    local function censor_key(enable) censor(tri(enable, "*", nil)) end

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
        main_pane.set_value(tri(tool_ctl.jumped_to_color, 1, 4))
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

            if settings.save("/rtu.settings") then
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
            tool_ctl.settings_confirm.hide(true)
            main_pane.set_value(6)
        end
    end

    PushButton{parent=clr_c_1,x=1,y=14,text="\x1b Back",callback=back_from_colors,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=clr_c_1,x=8,y=14,min_width=15,text="Accessibility",callback=show_access,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.color_next = PushButton{parent=clr_c_1,x=44,y=14,text="Next \x1a",callback=submit_colors,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.color_apply = PushButton{parent=clr_c_1,x=43,y=14,min_width=7,text="Apply",callback=submit_colors,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    tool_ctl.color_apply.hide(true)

    TextBox{parent=clr_c_3,x=1,y=1,height=1,text="Settings saved!"}
    PushButton{parent=clr_c_3,x=1,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}
    PushButton{parent=clr_c_3,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=clr_c_4,x=1,y=1,height=5,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=clr_c_4,x=1,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}
    PushButton{parent=clr_c_4,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Summary and Saving

    local sum_c_1 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_2 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_3 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_4 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_5 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_6 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_7 = Div{parent=summary,x=2,y=4,width=49}

    local sum_pane = MultiPane{parent=summary,x=1,y=4,panes={sum_c_1,sum_c_2,sum_c_3,sum_c_4,sum_c_5,sum_c_6,sum_c_7}}

    TextBox{parent=summary,x=1,y=2,height=1,text=" Summary",fg_bg=cpair(colors.black,colors.green)}

    local setting_list = ListBox{parent=sum_c_1,x=1,y=1,height=12,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function back_from_settings()
        if tool_ctl.viewing_config or tool_ctl.importing_legacy then
            if tool_ctl.importing_legacy and tool_ctl.importing_any_dc then
                sum_pane.set_value(7)
            else
                tool_ctl.importing_legacy = false
                tool_ctl.go_home()
            end

            tool_ctl.viewing_config = false
        else main_pane.set_value(5) end
    end

    ---@param element graphics_element
    ---@param data any
    local function try_set(element, data)
        if data ~= nil then element.set_value(data) end
    end

    ---@param exclude_conns boolean? true to exclude saving peripheral/redstone connections
    local function save_and_continue(exclude_conns)
        for k, v in pairs(tmp_cfg) do
            if not (exclude_conns and (k == "Peripherals" or k == "Redstone")) then settings.set(k, v) end
        end

        -- always set these if missing
        if settings.get("Peripherals") == nil then settings.set("Peripherals", {}) end
        if settings.get("Redstone") == nil then settings.set("Redstone", {}) end

        if settings.save("/rtu.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)

            try_set(s_vol, ini_cfg.SpeakerVolume)
            try_set(svr_chan, ini_cfg.SVR_Channel)
            try_set(rtu_chan, ini_cfg.RTU_Channel)
            try_set(timeout, ini_cfg.ConnTimeout)
            try_set(range, ini_cfg.TrustedRange)
            try_set(key, ini_cfg.AuthKey)
            try_set(mode, ini_cfg.LogMode)
            try_set(path, ini_cfg.LogPath)
            try_set(en_dbg, ini_cfg.LogDebug)
            try_set(fp_theme, ini_cfg.FrontPanelTheme)
            try_set(c_mode, ini_cfg.ColorMode)

            if not exclude_conns then
                tmp_cfg.Peripherals = deep_copy_peri(ini_cfg.Peripherals)
                tmp_cfg.Redstone = deep_copy_rs(ini_cfg.Redstone)

                tool_ctl.update_peri_list()
            end

            tool_ctl.dev_cfg.enable()
            tool_ctl.rs_cfg.enable()
            tool_ctl.view_gw_cfg.enable()

            if tool_ctl.importing_legacy then
                tool_ctl.importing_legacy = false
                sum_pane.set_value(5)
            else sum_pane.set_value(4) end
        else sum_pane.set_value(6) end
    end

    PushButton{parent=sum_c_1,x=1,y=14,text="\x1b Back",callback=back_from_settings,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.show_key_btn = PushButton{parent=sum_c_1,x=8,y=14,min_width=17,text="Unhide Auth Key",callback=function()tool_ctl.show_auth_key()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    tool_ctl.settings_apply = PushButton{parent=sum_c_1,x=43,y=14,min_width=7,text="Apply",callback=function()save_and_continue(true)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}
    tool_ctl.settings_confirm = PushButton{parent=sum_c_1,x=41,y=14,min_width=9,text="Confirm",callback=function()sum_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}
    tool_ctl.settings_confirm.hide()

    TextBox{parent=sum_c_2,x=1,y=1,height=1,text="The following peripherals will be imported:"}
    local peri_import_list = ListBox{parent=sum_c_2,x=1,y=3,height=10,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    PushButton{parent=sum_c_2,x=1,y=14,text="\x1b Back",callback=function()sum_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_2,x=41,y=14,min_width=9,text="Confirm",callback=function()sum_pane.set_value(3)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_3,x=1,y=1,height=1,text="The following redstone entries will be imported:"}
    local rs_import_list = ListBox{parent=sum_c_3,x=1,y=3,height=10,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    PushButton{parent=sum_c_3,x=1,y=14,text="\x1b Back",callback=function()sum_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_3,x=43,y=14,min_width=7,text="Apply",callback=save_and_continue,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    local function jump_peri_conns()
        tool_ctl.go_home()
        show_peri_conns()
    end

    local function jump_rs_conns()
        tool_ctl.go_home()
        show_rs_conns()
    end

    TextBox{parent=sum_c_4,x=1,y=1,height=1,text="Settings saved!"}
    TextBox{parent=sum_c_4,x=1,y=3,height=4,text="Remember to configure any peripherals or redstone that you have connected to this RTU gateway if you have not already done so, or if you have added, removed, or modified any of them."}
    PushButton{parent=sum_c_4,x=1,y=8,min_width=24,text="Peripheral Connections",callback=jump_peri_conns,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_4,x=1,y=10,min_width=22,text="Redstone Connections",callback=jump_rs_conns,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_4,x=1,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}
    PushButton{parent=sum_c_4,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_5,x=1,y=1,height=2,text="The old config.lua file will now be deleted, then the configurator will exit."}

    local function delete_legacy()
        fs.delete("/rtu/config.lua")
        exit()
    end

    PushButton{parent=sum_c_5,x=1,y=14,min_width=8,text="Cancel",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_5,x=44,y=14,min_width=6,text="OK",callback=delete_legacy,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_6,x=1,y=1,height=5,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=sum_c_6,x=1,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_6,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_7,x=1,y=1,height=8,text="Warning!\n\nSome of the devices in your old config file aren't currently connected. If the device isn't connected, the options can't be properly validated. Please either connect your devices and try again or complete the import without validation on those entry's settings."}
    TextBox{parent=sum_c_7,x=1,y=10,height=3,text="Afterwards, either (a) edit then save entries for currently disconnected devices to properly configure or (b) delete those entries."}
    PushButton{parent=sum_c_7,x=1,y=14,text="\x1b Back",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_7,x=41,y=14,min_width=9,text="Confirm",callback=function()sum_pane.set_value(1)end,fg_bg=cpair(colors.black,colors.orange),active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Config Change Log

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

    --#endregion

    --#region Peripherals

    local peri_c_1 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_2 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_3 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_4 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_5 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_6 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_7 = Div{parent=peri_cfg,x=2,y=4,width=49}

    local peri_pane = MultiPane{parent=peri_cfg,x=1,y=4,panes={peri_c_1,peri_c_2,peri_c_3,peri_c_4,peri_c_5,peri_c_6,peri_c_7}}

    TextBox{parent=peri_cfg,x=1,y=2,height=1,text=" Peripheral Connections",fg_bg=cpair(colors.black,colors.purple)}

    local peri_list = ListBox{parent=peri_c_1,x=1,y=1,height=12,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function peri_revert()
        tmp_cfg.Peripherals = deep_copy_peri(ini_cfg.Peripherals)
        tool_ctl.gen_peri_summary(tmp_cfg)
    end

    local function peri_apply()
        settings.set("Peripherals", tmp_cfg.Peripherals)

        if settings.save("/rtu.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)
            peri_pane.set_value(5)
        else
            peri_pane.set_value(6)
        end
    end

    PushButton{parent=peri_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_1,x=8,y=14,min_width=16,text="Revert Changes",callback=peri_revert,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_1,x=35,y=14,min_width=7,text="Add +",callback=function()peri_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_1,x=43,y=14,min_width=7,text="Apply",callback=peri_apply,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=peri_c_2,x=1,y=1,height=1,text="Select one of the below devices to use."}

    tool_ctl.ppm_devs = ListBox{parent=peri_c_2,x=1,y=3,height=10,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    PushButton{parent=peri_c_2,x=1,y=14,text="\x1b Back",callback=function()peri_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_2,x=8,y=14,min_width=10,text="Manual +",callback=function()peri_pane.set_value(3)end,fg_bg=cpair(colors.black,colors.orange),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_2,x=26,y=14,min_width=24,text="I don't see my device!",callback=function()peri_pane.set_value(7)end,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=peri_c_7,x=1,y=1,height=10,text="Make sure your device is either touching the RTU or connected via wired modems. There should be a wired modem on a side of the RTU then one on the device, connected by a cable. The modem on the device needs to be right clicked to connect it (which will turn its border red), at which point the peripheral name will be shown in the chat."}
    TextBox{parent=peri_c_7,x=1,y=9,height=4,text="If it still does not show, it may not be compatible. Currently only Boilers, Turbines, Dynamic Tanks, SNAs, SPSs, Induction Matricies, and Environment Detectors are supported."}
    PushButton{parent=peri_c_7,x=1,y=14,text="\x1b Back",callback=function()peri_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    local new_peri_attrs = { "", "" }
    local function new_peri(name, type)
        new_peri_attrs = { name, type }
        tool_ctl.peri_cfg_editing = false

        tool_ctl.p_err.hide(true)
        tool_ctl.p_name_msg.set_value("Configuring peripheral on '" .. name .. "':")
        tool_ctl.p_desc_ext.set_value("")

        if type == "boilerValve" then
            tool_ctl.p_prompt.set_value("This is the #     boiler for reactor unit #    .")
            tool_ctl.p_idx.show()
            tool_ctl.p_idx.redraw()
            tool_ctl.p_idx.enable()
            tool_ctl.p_idx.set_max(2)
            tool_ctl.p_unit.reposition(44, 4)
            tool_ctl.p_unit.enable()
            tool_ctl.p_unit.show()
            tool_ctl.p_assign_btn.hide(true)
            tool_ctl.p_assign_end.hide(true)
            tool_ctl.p_desc.reposition(1, 7)
            tool_ctl.p_desc.set_value("Each unit can have at most 2 boilers. Boiler #1 shows up first on the main display, followed by boiler #2 below it. These numberings are independent of which RTU they are connected to. For example, one RTU can have boiler #1 and another can have #2, but both cannot have #1.")
        elseif type == "turbineValve" then
            tool_ctl.p_prompt.set_value("This is the #     turbine for reactor unit #    .")
            tool_ctl.p_idx.show()
            tool_ctl.p_idx.redraw()
            tool_ctl.p_idx.enable()
            tool_ctl.p_idx.set_max(3)
            tool_ctl.p_unit.reposition(45, 4)
            tool_ctl.p_unit.enable()
            tool_ctl.p_unit.show()
            tool_ctl.p_assign_btn.hide(true)
            tool_ctl.p_assign_end.hide(true)
            tool_ctl.p_desc.reposition(1, 7)
            tool_ctl.p_desc.set_value("Each unit can have at most 3 turbines. Turbine #1 shows up first on the main display, followed by #2 then #3 below it. These numberings are independent of which RTU they are connected to. For example, one RTU can have turbine #1 and another can have #2, but both cannot have #1.")
        elseif type == "solarNeutronActivator" then
            tool_ctl.p_idx.hide()
            tool_ctl.p_prompt.set_value("This SNA is for reactor unit #    .")
            tool_ctl.p_unit.reposition(31, 4)
            tool_ctl.p_unit.enable()
            tool_ctl.p_unit.show()
            tool_ctl.p_assign_btn.hide(true)
            tool_ctl.p_assign_end.hide(true)
            tool_ctl.p_desc_ext.set_value("Before adding lots of SNAs: multiply the \"PEAK\" rate on the flow monitor (after connecting at least 1 SNA) by 10 to get the mB/t of waste that they can process. Enough SNAs to provide 2x to 3x of your max burn rate should be a good margin to catch up after night or cloudy weather. Too many devices (such as SNAs) on one RTU can cause lag.")
        elseif type == "dynamicValve" then
            tool_ctl.p_prompt.set_value("This is the #     dynamic tank for...")
            tool_ctl.p_assign_btn.show()
            tool_ctl.p_assign_btn.redraw()
            tool_ctl.p_assign_end.show()
            tool_ctl.p_assign_end.redraw()
            tool_ctl.p_idx.show()
            tool_ctl.p_idx.redraw()
            tool_ctl.p_idx.set_max(4)
            tool_ctl.p_unit.reposition(18, 6)
            tool_ctl.p_unit.enable()
            tool_ctl.p_unit.show()

            if tool_ctl.p_assign_btn.get_value() == 1 then
                tool_ctl.p_idx.enable()
                tool_ctl.p_unit.disable()
            else
                tool_ctl.p_idx.set_value(1)
                tool_ctl.p_idx.disable()
                tool_ctl.p_unit.enable()
            end

            tool_ctl.p_desc.reposition(1, 8)
            tool_ctl.p_desc.set_value("Each reactor unit can have at most 1 tank and the facility can have at most 4. Each facility tank must have a unique # 1 through 4, regardless of where it is connected. Only a total of 4 tanks can be displayed on the flow monitor.")
        elseif type == "environmentDetector" then
            tool_ctl.p_prompt.set_value("This is the #     environment detector for...")
            tool_ctl.p_assign_btn.show()
            tool_ctl.p_assign_btn.redraw()
            tool_ctl.p_assign_end.show()
            tool_ctl.p_assign_end.redraw()
            tool_ctl.p_idx.show()
            tool_ctl.p_idx.redraw()
            tool_ctl.p_idx.set_max(99)
            tool_ctl.p_unit.reposition(18, 6)
            tool_ctl.p_unit.enable()
            tool_ctl.p_unit.show()
            if tool_ctl.p_assign_btn.get_value() == 1 then tool_ctl.p_unit.disable() else tool_ctl.p_unit.enable() end
            tool_ctl.p_desc.reposition(1, 8)
            tool_ctl.p_desc.set_value("You can connect more than one environment detector for a particular unit or the facility. In that case, the maximum radiation reading from those assigned to that particular unit or the facility will be used for alarms and display.")
        elseif type == "inductionPort" or type == "spsPort" then
            local dev = tri(type == "inductionPort", "induction matrix", "SPS")
            tool_ctl.p_idx.hide(true)
            tool_ctl.p_unit.hide(true)
            tool_ctl.p_prompt.set_value("This is the " .. dev .. " for the facility.")
            tool_ctl.p_assign_btn.hide(true)
            tool_ctl.p_assign_end.hide(true)
            tool_ctl.p_desc.reposition(1, 7)
            tool_ctl.p_desc.set_value("There can only be one of these devices per SCADA network, so it will be assigned as the sole " .. dev .. " for the facility. There must only be one of these across all the RTUs you have.")
        else
            assert(false, "invalid peripheral type after type validation")
        end

        peri_pane.set_value(4)
    end

    -- update peripherals list
    function tool_ctl.update_peri_list()
        local alternate = true
        local mounts = ppm.list_mounts()

        -- filter out in-use peripherals
        for _, v in ipairs(tmp_cfg.Peripherals) do mounts[v.name] = nil end

        tool_ctl.ppm_devs.remove_all()
        for name, entry in pairs(mounts) do
            if util.table_contains(RTU_DEV_TYPES, entry.type) then
                local bkg = tri(alternate, colors.white, colors.lightGray)

                ---@cast entry ppm_entry
                local line = Div{parent=tool_ctl.ppm_devs,height=2,fg_bg=cpair(colors.black,bkg)}
                PushButton{parent=line,x=1,y=1,min_width=9,alignment=LEFT,height=1,text="> SELECT",callback=function()tool_ctl.peri_cfg_manual=false;new_peri(name,entry.type)end,fg_bg=cpair(colors.black,colors.purple),active_fg_bg=cpair(colors.white,colors.black)}
                TextBox{parent=line,x=11,y=1,height=1,text=name,fg_bg=cpair(colors.black,bkg)}
                TextBox{parent=line,x=11,y=2,height=1,text=entry.type,fg_bg=cpair(colors.gray,bkg)}

                alternate = not alternate
            end
        end
    end

    tool_ctl.update_peri_list()

    TextBox{parent=peri_c_3,x=1,y=1,height=4,text="This feature is intended for advanced users. If you are clicking this just because your device is not shown, follow the connection instructions in 'I don't see my device!'."}
    TextBox{parent=peri_c_3,x=1,y=6,height=4,text="Peripheral Name"}
    local p_name = TextField{parent=peri_c_3,x=1,y=7,width=49,height=1,max_len=128,fg_bg=bw_fg_bg}
    local p_type = Radio2D{parent=peri_c_3,x=1,y=9,rows=4,columns=2,default=1,options=RTU_DEV_TYPES,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.purple}
    local man_p_err = TextBox{parent=peri_c_3,x=8,y=14,height=1,width=35,text="Please enter a peripheral name.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
    man_p_err.hide(true)

    local function submit_manual_peri()
        local name = p_name.get_value()
        if string.len(name) > 0 then
            tool_ctl.entering_manual = true
            man_p_err.hide(true)
            new_peri(name, RTU_DEV_TYPES[p_type.get_value()])
        else man_p_err.show() end
    end

    PushButton{parent=peri_c_3,x=1,y=14,text="\x1b Back",callback=function()peri_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_3,x=44,y=14,text="Next \x1a",callback=submit_manual_peri,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    tool_ctl.p_name_msg = TextBox{parent=peri_c_4,x=1,y=1,height=2,text=""}
    tool_ctl.p_prompt = TextBox{parent=peri_c_4,x=1,y=4,height=2,text=""}
    tool_ctl.p_idx = NumberField{parent=peri_c_4,x=14,y=4,width=4,max_chars=2,min=1,max=2,default=1,fg_bg=bw_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    tool_ctl.p_assign_btn = RadioButton{parent=peri_c_4,x=1,y=5,default=1,options={"the facility.","a unit. (unit #"},callback=function(v)tool_ctl.p_assign(v)end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.purple}
    tool_ctl.p_assign_end = TextBox{parent=peri_c_4,x=22,y=6,height=6,width=1,text=")"}

    tool_ctl.p_unit = NumberField{parent=peri_c_4,x=44,y=4,width=4,max_chars=2,min=1,max=4,default=1,fg_bg=bw_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    tool_ctl.p_unit.disable()

    function tool_ctl.p_assign(opt)
        if opt == 1 then
            tool_ctl.p_unit.disable()
            if new_peri_attrs[2] == "dynamicValve" then tool_ctl.p_idx.enable() end
        else
            tool_ctl.p_unit.enable()
            if new_peri_attrs[2] == "dynamicValve" then
                tool_ctl.p_idx.set_value(1)
                tool_ctl.p_idx.disable()
            end
        end
    end

    tool_ctl.p_desc = TextBox{parent=peri_c_4,x=1,y=7,height=6,text="",fg_bg=g_lg_fg_bg}
    tool_ctl.p_desc_ext = TextBox{parent=peri_c_4,x=1,y=6,height=7,text="",fg_bg=g_lg_fg_bg}

    tool_ctl.p_err = TextBox{parent=peri_c_4,x=8,y=14,height=1,width=32,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
    tool_ctl.p_err.hide(true)

    local function back_from_peri_opts()
        if tool_ctl.peri_cfg_editing ~= false then
            peri_pane.set_value(1)
        elseif tool_ctl.entering_manual then
            peri_pane.set_value(3)
        else
            peri_pane.set_value(2)
        end

        tool_ctl.entering_manual = false
    end

    local function save_peri_entry()
        local peri_name = new_peri_attrs[1]
        local peri_type = new_peri_attrs[2]

        local unit, index = nil, nil

        local for_facility = tool_ctl.p_assign_btn.get_value() == 1
        local u = tonumber(tool_ctl.p_unit.get_value())
        local idx = tonumber(tool_ctl.p_idx.get_value())

        if util.table_contains(NEEDS_UNIT, peri_type) then
            if (peri_type == "dynamicValve" or peri_type == "environmentDetector") and for_facility then
                -- skip
            elseif not (util.is_int(u) and u > 0 and u < 5) then
                tool_ctl.p_err.set_value("Unit ID must be within 1 to 4.")
                tool_ctl.p_err.show()
                return
            else unit = u end
        end

        if peri_type == "boilerValve" then
            if not (idx == 1 or idx == 2) then
                tool_ctl.p_err.set_value("Index must be 1 or 2.")
                tool_ctl.p_err.show()
                return
            else index = idx end
        elseif peri_type == "turbineValve" then
            if not (idx == 1 or idx == 2 or idx == 3) then
                tool_ctl.p_err.set_value("Index must be 1, 2, or 3.")
                tool_ctl.p_err.show()
                return
            else index = idx end
        elseif peri_type == "dynamicValve" and for_facility then
            if not (util.is_int(idx) and idx > 0 and idx < 5) then
                tool_ctl.p_err.set_value("Index must be within 1 to 4.")
                tool_ctl.p_err.show()
                return
            else index = idx end
        elseif peri_type == "dynamicValve" then
            index = 1
        elseif peri_type == "environmentDetector" then
            if not (util.is_int(idx) and idx > 0) then
                tool_ctl.p_err.set_value("Index must be greater than 0.")
                tool_ctl.p_err.show()
                return
            else index = idx end
        end

        tool_ctl.p_err.hide(true)

        ---@type rtu_peri_definition
        local def = { name = peri_name, unit = unit, index = index }

        if tool_ctl.peri_cfg_editing == false then
            table.insert(tmp_cfg.Peripherals, def)
        else
            def.name = tmp_cfg.Peripherals[tool_ctl.peri_cfg_editing].name
            tmp_cfg.Peripherals[tool_ctl.peri_cfg_editing] = def
        end

        peri_pane.set_value(1)
        tool_ctl.gen_peri_summary(tmp_cfg)
        tool_ctl.update_peri_list()

        tool_ctl.p_idx.set_value(1)
    end

    PushButton{parent=peri_c_4,x=1,y=14,text="\x1b Back",callback=back_from_peri_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_4,x=41,y=14,min_width=9,text="Confirm",callback=save_peri_entry,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=peri_c_5,x=1,y=1,height=1,text="Settings saved!"}
    PushButton{parent=peri_c_5,x=1,y=14,text="\x1b Back",callback=function()peri_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_5,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=peri_c_6,x=1,y=1,height=5,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=peri_c_6,x=1,y=14,text="\x1b Back",callback=function()peri_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_6,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Redstone

    local rs_c_1 = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_2 = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_3 = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_4 = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_5 = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_6 = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_7 = Div{parent=rs_cfg,x=2,y=4,width=49}

    local rs_pane = MultiPane{parent=rs_cfg,x=1,y=4,panes={rs_c_1,rs_c_2,rs_c_3,rs_c_4,rs_c_5,rs_c_6,rs_c_7}}

    TextBox{parent=rs_cfg,x=1,y=2,height=1,text=" Redstone Connections",fg_bg=cpair(colors.black,colors.red)}

    TextBox{parent=rs_c_1,x=1,y=1,height=1,text=" port          side/color       unit/facility",fg_bg=g_lg_fg_bg}
    local rs_list = ListBox{parent=rs_c_1,x=1,y=2,height=11,width=49,scroll_height=200,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function rs_revert()
        tmp_cfg.Redstone = deep_copy_rs(ini_cfg.Redstone)
        tool_ctl.gen_rs_summary(tmp_cfg)
    end

    local function rs_apply()
        settings.set("Redstone", tmp_cfg.Redstone)

        if settings.save("/rtu.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)
            rs_pane.set_value(4)
        else
            rs_pane.set_value(5)
        end
    end

    PushButton{parent=rs_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_1,x=8,y=14,min_width=16,text="Revert Changes",callback=rs_revert,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_1,x=35,y=14,min_width=7,text="New +",callback=function()rs_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_1,x=43,y=14,min_width=7,text="Apply",callback=rs_apply,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_6,x=1,y=1,height=5,text="You already configured this input. There can only be one entry for each input.\n\nPlease select a different port."}
    PushButton{parent=rs_c_6,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_2,x=1,y=1,height=1,text="Select one of the below ports to use."}

    local rs_ports = ListBox{parent=rs_c_2,x=1,y=3,height=10,width=49,scroll_height=200,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function new_rs(port)
        if (rsio.get_io_dir(port) == rsio.IO_DIR.IN) then
            for i = 1, #tmp_cfg.Redstone do
                if tmp_cfg.Redstone[i].port == port then
                    rs_pane.set_value(6)
                    return
                end
            end
        end

        tool_ctl.rs_cfg_editing = false

        local text

        if port == -1 then
            tool_ctl.rs_cfg_color.hide(true)
            tool_ctl.rs_cfg_shortcut.show()
            tool_ctl.rs_cfg_side_l.set_value("Output Side")
            text = "You selected the ALL_WASTE shortcut."
        else
            tool_ctl.rs_cfg_shortcut.hide(true)
            tool_ctl.rs_cfg_side_l.set_value(tri(rsio.get_io_dir(port) == rsio.IO_DIR.IN, "Input Side", "Output Side"))
            tool_ctl.rs_cfg_color.show()

            local io_type = "analog input "
            local io_mode = rsio.get_io_mode(port)
            local inv = tri(rsio.digital_is_active(port, IO_LVL.LOW) == true, "inverted ", "")

            if io_mode == IO_MODE.DIGITAL_IN then
                io_type = inv .. "digital input "
            elseif io_mode == IO_MODE.DIGITAL_OUT then
                io_type = inv .. "digital output "
            elseif io_mode == IO_MODE.ANALOG_OUT then
                io_type = "analog output "
            end

            text = "You selected the " .. io_type .. rsio.to_string(port) .. " (for "

            if PORT_DSGN[port] == 1 then
                text = text .. "a unit)."
                tool_ctl.rs_cfg_unit_l.show()
                tool_ctl.rs_cfg_unit.show()
            else
                tool_ctl.rs_cfg_unit_l.hide(true)
                tool_ctl.rs_cfg_unit.hide(true)
                text = text .. "the facility)."
            end
        end

        tool_ctl.rs_cfg_selection.set_value(text)
        tool_ctl.rs_cfg_port = port
        rs_pane.set_value(3)
    end

    -- add entries to redstone option list
    local all_w_macro = Div{parent=rs_ports,height=1}
    PushButton{parent=all_w_macro,x=1,y=1,min_width=14,alignment=LEFT,height=1,text=">ALL_WASTE",callback=function()new_rs(-1)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.black)}
    TextBox{parent=all_w_macro,x=16,y=1,width=5,height=1,text="[n/a]",fg_bg=cpair(colors.lightGray,colors.white)}
    TextBox{parent=all_w_macro,x=22,y=1,height=1,text="Create all 4 waste entries",fg_bg=cpair(colors.gray,colors.white)}

    for i = 1, rsio.NUM_PORTS do
        local p = PORT_DESC_MAP[i][1]
        local name = rsio.to_string(p)
        local io_dir = tri(rsio.get_io_dir(p) == rsio.IO_DIR.IN, "[in]", "[out]")
        local btn_color = tri(rsio.get_io_dir(p) == rsio.IO_DIR.IN, colors.yellow, colors.lightBlue)

        local entry = Div{parent=rs_ports,height=1}
        PushButton{parent=entry,x=1,y=1,min_width=14,alignment=LEFT,height=1,text=">"..name,callback=function()new_rs(p)end,fg_bg=cpair(colors.black,btn_color),active_fg_bg=cpair(colors.white,colors.black)}
        TextBox{parent=entry,x=16,y=1,width=5,height=1,text=io_dir,fg_bg=cpair(colors.lightGray,colors.white)}
        TextBox{parent=entry,x=22,y=1,height=1,text=PORT_DESC_MAP[i][2],fg_bg=cpair(colors.gray,colors.white)}
    end

    PushButton{parent=rs_c_2,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    tool_ctl.rs_cfg_selection = TextBox{parent=rs_c_3,x=1,y=1,height=2,text=""}

    PushButton{parent=rs_c_3,x=36,y=3,text="What's that?",min_width=14,callback=function()rs_pane.set_value(7)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_7,x=1,y=1,height=4,text="(Normal) Digital Input: On if there is a redstone signal, off otherwise\nInverted Digital Input: On without a redstone signal, off otherwise"}
    TextBox{parent=rs_c_7,x=1,y=6,height=4,text="(Normal) Digital Output: Redstone signal to 'turn it on', none to 'turn it off'\nInverted Digital Output: No redstone signal to 'turn it on', redstone signal to 'turn it off'"}
    TextBox{parent=rs_c_7,x=1,y=11,height=2,text="Analog Input: 0-15 redstone power level input\nAnalog Output: 0-15 scaled redstone power level output"}
    PushButton{parent=rs_c_7,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    tool_ctl.rs_cfg_side_l = TextBox{parent=rs_c_3,x=1,y=4,width=11,height=1,text="Output Side"}
    local side = Radio2D{parent=rs_c_3,x=1,y=5,rows=1,columns=6,default=1,options=side_options,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.red}

    tool_ctl.rs_cfg_unit_l = TextBox{parent=rs_c_3,x=25,y=7,width=7,height=1,text="Unit ID"}
    tool_ctl.rs_cfg_unit = NumberField{parent=rs_c_3,x=33,y=7,width=10,max_chars=2,min=1,max=4,fg_bg=bw_fg_bg}

    local function set_bundled(bundled)
        if bundled then tool_ctl.rs_cfg_color.enable() else tool_ctl.rs_cfg_color.disable() end
    end

    tool_ctl.rs_cfg_shortcut = TextBox{parent=rs_c_3,x=1,y=9,height=4,text="This shortcut will add entries for each of the 4 waste outputs. If you select bundled, 4 colors will be assigned to the selected side. Otherwise, 4 default sides will be used."}
    tool_ctl.rs_cfg_shortcut.hide(true)

    local bundled = CheckBox{parent=rs_c_3,x=1,y=7,label="Is Bundled?",default=false,box_fg_bg=cpair(colors.red,colors.black),callback=set_bundled}
    tool_ctl.rs_cfg_color = Radio2D{parent=rs_c_3,x=1,y=9,rows=4,columns=4,default=1,options=color_options,radio_colors=cpair(colors.lightGray,colors.black),color_map=color_options_map,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
    tool_ctl.rs_cfg_color.disable()

    local rs_err = TextBox{parent=rs_c_3,x=8,y=14,height=1,width=30,text="Unit ID must be within 1 to 4.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
    rs_err.hide(true)

    local function back_from_rs_opts()
        rs_err.hide(true)
        if tool_ctl.rs_cfg_editing ~= false then rs_pane.set_value(1) else rs_pane.set_value(2) end
    end

    local function save_rs_entry()
        local port = tool_ctl.rs_cfg_port
        local u = tonumber(tool_ctl.rs_cfg_unit.get_value())

        if PORT_DSGN[port] == 0 or (util.is_int(u) and u > 0 and u < 5) then
            rs_err.hide(true)

            if port >= 0 then
                ---@type rtu_rs_definition
                local def = {
                    unit = tri(PORT_DSGN[port] == 1, u, nil),
                    port = port,
                    side = side_options_map[side.get_value()],
                    color = tri(bundled.get_value(), color_options_map[tool_ctl.rs_cfg_color.get_value()], nil)
                }

                if tool_ctl.rs_cfg_editing == false then
                    table.insert(tmp_cfg.Redstone, def)
                else
                    def.port = tmp_cfg.Redstone[tool_ctl.rs_cfg_editing].port
                    tmp_cfg.Redstone[tool_ctl.rs_cfg_editing] = def
                end
            elseif port == -1 then
                local default_sides = { "left", "back", "right", "front" }
                local default_colors = { colors.red, colors.orange, colors.yellow, colors.lime }
                for i = 0, 3 do
                    table.insert(tmp_cfg.Redstone, {
                        unit = tri(PORT_DSGN[IO.WASTE_PU + i] == 1, u, nil),
                        port = IO.WASTE_PU + i,
                        side = tri(bundled.get_value(), side_options_map[side.get_value()], default_sides[i + 1]),
                        color = tri(bundled.get_value(), default_colors[i + 1], nil)
                    })
                end
            end

            rs_pane.set_value(1)
            tool_ctl.gen_rs_summary(tmp_cfg)

            side.set_value(1)
            bundled.set_value(false)
            tool_ctl.rs_cfg_color.set_value(1)
            tool_ctl.rs_cfg_color.disable()
        else rs_err.show() end
    end

    PushButton{parent=rs_c_3,x=1,y=14,text="\x1b Back",callback=back_from_rs_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_3,x=41,y=14,min_width=9,text="Confirm",callback=save_rs_entry,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_4,x=1,y=1,height=1,text="Settings saved!"}
    PushButton{parent=rs_c_4,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_4,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_5,x=1,y=1,height=5,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=rs_c_5,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_5,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    -- set tool functions now that we have the elements

    -- load a legacy config file
    function tool_ctl.load_legacy()
        local config = require("rtu.config")

        tool_ctl.importing_any_dc = false

        tmp_cfg.SpeakerVolume = config.SOUNDER_VOLUME or 1
        tmp_cfg.SVR_Channel = config.SVR_CHANNEL
        tmp_cfg.RTU_Channel = config.RTU_CHANNEL
        tmp_cfg.ConnTimeout = config.COMMS_TIMEOUT
        tmp_cfg.TrustedRange = config.TRUSTED_RANGE
        tmp_cfg.AuthKey = config.AUTH_KEY or ""
        tmp_cfg.LogMode = config.LOG_MODE
        tmp_cfg.LogPath = config.LOG_PATH
        tmp_cfg.LogDebug = config.LOG_DEBUG or false
        tmp_cfg.Peripherals = {}
        tmp_cfg.Redstone = {}

        local mounts = ppm.list_mounts()

        peri_import_list.remove_all()
        for _, entry in ipairs(config.RTU_DEVICES) do
            local for_facility = entry.for_reactor == 0
            local ini_unit = tri(for_facility, nil, entry.for_reactor)

            local def = { name = entry.name, unit = ini_unit, index = entry.index }
            local mount = mounts[def.name] ---@type ppm_entry|nil

            local status = "  \x13 not connected, please re-config later"
            local color = colors.orange

            if mount ~= nil then
                -- lets make sure things are valid
                local unit, index, err = nil, nil, false
                local u, idx = def.unit, def.index

                if util.table_contains(NEEDS_UNIT, mount.type) then
                    if (mount.type == "dynamicValve" or mount.type == "environmentDetector") and for_facility then
                        -- skip
                    elseif not (util.is_int(u) and u > 0 and u < 5) then
                        err = true
                    else unit = u end
                end

                if mount.type == "boilerValve" then
                    if not (idx == 1 or idx == 2) then
                        err = true
                    else index = idx end
                elseif mount.type == "turbineValve" then
                    if not (idx == 1 or idx == 2 or idx == 3) then
                        err = true
                    else index = idx end
                elseif mount.type == "dynamicValve" and for_facility then
                    if not (util.is_int(idx) and idx > 0 and idx < 5) then
                        err = true
                    else index = idx end
                elseif mount.type == "dynamicValve" then
                    index = 1
                elseif mount.type == "environmentDetector" then
                    if not (util.is_int(idx) and idx > 0) then
                        err = true
                    else index = idx end
                end

                if err then
                    status = "  \x13 invalid, please re-config later"
                else
                    def.index = index
                    def.unit = unit
                    status = "  \x04 validated"
                    color = colors.green
                end
            else tool_ctl.importing_any_dc = true end

            table.insert(tmp_cfg.Peripherals, def)

            local desc = "  \x1a "

            if type(def.index) == "number" then
                desc = desc .. "#" .. def.index .. " "
            end

            if type(def.unit) == "number" then
                desc = desc .. "for unit " .. def.unit
            else
                desc = desc .. "for the facility"
            end

            local line = Div{parent=peri_import_list,height=3}
            TextBox{parent=line,x=1,y=1,height=1,text="@ "..def.name,fg_bg=cpair(colors.black,colors.white)}
            TextBox{parent=line,x=1,y=2,height=1,text=status,fg_bg=cpair(color,colors.white)}
            TextBox{parent=line,x=1,y=3,height=1,text=desc,fg_bg=cpair(colors.gray,colors.white)}
        end

        rs_import_list.remove_all()
        for _, entry in ipairs(config.RTU_REDSTONE) do
            if entry.for_reactor == 0 then entry.for_reactor = nil end
            for _, io_entry in ipairs(entry.io) do
                local def = { unit = entry.for_reactor, port = io_entry.port, side = io_entry.side, color = io_entry.bundled_color }
                table.insert(tmp_cfg.Redstone, def)

                local name = rsio.to_string(def.port)
                local io_dir = tri(rsio.get_io_dir(def.port) == rsio.IO_DIR.IN, "\x1a", "\x1b")
                local conn = def.side
                local unit = "facility"

                if def.unit then unit = "unit " .. def.unit end
                if def.color ~= nil then conn = def.side .. "/" .. rsio.color_name(def.color) end

                local line = Div{parent=rs_import_list,height=1}
                TextBox{parent=line,x=1,y=1,width=1,height=1,text=io_dir,fg_bg=cpair(colors.lightGray,colors.white)}
                TextBox{parent=line,x=2,y=1,width=14,height=1,text=name}
                TextBox{parent=line,x=18,y=1,width=string.len(conn),height=1,text=conn,fg_bg=cpair(colors.gray,colors.white)}
                TextBox{parent=line,x=40,y=1,height=1,text=unit,fg_bg=cpair(colors.gray,colors.white)}
            end
        end

        tool_ctl.gen_summary(tmp_cfg)
        if tool_ctl.importing_any_dc then sum_pane.set_value(7) else sum_pane.set_value(1) end
        main_pane.set_value(6)
        tool_ctl.settings_apply.hide(true)
        tool_ctl.settings_confirm.show()
        tool_ctl.importing_legacy = true
    end

    -- go back to the home page
    function tool_ctl.go_home()
        tool_ctl.viewing_config = false
        tool_ctl.importing_legacy = false
        tool_ctl.importing_any_dc = false

        main_pane.set_value(1)
        net_pane.set_value(1)
        clr_pane.set_value(1)
        sum_pane.set_value(1)
        peri_pane.set_value(1)
        rs_pane.set_value(1)
    end

    -- expose the auth key on the summary page
    function tool_ctl.show_auth_key()
        tool_ctl.show_key_btn.disable()
        tool_ctl.auth_key_textbox.set_value(tool_ctl.auth_key_value)
    end

    -- generate the summary list
    ---@param cfg rtu_config
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
            elseif f[1] == "LogMode" then val = tri(raw == log.MODE.APPEND, "append", "replace")
            elseif f[1] == "FrontPanelTheme" then
                val = util.strval(themes.fp_theme_name(raw))
            elseif f[1] == "ColorMode" then
                val = util.strval(themes.color_mode_name(raw))
            end

            if val == "nil" then val = "<not set>" end

            local c = tri(alternate, g_lg_fg_bg, cpair(colors.gray,colors.white))
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

    ---@param def rtu_peri_definition
    ---@param idx integer
    ---@param type string
    local function edit_peri_entry(idx, def, type)
        -- set inputs BEFORE calling new_peri()
        if def.index ~= nil then tool_ctl.p_idx.set_value(def.index) end
        if def.unit == nil then
            tool_ctl.p_assign_btn.set_value(1)
        else
            tool_ctl.p_unit.set_value(def.unit)
            tool_ctl.p_assign_btn.set_value(2)
        end

        new_peri(def.name, type)

        -- set editing mode AFTER new_peri()
        tool_ctl.peri_cfg_editing = idx
    end

    local function delete_peri_entry(idx)
        table.remove(tmp_cfg.Peripherals, idx)
        tool_ctl.gen_peri_summary(tmp_cfg)
        tool_ctl.update_peri_list()
    end

    -- generate the peripherals summary list
    ---@param cfg rtu_config
    function tool_ctl.gen_peri_summary(cfg)
        peri_list.remove_all()

        for i = 1, #cfg.Peripherals do
            local def = cfg.Peripherals[i]  ---@type rtu_peri_definition

            local t = ppm.get_type(def.name)
            local t_str = "<disconnected> (connect to edit)"
            local disconnected = t == nil

            if not disconnected then t_str = "[" .. t .. "]" end

            local desc = "  \x1a "

            if type(def.index) == "number" then
                desc = desc .. "#" .. def.index .. " "
            end

            if type(def.unit) == "number" then
                desc = desc .. "for unit " .. def.unit
            else
                desc = desc .. "for the facility"
            end

            local entry = Div{parent=peri_list,height=3}
            TextBox{parent=entry,x=1,y=1,height=1,text="@ "..def.name,fg_bg=cpair(colors.black,colors.white)}
            TextBox{parent=entry,x=1,y=2,height=1,text="  \x1a "..t_str,fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=entry,x=1,y=3,height=1,text=desc,fg_bg=cpair(colors.gray,colors.white)}
            local edit_btn = PushButton{parent=entry,x=41,y=2,min_width=8,height=1,text="EDIT",callback=function()edit_peri_entry(i,def,t or "")end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
            PushButton{parent=entry,x=41,y=3,min_width=8,height=1,text="DELETE",callback=function()delete_peri_entry(i)end,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}

            if disconnected then edit_btn.disable() end
        end
    end

    local function edit_rs_entry(idx)
        local def = tmp_cfg.Redstone[idx]   ---@type rtu_rs_definition

        tool_ctl.rs_cfg_shortcut.hide(true)
        tool_ctl.rs_cfg_color.show()

        tool_ctl.rs_cfg_port = def.port
        tool_ctl.rs_cfg_editing = idx

        local text = "Editing " .. rsio.to_string(def.port) .. " (for "
        if PORT_DSGN[def.port] == 1 then
            text = text .. "a unit)."
            tool_ctl.rs_cfg_unit_l.show()
            tool_ctl.rs_cfg_unit.show()
            tool_ctl.rs_cfg_unit.set_value(def.unit or 1)
        else
            tool_ctl.rs_cfg_unit_l.hide(true)
            tool_ctl.rs_cfg_unit.hide(true)
            text = text .. "the facility)."
        end

        local value = 1
        if def.color ~= nil then
            value = color_to_idx(def.color)
            tool_ctl.rs_cfg_color.enable()
        else
            tool_ctl.rs_cfg_color.disable()
        end

        tool_ctl.rs_cfg_selection.set_value(text)
        tool_ctl.rs_cfg_side_l.set_value(tri(rsio.get_io_dir(def.port) == rsio.IO_DIR.IN, "Input Side", "Output Side"))
        side.set_value(side_to_idx(def.side))
        bundled.set_value(def.color ~= nil)
        tool_ctl.rs_cfg_color.set_value(value)
        rs_pane.set_value(3)
    end

    local function delete_rs_entry(idx)
        table.remove(tmp_cfg.Redstone, idx)
        tool_ctl.gen_rs_summary(tmp_cfg)
    end

    -- generate the redstone summary list
    ---@param cfg rtu_config
    function tool_ctl.gen_rs_summary(cfg)
        rs_list.remove_all()

        for i = 1, #cfg.Redstone do
            local def = cfg.Redstone[i]   ---@type rtu_rs_definition

            local name = rsio.to_string(def.port)
            local io_dir = tri(rsio.get_io_mode(def.port) == rsio.IO_DIR.IN, "\x1a", "\x1b")
            local conn = def.side
            local unit = util.strval(def.unit or "F")

            if def.color ~= nil then conn = def.side .. "/" .. rsio.color_name(def.color) end

            local entry = Div{parent=rs_list,height=1}
            TextBox{parent=entry,x=1,y=1,width=1,height=1,text=io_dir,fg_bg=cpair(colors.lightGray,colors.white)}
            TextBox{parent=entry,x=2,y=1,width=14,height=1,text=name}
            TextBox{parent=entry,x=16,y=1,width=string.len(conn),height=1,text=conn,fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=entry,x=33,y=1,width=1,height=1,text=unit,fg_bg=cpair(colors.gray,colors.white)}
            PushButton{parent=entry,x=35,y=1,min_width=6,height=1,text="EDIT",callback=function()edit_rs_entry(i)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
            PushButton{parent=entry,x=41,y=1,min_width=8,height=1,text="DELETE",callback=function()delete_rs_entry(i)end,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
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

-- run the RTU gateway configurator
---@param ask_config? boolean indicate if this is being called by the startup app due to an invalid configuration
function configurator.configure(ask_config)
    tool_ctl.ask_config = ask_config == true

    load_settings(settings_cfg, true)
    tool_ctl.has_config = load_settings(ini_cfg)
    tmp_cfg.Peripherals = deep_copy_peri(ini_cfg.Peripherals)
    tmp_cfg.Redstone = deep_copy_rs(ini_cfg.Redstone)

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
            elseif event == "peripheral_detach" then
---@diagnostic disable-next-line: discard-returns
                ppm.handle_unmount(param1)
                tool_ctl.update_peri_list()
            elseif event == "peripheral" then
---@diagnostic disable-next-line: discard-returns
                ppm.mount(param1)
                tool_ctl.update_peri_list()
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
