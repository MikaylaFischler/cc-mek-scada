--
-- Configuration GUI
--

local log         = require("scada-common.log")
local rsio        = require("scada-common.rsio")
local tcd         = require("scada-common.tcd")
local util        = require("scada-common.util")

local core        = require("graphics.core")

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

local println = util.println

local cpair = core.cpair

local IO = rsio.IO

local LEFT = core.ALIGN.LEFT
local CENTER = core.ALIGN.CENTER
local RIGHT = core.ALIGN.RIGHT

-- rsio port descriptions
local PORT_DESC = {
    "Facility SCRAM",
    "Facility Acknowledge",
    "Reactor SCRAM",
    "Reactor RPS Reset",
    "Reactor Enable",
    "Unit Acknowledge",
    "Facility Alarm (high prio)",
    "Facility Alarm (any)",
    "Waste Plutonium Valve",
    "Waste Polonium Valve",
    "Waste Po Pellets Valve",
    "Waste Antimatter Valve",
    "Reactor Active",
    "Reactor in Auto Control",
    "RPS Tripped",
    "RPS Auto SCRAM",
    "RPS High Damage",
    "RPS High Temperature",
    "RPS Low Coolant",
    "RPS Excess Heated Coolant",
    "RPS Excess Waste",
    "RPS Insufficient Fuel",
    "RPS PLC Fault",
    "RPS Supervisor Timeout",
    "Unit Alarm",
    "Unit Emergency Cool. Valve"
}

-- designation (0 = facility, 1 = unit)
local PORT_DSGN = { [-1] = 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }

assert(#PORT_DESC == rsio.NUM_PORTS)
assert(#PORT_DSGN == rsio.NUM_PORTS)

-- changes to the config data/format to let the user know
local changes = {}

---@class rtu_rs_definition
---@field unit integer|nil
---@field port IO_PORT
---@field side side
---@field color color|nil

---@class rtu_configurator
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
    rs_cfg_editing = false, ---@type integer|false

    view_gw_cfg = nil,      ---@type graphics_element
    dev_cfg = nil,          ---@type graphics_element
    rs_cfg = nil,           ---@type graphics_element
    settings_apply = nil,   ---@type graphics_element

    go_home = nil,          ---@type function
    gen_summary = nil,      ---@type function
    show_current_cfg = nil, ---@type function
    load_legacy = nil,      ---@type function
    gen_rs_summary = nil,   ---@type function

    show_auth_key = nil,    ---@type function
    show_key_btn = nil,     ---@type graphics_element
    auth_key_textbox = nil, ---@type graphics_element
    auth_key_value = "",

    rs_cfg_selection = nil, ---@type graphics_element
    rs_cfg_unit_l = nil,    ---@type graphics_element
    rs_cfg_unit = nil,      ---@type graphics_element
    rs_cfg_color = nil,     ---@type graphics_element
    rs_cfg_shortcut = nil   ---@type graphics_element
}

---@class rtu_config
local tmp_cfg = {
    SpeakerVolume = 1.0,
    Peripherals = {},
    Redstone = {},
    SVR_Channel = nil,
    RTU_Channel = nil,
    ConnTimeout = nil,
    TrustedRange = nil,
    AuthKey = nil,
    LogMode = 0,
    LogPath = "",
    LogDebug = false
}

---@class rtu_config
local ini_cfg = {}

local fields = {
    { "SpeakerVolume", "Speaker Volume" },
    { "SVR_Channel", "SVR Channel" },
    { "RTU_Channel", "RTU Channel" },
    { "ConnTimeout", "Connection Timeout" },
    { "TrustedRange", "Trusted Range" },
    { "AuthKey", "Facility Auth Key" },
    { "LogMode", "Log Mode" },
    { "LogPath", "Log Path" },
    { "LogDebug","Log Debug Messages" }
}

local side_options = { "Top", "Bottom", "Left", "Right", "Front", "Back" }
local side_options_map = { "top", "bottom", "left", "right", "front", "back" }
local color_options = { "Red", "Orange", "Yellow", "Lime", "Green", "Cyan", "Light Blue", "Blue", "Purple", "Magenta", "Pink", "White", "Light Gray", "Gray", "Black", "Brown" }
local color_options_map = { colors.red, colors.orange, colors.yellow, colors.lime, colors.green, colors.cyan, colors.lightBlue, colors.blue, colors.purple, colors.magenta, colors.pink, colors.white, colors.lightGray, colors.gray, colors.black, colors.brown }

local color_name_map = {
    [colors.red] = "red",
    [colors.orange] = "orange",
    [colors.yellow] = "yellow",
    [colors.lime] = "lime",
    [colors.green] = "green",
    [colors.cyan] = "cyan",
    [colors.lightBlue] = "lightBlue",
    [colors.blue] = "blue",
    [colors.purple] = "purple",
    [colors.magenta] = "magenta",
    [colors.pink] = "pink",
    [colors.white] = "white",
    [colors.lightGray] = "lightGray",
    [colors.gray] = "gray",
    [colors.black] = "black",
    [colors.brown] = "brown"
}

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

-- deep copy a redstone definitions table
local function deep_copy_rs(data)
    local array = {}
    for _, d in ipairs(data) do
        table.insert(array, { unit = d.unit, port = d.port, side = d.side, color = d.color })
    end
    return array
end

-- load data from the settings file
---@param target rtu_config
local function load_settings(target)
    target.SpeakerVolume = settings.get("SpeakerVolume", 1.0)
    target.Peripherals = settings.get("Peripherals", {})
    target.Redstone = settings.get("Redstone", {})

    target.SVR_Channel = settings.get("SVR_Channel", 16240)
    target.RTU_Channel = settings.get("RTU_Channel", 16242)
    target.ConnTimeout = settings.get("ConnTimeout", 5)
    target.TrustedRange = settings.get("TrustedRange", 0)
    target.AuthKey = settings.get("AuthKey", "")
    target.LogMode = settings.get("LogMode", log.MODE.APPEND)
    target.LogPath = settings.get("LogPath", "/log.txt")
    target.LogDebug = settings.get("LogDebug", false)
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
    local summary = Div{parent=root_pane_div,x=1,y=1}
    local changelog = Div{parent=root_pane_div,x=1,y=1}
    local peri_cfg = Div{parent=root_pane_div,x=1,y=1}
    local rs_cfg = Div{parent=root_pane_div,x=1,y=1}

    local main_pane = MultiPane{parent=root_pane_div,x=1,y=1,panes={main_page,spkr_cfg,net_cfg,log_cfg,summary,changelog,peri_cfg,rs_cfg}}

    --#region MAIN PAGE

    local y_start = 5

    TextBox{parent=main_page,x=2,y=2,height=2,text_align=CENTER,text="Welcome to the RTU gateway configurator! Please select one of the following options."}

    if tool_ctl.ask_config then
        TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text_align=CENTER,text="Notice: This device has no valid config so the configurator has been automatically started. If you previously had a valid config, you may want to check the Change Log to see what changed.",fg_bg=cpair(colors.red,colors.lightGray)}
        y_start = y_start + 5
    end

    local function view_config()
        tool_ctl.viewing_config = true
        tool_ctl.gen_summary(ini_cfg)
        tool_ctl.settings_apply.hide(true)
        main_pane.set_value(5)
    end

    if fs.exists("/rtu/config.lua") then
        PushButton{parent=main_page,x=2,y=y_start,min_width=28,text="Import Legacy 'config.lua'",callback=function()tool_ctl.load_legacy()end,fg_bg=cpair(colors.black,colors.cyan),active_fg_bg=btn_act_fg_bg}
        y_start = y_start + 2
    end

    local function show_rs_conns()
        tool_ctl.gen_rs_summary(ini_cfg)
        main_pane.set_value(8)
    end

    PushButton{parent=main_page,x=2,y=y_start,min_width=19,text="Configure Gateway",callback=function()main_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    tool_ctl.view_gw_cfg = PushButton{parent=main_page,x=2,y=y_start+2,min_width=28,text="View Gateway Configuration",callback=view_config,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    tool_ctl.dev_cfg = PushButton{parent=main_page,x=2,y=y_start+4,min_width=18,text="RTU Unit Devices",callback=function()main_pane.set_value(7)end,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    tool_ctl.rs_cfg = PushButton{parent=main_page,x=2,y=y_start+6,min_width=22,text="Redstone Connections",callback=show_rs_conns,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}

    if not tool_ctl.has_config then
        tool_ctl.view_gw_cfg.disable()
        -- tool_ctl.dev_cfg.disable()
        -- tool_ctl.rs_cfg.disable()
    end

    PushButton{parent=main_page,x=2,y=17,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=main_page,x=39,y=17,min_width=12,text="Change Log",callback=function()main_pane.set_value(6)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region SPEAKER CONFIG

    local spkr_c = Div{parent=spkr_cfg,x=2,y=4,width=49}

    TextBox{parent=spkr_cfg,x=1,y=2,height=1,text_align=CENTER,text=" Speaker Configuration",fg_bg=cpair(colors.black,colors.cyan)}

    TextBox{parent=spkr_c,x=1,y=1,height=2,text_align=CENTER,text="Speakers can be connected to this RTU gateway without RTU unit configuration entries."}
    TextBox{parent=spkr_c,x=1,y=4,height=3,text_align=CENTER,text="You can change the speaker audio volume from the default. The range is 0.0 to 3.0, where 1.0 is standard volume."}

    local s_vol = NumberField{parent=spkr_c,x=1,y=8,width=9,max_digits=7,allow_decimal=true,default=ini_cfg.SpeakerVolume,min=0,max=3,fg_bg=bw_fg_bg}

    TextBox{parent=spkr_c,x=1,y=10,height=3,text_align=CENTER,text="Note: alarm sine waves are at half scale so that multiple will be required to reach full scale.",fg_bg=g_lg_fg_bg}

    local s_vol_err = TextBox{parent=spkr_c,x=8,y=14,height=1,width=35,text_align=LEFT,text="Please set a volume.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_vol()
        local vol = tonumber(s_vol.get_value())
        if vol ~= nil then
            s_vol_err.hide(true)
            tmp_cfg.SpeakerVolume = vol
            main_pane.set_value(3)
        else s_vol_err.show() end
    end

    PushButton{parent=spkr_c,x=1,y=14,min_width=6,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=spkr_c,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_vol,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region NET CONFIG

    local net_c_1 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_2 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_3 = Div{parent=net_cfg,x=2,y=4,width=49}

    local net_pane = MultiPane{parent=net_cfg,x=1,y=4,panes={net_c_1,net_c_2,net_c_3}}

    TextBox{parent=net_cfg,x=1,y=2,height=1,text_align=CENTER,text=" Network Configuration",fg_bg=cpair(colors.black,colors.lightBlue)}

    TextBox{parent=net_c_1,x=1,y=1,height=1,text_align=CENTER,text="Please set the network channels below."}
    TextBox{parent=net_c_1,x=1,y=3,height=4,text_align=CENTER,text="Each of the 5 uniquely named channels, including the 2 below, must be the same for each device in this SCADA network. For multiplayer servers, it is recommended to not use the default channels.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=8,height=1,text_align=CENTER,text="Supervisor Channel"}
    local svr_chan = NumberField{parent=net_c_1,x=1,y=9,width=7,default=ini_cfg.SVR_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=9,height=4,text_align=CENTER,text="[SVR_CHANNEL]",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_1,x=1,y=11,height=1,text_align=CENTER,text="RTU Channel"}
    local rtu_chan = NumberField{parent=net_c_1,x=1,y=12,width=7,default=ini_cfg.RTU_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=12,height=4,text_align=CENTER,text="[RTU_CHANNEL]",fg_bg=g_lg_fg_bg}

    local chan_err = TextBox{parent=net_c_1,x=8,y=14,height=1,width=35,text_align=LEFT,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

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

    PushButton{parent=net_c_1,x=1,y=14,min_width=6,text="\x1b Back",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_1,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_channels,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_2,x=1,y=1,height=1,text_align=CENTER,text="Connection Timeout"}
    local timeout = NumberField{parent=net_c_2,x=1,y=2,width=7,default=ini_cfg.ConnTimeout,min=2,max=25,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_2,x=9,y=2,height=2,text_align=CENTER,text="seconds (default 5)",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_2,x=1,y=3,height=4,text_align=CENTER,text="You generally do not want or need to modify this. On slow servers, you can increase this to make the system wait longer before assuming a disconnection.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_2,x=1,y=8,height=1,text_align=CENTER,text="Trusted Range"}
    local range = NumberField{parent=net_c_2,x=1,y=9,width=10,default=ini_cfg.TrustedRange,min=0,max_digits=20,allow_decimal=true,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_2,x=1,y=10,height=4,text_align=CENTER,text="Setting this to a value larger than 0 prevents connections with devices that many meters (blocks) away in any direction.",fg_bg=g_lg_fg_bg}

    local p2_err = TextBox{parent=net_c_2,x=8,y=14,height=1,width=35,text_align=LEFT,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

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

    PushButton{parent=net_c_2,x=1,y=14,min_width=6,text="\x1b Back",callback=function()net_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_2,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_ct_tr,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_3,x=1,y=1,height=2,text_align=CENTER,text="Optionally, set the facility authentication key below. Do NOT use one of your passwords."}
    TextBox{parent=net_c_3,x=1,y=4,height=6,text_align=CENTER,text="This enables verifying that messages are authentic, so it is intended for security on multiplayer servers. All devices on the same network MUST use the same key if any device has a key. This does result in some extra compution (can slow things down).",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_3,x=1,y=11,height=1,text_align=CENTER,text="Facility Auth Key"}
    local key, _, censor = TextField{parent=net_c_3,x=1,y=12,max_len=64,value=ini_cfg.AuthKey,width=32,height=1,fg_bg=bw_fg_bg}

    local function censor_key(enable) censor(util.trinary(enable, "*", nil)) end

    local hide_key = CheckBox{parent=net_c_3,x=34,y=12,label="Hide",box_fg_bg=cpair(colors.lightBlue,colors.black),callback=censor_key}

    hide_key.set_value(true)
    censor_key(true)

    local key_err = TextBox{parent=net_c_3,x=8,y=14,height=1,width=35,text_align=LEFT,text="Key must be at least 8 characters.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_auth()
        local v = key.get_value()
        if string.len(v) == 0 or string.len(v) >= 8 then
            tmp_cfg.AuthKey = key.get_value()
            main_pane.set_value(4)
            key_err.hide(true)
        else key_err.show() end
    end

    PushButton{parent=net_c_3,x=1,y=14,min_width=6,text="\x1b Back",callback=function()net_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_3,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_auth,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region LOG CONFIG

    local log_c_1 = Div{parent=log_cfg,x=2,y=4,width=49}

    TextBox{parent=log_cfg,x=1,y=2,height=1,text_align=CENTER,text=" Logging Configuration",fg_bg=cpair(colors.black,colors.pink)}

    TextBox{parent=log_c_1,x=1,y=1,height=1,text_align=CENTER,text="Please configure logging below."}

    TextBox{parent=log_c_1,x=1,y=3,height=1,text_align=CENTER,text="Log File Mode"}
    local mode = RadioButton{parent=log_c_1,x=1,y=4,default=ini_cfg.LogMode+1,options={"Append on Startup","Replace on Startup"},callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.pink}

    TextBox{parent=log_c_1,x=1,y=7,height=1,text_align=CENTER,text="Log File Path"}
    local path = TextField{parent=log_c_1,x=1,y=8,width=49,height=1,value=ini_cfg.LogPath,max_len=128,fg_bg=bw_fg_bg}

    local en_dbg = CheckBox{parent=log_c_1,x=1,y=10,default=ini_cfg.LogDebug,label="Enable Logging Debug Messages",box_fg_bg=cpair(colors.pink,colors.black)}
    TextBox{parent=log_c_1,x=3,y=11,height=2,text_align=CENTER,text="This results in much larger log files. It is best to only use this when there is a problem.",fg_bg=g_lg_fg_bg}

    local path_err = TextBox{parent=log_c_1,x=8,y=14,height=1,width=35,text_align=LEFT,text="Please provide a log file path.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

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

    PushButton{parent=log_c_1,x=1,y=14,min_width=6,text="\x1b Back",callback=function()main_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=log_c_1,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_log,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region SUMMARY OF CHANGES

    local sum_c_1 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_2 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_3 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_4 = Div{parent=summary,x=2,y=4,width=49}

    local sum_pane = MultiPane{parent=summary,x=1,y=4,panes={sum_c_1,sum_c_2,sum_c_3,sum_c_4}}

    TextBox{parent=summary,x=1,y=2,height=1,text_align=CENTER,text=" Summary",fg_bg=cpair(colors.black,colors.green)}

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
        for k, v in pairs(tmp_cfg) do settings.set(k, v) end

        if settings.save("rtu.settings") then
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

            if tool_ctl.importing_legacy then
                tool_ctl.importing_legacy = false
                sum_pane.set_value(3)
            else sum_pane.set_value(2) end
        else sum_pane.set_value(4) end
    end

    PushButton{parent=sum_c_1,x=1,y=14,min_width=6,text="\x1b Back",callback=back_from_settings,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.show_key_btn = PushButton{parent=sum_c_1,x=8,y=14,min_width=17,text="Unhide Auth Key",callback=function()tool_ctl.show_auth_key()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    tool_ctl.settings_apply = PushButton{parent=sum_c_1,x=43,y=14,min_width=7,text="Apply",callback=save_and_continue,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_2,x=1,y=1,height=1,text_align=CENTER,text="Settings saved!"}

    PushButton{parent=sum_c_2,x=1,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_2,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_3,x=1,y=1,height=2,text_align=CENTER,text="The old config.lua file will now be deleted, then the configurator will exit."}

    local function delete_legacy()
        fs.delete("/rtu/config.lua")
        exit()
    end

    PushButton{parent=sum_c_3,x=1,y=14,min_width=8,text="Cancel",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_3,x=44,y=14,min_width=6,text="OK",callback=delete_legacy,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_4,x=1,y=1,height=5,text_align=CENTER,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}

    PushButton{parent=sum_c_4,x=1,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_4,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    --#endregion

    --#region CONFIG CHANGE LOG

    local cl = Div{parent=changelog,x=2,y=4,width=49}

    TextBox{parent=changelog,x=1,y=2,height=1,text_align=CENTER,text=" Config Change Log",fg_bg=bw_fg_bg}

    local c_log = ListBox{parent=cl,x=1,y=1,height=12,width=51,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    for _, change in ipairs(changes) do
        TextBox{parent=c_log,text=change[1],height=1,fg_bg=bw_fg_bg}
        for _, v in ipairs(change[2]) do
            local e = Div{parent=c_log,height=#util.strwrap(v,46)}
            TextBox{parent=e,y=1,x=1,text="- ",height=1,fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=e,y=1,x=3,text=v,height=e.get_height(),fg_bg=cpair(colors.gray,colors.white)}
        end
    end

    PushButton{parent=cl,x=1,y=14,min_width=6,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region REDSTONE

    local rs_c_1 = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_2 = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_3 = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_4 = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_5 = Div{parent=rs_cfg,x=2,y=4,width=49}

    local rs_pane = MultiPane{parent=rs_cfg,x=1,y=4,panes={rs_c_1,rs_c_2,rs_c_3,rs_c_4,rs_c_5}}

    TextBox{parent=rs_cfg,x=1,y=2,height=1,text_align=CENTER,text=" Redstone Connections",fg_bg=cpair(colors.black,colors.red)}

    TextBox{parent=rs_c_1,x=1,y=1,height=1,text=" port          side/color       unit/facility",fg_bg=g_lg_fg_bg}
    local rs_list = ListBox{parent=rs_c_1,x=1,y=2,height=11,width=51,scroll_height=200,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function rs_revert()
        tmp_cfg.Redstone = deep_copy_rs(ini_cfg.Redstone)
        tool_ctl.gen_rs_summary(tmp_cfg)
    end

    local function rs_apply()
        settings.set("Redstone", tmp_cfg.Redstone)

        if settings.save("rtu.settings") then
            load_settings(ini_cfg)
            rs_pane.set_value(4)
        else
            rs_pane.set_value(5)
        end
    end

    PushButton{parent=rs_c_1,x=1,y=14,min_width=6,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_1,x=8,y=14,min_width=16,text="Revert Changes",callback=rs_revert,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_1,x=35,y=14,min_width=7,text="New +",callback=function()rs_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_1,x=43,y=14,min_width=7,text="Apply",callback=rs_apply,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_2,x=1,y=1,height=1,text="Select one of the below ports to use."}

    local rs_ports = ListBox{parent=rs_c_2,x=1,y=3,height=10,width=51,scroll_height=200,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local new_rs_port = IO.F_SCRAM
    local function new_rs(port)
        tool_ctl.rs_cfg_editing = false

        local text

        if port == -1 then
            tool_ctl.rs_cfg_color.hide(true)
            tool_ctl.rs_cfg_shortcut.show()
            text = "You selected the ALL_WASTE shortcut."
        else
            tool_ctl.rs_cfg_shortcut.hide(true)
            tool_ctl.rs_cfg_color.show()
            text = "You selected " .. rsio.to_string(port) .. " (for "
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
        new_rs_port = port
        rs_pane.set_value(3)
    end

    -- add entries to redstone option list
    local all_w_macro = Div{parent=rs_ports,height=1}
    PushButton{parent=all_w_macro,x=1,y=1,min_width=14,alignment=LEFT,height=1,text=">ALL_WASTE",callback=function()new_rs(-1)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.black)}
    TextBox{parent=all_w_macro,x=16,y=1,width=5,height=1,text="[n/a]",fg_bg=cpair(colors.lightGray,colors.white)}
    TextBox{parent=all_w_macro,x=22,y=1,height=1,text="Create all 4 waste entries",fg_bg=cpair(colors.gray,colors.white)}
    for i = 1, rsio.NUM_PORTS do
        local name = rsio.to_string(i)
        local io_dir = util.trinary(rsio.get_io_mode(i) == rsio.IO_DIR.IN, "[in]", "[out]")
        local btn_color = util.trinary(rsio.get_io_mode(i) == rsio.IO_DIR.IN, colors.yellow, colors.lightBlue)
        local entry = Div{parent=rs_ports,height=1}
        PushButton{parent=entry,x=1,y=1,min_width=14,alignment=LEFT,height=1,text=">"..name,callback=function()new_rs(i)end,fg_bg=cpair(colors.black,btn_color),active_fg_bg=cpair(colors.white,colors.black)}
        TextBox{parent=entry,x=16,y=1,width=5,height=1,text=io_dir,fg_bg=cpair(colors.lightGray,colors.white)}
        TextBox{parent=entry,x=22,y=1,height=1,text=PORT_DESC[i],fg_bg=cpair(colors.gray,colors.white)}
    end

    PushButton{parent=rs_c_2,x=1,y=14,min_width=6,text="\x1b Back",callback=function()rs_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    tool_ctl.rs_cfg_selection = TextBox{parent=rs_c_3,x=1,y=1,height=1,text_align=CENTER,text=""}

    tool_ctl.rs_cfg_unit_l = TextBox{parent=rs_c_3,x=27,y=3,width=7,height=1,text_align=CENTER,text="Unit ID"}
    tool_ctl.rs_cfg_unit = NumberField{parent=rs_c_3,x=27,y=4,width=10,max_digits=2,min=1,max=4,fg_bg=bw_fg_bg}

    TextBox{parent=rs_c_3,x=1,y=3,width=11,height=1,text_align=CENTER,text="Output Side"}
    local side = Radio2D{parent=rs_c_3,x=1,y=4,rows=2,columns=3,default=1,options=side_options,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.red}

    local function set_bundled(bundled)
        if bundled then tool_ctl.rs_cfg_color.enable() else tool_ctl.rs_cfg_color.disable() end
    end

    tool_ctl.rs_cfg_shortcut = TextBox{parent=rs_c_3,x=1,y=9,height=4,text="This shortcut will add entries for each of the 4 waste outputs. If you select bundled, 4 colors will be assigned to the selected side. Otherwise, 4 default sides will be used."}
    tool_ctl.rs_cfg_shortcut.hide(true)

    local bundled = CheckBox{parent=rs_c_3,x=1,y=7,label="Is Bundled?",default=false,box_fg_bg=cpair(colors.red,colors.black),callback=set_bundled}
    tool_ctl.rs_cfg_color = Radio2D{parent=rs_c_3,x=1,y=9,rows=4,columns=4,default=1,options=color_options,radio_colors=cpair(colors.lightGray,colors.black),color_map=color_options_map,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
    tool_ctl.rs_cfg_color.disable()

    local rs_err = TextBox{parent=rs_c_3,x=8,y=14,height=1,width=35,text_align=LEFT,text="Unit ID must be within 1 through 4.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
    rs_err.hide(true)

    local function back_from_rs_opts()
        rs_err.hide(true)
        if tool_ctl.rs_cfg_editing ~= false then rs_pane.set_value(1) else rs_pane.set_value(2) end
    end

    local function save_rs_entry()
        local u = tonumber(tool_ctl.rs_cfg_unit.get_value())

        if PORT_DSGN[new_rs_port] == 0 or (util.is_int(u) and u > 0 and u < 5) then
            rs_err.hide(true)

            if new_rs_port >= 0 then
                ---@type rtu_rs_definition
                local def = {
                    unit = util.trinary(PORT_DSGN[new_rs_port] == 1, u, nil),
                    port = new_rs_port,
                    side = side_options_map[side.get_value()],
                    color = util.trinary(bundled.get_value(), color_options_map[tool_ctl.rs_cfg_color.get_value()], nil)
                }

                if tool_ctl.rs_cfg_editing == false then
                    table.insert(tmp_cfg.Redstone, def)
                else
                    def.port = tmp_cfg.Redstone[tool_ctl.rs_cfg_editing].port
                    tmp_cfg.Redstone[tool_ctl.rs_cfg_editing] = def
                end
            elseif new_rs_port == -1 then
                local default_sides = { "left", "back", "right", "front" }
                local default_colors = { colors.red, colors.orange, colors.yellow, colors.lime }
                for i = 0, 3 do
                    table.insert(tmp_cfg.Redstone, {
                        unit = util.trinary(PORT_DSGN[IO.WASTE_PU + i] == 1, u, nil),
                        port = IO.WASTE_PU + i,
                        side = util.trinary(bundled.get_value(), side_options_map[side.get_value()], default_sides[i + 1]),
                        color = util.trinary(bundled.get_value(), default_colors[i + 1], nil)
                    })
                end
            end

            rs_pane.set_value(1)
            tool_ctl.gen_rs_summary(tmp_cfg)

            side.set_value(1)
            bundled.set_value(false)
            tool_ctl.rs_cfg_color.set_value(1)
            tool_ctl.rs_cfg_color.disable()
        else
            rs_err.show()
        end
    end

    PushButton{parent=rs_c_3,x=1,y=14,min_width=6,text="\x1b Back",callback=back_from_rs_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_3,x=44,y=14,min_width=6,text="Save",callback=save_rs_entry,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_4,x=1,y=1,height=1,text_align=CENTER,text="Settings saved!"}
    PushButton{parent=rs_c_4,x=1,y=14,min_width=6,text="\x1b Back",callback=function()rs_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_4,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_5,x=1,y=1,height=5,text_align=CENTER,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=rs_c_5,x=1,y=14,min_width=6,text="\x1b Back",callback=function()rs_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_5,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    -- set tool functions now that we have the elements

    -- load a legacy config file
    function tool_ctl.load_legacy()
        local config = require("rtu.config")

        tmp_cfg.SpeakerVolume = config.SOUNDER_VOLUME
        tmp_cfg.SVR_Channel = config.SVR_CHANNEL
        tmp_cfg.RTU_Channel = config.RTU_CHANNEL
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

    -- go back to the home page
    function tool_ctl.go_home()
        main_pane.set_value(1)
        net_pane.set_value(1)
        sum_pane.set_value(1)
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

            if f[1] == "AuthKey" then val = string.rep("*", string.len(val)) end
            if f[1] == "LogMode" then val = util.trinary(raw == log.MODE.APPEND, "append", "replace") end
            if val == "nil" then val = "n/a" end

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

    local function edit_rs_entry(idx)
        local def = tmp_cfg.Redstone[idx]   ---@type rtu_rs_definition

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
            local io_dir = util.trinary(rsio.get_io_mode(def.port) == rsio.IO_DIR.IN, "\x1a", "\x1b")
            local conn = def.side
            local unit = util.strval(def.unit or "F")

            if def.color ~= nil then
                conn = def.side .. "/" .. color_name_map[def.color]
            end

            local entry = Div{parent=rs_list,height=1}
            TextBox{parent=entry,x=1,y=1,width=1,height=1,text=io_dir,fg_bg=cpair(colors.lightGray,colors.white)}
            TextBox{parent=entry,x=2,y=1,width=14,height=1,text=name}
            TextBox{parent=entry,x=16,y=1,width=string.len(conn),height=1,text=conn,fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=entry,x=33,y=1,width=1,height=1,text=unit,fg_bg=cpair(colors.gray,colors.white)}
            PushButton{parent=entry,x=35,y=1,min_width=6,height=1,text="EDIT",callback=function()edit_rs_entry(i)end,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}
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
---@param ask_config? boolean indicate if this is being called by the RTU startup app due to an invalid configuration
function configurator.configure(ask_config)
    tool_ctl.ask_config = ask_config == true
    tool_ctl.has_config = settings.load("/rtu.settings")

    load_settings(ini_cfg)

    tmp_cfg.Redstone = deep_copy_rs(ini_cfg.Redstone)

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
                -- notify timer callback dispatcher
                tcd.handle(param1)
            elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or event == "double_click" then
                -- handle a mouse event
                local m_e = core.events.new_mouse_event(event, param1, param2, param3)
                if m_e then display.handle_mouse(m_e) end
            elseif event == "char" or event == "key" or event == "key_up" then
                -- handle a key event
                local k_e = core.events.new_key_event(event, param1, param2)
                if k_e then display.handle_key(k_e) end
            elseif event == "paste" then
                -- handle a paste event
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
