--
-- Configuration GUI
--

local comms       = require("scada-common.comms")
local log         = require("scada-common.log")
local network     = require("scada-common.network")
local ppm         = require("scada-common.ppm")
local tcd         = require("scada-common.tcd")
local util        = require("scada-common.util")
local themes      = require("graphics.themes")

local core        = require("graphics.core")

local DisplayBox  = require("graphics.elements.displaybox")
local Div         = require("graphics.elements.div")
local ListBox     = require("graphics.elements.listbox")
local MultiPane   = require("graphics.elements.multipane")
local TextBox     = require("graphics.elements.textbox")

local CheckBox    = require("graphics.elements.controls.checkbox")
local PushButton  = require("graphics.elements.controls.push_button")
local RadioButton = require("graphics.elements.controls.radio_button")

local NumberField = require("graphics.elements.form.number_field")
local TextField   = require("graphics.elements.form.text_field")

local IndLight    = require("graphics.elements.indicators.light")

local println = util.println
local tri = util.trinary

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE = comms.MGMT_TYPE

local cpair = core.cpair

local LEFT = core.ALIGN.LEFT
local CENTER = core.ALIGN.CENTER
local RIGHT = core.ALIGN.RIGHT

-- changes to the config data/format to let the user know
local changes = {
    { "v1.2.4", { "Added temperature scale options" } },
    { "v1.2.12", { "Added main UI theme", "Added front panel UI theme", "Added color accessibility modes" } },
    { "v1.3.3", { "Added standard with black off state color mode", "Added blue indicator color modes" } }
}

---@class crd_configurator
local configurator = {}

local style = {}

style.root = cpair(colors.black, colors.lightGray)
style.header = cpair(colors.white, colors.gray)

style.colors = themes.smooth_stone.colors

local bw_fg_bg = cpair(colors.black, colors.white)
local g_lg_fg_bg = cpair(colors.gray, colors.lightGray)
local nav_fg_bg = bw_fg_bg
local btn_act_fg_bg = cpair(colors.white, colors.gray)
local dis_fg_bg = cpair(colors.lightGray,colors.white)

---@class _crd_cfg_tool_ctl
local tool_ctl = {
    nic = nil,              ---@type nic
    net_listen = false,
    sv_addr = comms.BROADCAST,
    sv_seq_num = 0,
    sv_cool_conf = nil,     ---@type table list of boiler & turbine counts
    show_sv_cfg = nil,      ---@type function

    start_fail = 0,
    fail_message = "",
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

    sv_connect = nil,       ---@type function
    sv_conn_button = nil,   ---@type graphics_element
    sv_conn_status = nil,   ---@type graphics_element
    sv_conn_detail = nil,   ---@type graphics_element
    sv_skip = nil,          ---@type graphics_element
    sv_next = nil,          ---@type graphics_element

    apply_mon = nil,        ---@type graphics_element

    update_mon_reqs = nil,  ---@type function
    gen_mon_list = function () end,
    edit_monitor = nil,     ---@type function

    mon_iface = "",
    mon_expect = {}
}

---@class crd_config
local tmp_cfg = {
    UnitCount = 1,
    SpeakerVolume = 1.0,
    Time24Hour = true,
    TempScale = 1,
    DisableFlowView = false,
    MainDisplay = nil,  ---@type string
    FlowDisplay = nil,  ---@type string
    UnitDisplays = {},
    SVR_Channel = nil,  ---@type integer
    CRD_Channel = nil,  ---@type integer
    PKT_Channel = nil,  ---@type integer
    SVR_Timeout = nil,  ---@type number
    API_Timeout = nil,  ---@type number
    TrustedRange = nil, ---@type number
    AuthKey = nil,      ---@type string|nil
    LogMode = 0,
    LogPath = "",
    LogDebug = false,
    MainTheme = 1,
    FrontPanelTheme = 1,
    ColorMode = 1
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
    { "TempScale", "Temperature Scale", 1 },
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

-- check if a value is an integer within a range (inclusive)
---@param x integer
---@param min integer
---@param max integer
local function is_int_min_max(x, min, max) return util.is_int(x) and x >= min and x <= max end

-- send a management packet to the supervisor
---@param msg_type MGMT_TYPE
---@param msg table
local function send_sv(msg_type, msg)
    local s_pkt = comms.scada_packet()
    local pkt = comms.mgmt_packet()

    pkt.make(msg_type, msg)
    s_pkt.make(tool_ctl.sv_addr, tool_ctl.sv_seq_num, PROTOCOL.SCADA_MGMT, pkt.raw_sendable())

    tool_ctl.nic.transmit(tmp_cfg.SVR_Channel, tmp_cfg.CRD_Channel, s_pkt)
    tool_ctl.sv_seq_num = tool_ctl.sv_seq_num + 1
end

-- handle an establish message from the supervisor
---@param packet mgmt_frame
local function handle_packet(packet)
    local error_msg = nil

    if packet.scada_frame.local_channel() ~= tmp_cfg.CRD_Channel then
        error_msg = "Error: unknown receive channel."
    elseif packet.scada_frame.remote_channel() == tmp_cfg.SVR_Channel and packet.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
        if packet.type == MGMT_TYPE.ESTABLISH then
            if packet.length == 2 then
                local est_ack = packet.data[1]
                local config = packet.data[2]

                if est_ack == ESTABLISH_ACK.ALLOW then
                    if type(config) == "table" and #config == 2 then
                        local count_ok = is_int_min_max(config[1], 1, 4)
                        local cool_ok = type(config[2]) == "table" and type(config[2].r_cool) == "table" and #config[2].r_cool == config[1]

                        if count_ok and cool_ok then
                            tmp_cfg.UnitCount = config[1]
                            tool_ctl.sv_cool_conf = {}

                            for i = 1, tmp_cfg.UnitCount do
                                local num_b = config[2].r_cool[i].BoilerCount
                                local num_t = config[2].r_cool[i].TurbineCount
                                tool_ctl.sv_cool_conf[i] = { num_b, num_t }
                                cool_ok = cool_ok and is_int_min_max(num_b, 0, 2) and is_int_min_max(num_t, 1, 3)
                            end
                        end

                        if not count_ok then
                            error_msg = "Error: supervisor unit count out of range."
                        elseif not cool_ok then
                            error_msg = "Error: supervisor cooling configuration malformed."
                            tool_ctl.sv_cool_conf = nil
                        end

                        tool_ctl.sv_addr = packet.scada_frame.src_addr()
                        send_sv(MGMT_TYPE.CLOSE, {})
                    else
                        error_msg = "Error: invalid cooling configuration supervisor."
                    end
                else
                    error_msg = "Error: invalid allow reply length from supervisor."
                end
            elseif packet.length == 1 then
                local est_ack = packet.data[1]

                if est_ack == ESTABLISH_ACK.DENY then
                    error_msg = "Error: supervisor connection denied."
                elseif est_ack == ESTABLISH_ACK.COLLISION then
                    error_msg = "Error: a coordinator is already/still connected. Please try again."
                elseif est_ack == ESTABLISH_ACK.BAD_VERSION then
                    error_msg = "Error: coordinator comms version does not match supervisor comms version."
                else
                    error_msg = "Error: invalid reply from supervisor."
                end
            else
                error_msg = "Error: invalid reply length from supervisor."
            end
        else
            error_msg = "Error: didn't get an establish reply from supervisor."
        end
    end

    tool_ctl.net_listen = false

    if error_msg then
        tool_ctl.sv_conn_status.set_value("")
        tool_ctl.sv_conn_detail.set_value(error_msg)
        tool_ctl.sv_conn_button.enable()
    else
        tool_ctl.sv_conn_status.set_value("Connected!")
        tool_ctl.sv_conn_detail.set_value("Data received successfully, press 'Next' to continue.")
        tool_ctl.sv_skip.hide()
        tool_ctl.sv_next.show()
    end
end

-- handle supervisor connection failure
local function handle_timeout()
    tool_ctl.net_listen = false
    tool_ctl.sv_conn_button.enable()
    tool_ctl.sv_conn_status.set_value("Timed out.")
    tool_ctl.sv_conn_detail.set_value("Supervisor did not reply. Ensure startup app is running on the supervisor.")
end

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
---@param display graphics_element
local function config_view(display)
---@diagnostic disable-next-line: undefined-field
    local function exit() os.queueEvent("terminate") end

    TextBox{parent=display,y=1,text="Coordinator Configurator",alignment=CENTER,height=1,fg_bg=style.header}

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

    -- Main Page

    local y_start = 5

    TextBox{parent=main_page,x=2,y=2,height=2,text="Welcome to the Coordinator configurator! Please select one of the following options."}

    if tool_ctl.start_fail == 2 then
        local msg = util.c("Notice: There is a problem with your monitor configuration. ", tool_ctl.fail_message, " Please reconfigure monitors or correct their sizes.")
        TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text=msg,fg_bg=cpair(colors.red,colors.lightGray)}
        y_start = y_start + 5
    elseif tool_ctl.start_fail > 0 then
        TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text="Notice: This device has no valid config so the configurator has been automatically started. If you previously had a valid config, you may want to check the Change Log to see what changed.",fg_bg=cpair(colors.red,colors.lightGray)}
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
    tool_ctl.view_cfg = PushButton{parent=main_page,x=2,y=y_start+2,min_width=20,text="View Configuration",callback=view_config,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=dis_fg_bg}

    local function jump_color()
        tool_ctl.jumped_to_color = true
        tool_ctl.color_next.hide(true)
        tool_ctl.color_apply.show()
        main_pane.set_value(8)
    end

    PushButton{parent=main_page,x=2,y=17,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
    tool_ctl.color_cfg = PushButton{parent=main_page,x=23,y=17,min_width=15,text="Color Options",callback=jump_color,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    PushButton{parent=main_page,x=39,y=17,min_width=12,text="Change Log",callback=function()main_pane.set_value(10)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    if not tool_ctl.has_config then
        tool_ctl.view_cfg.disable()
        tool_ctl.color_cfg.disable()
    end

    --#region Network

    local net_c_1 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_2 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_3 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_4 = Div{parent=net_cfg,x=2,y=4,width=49}

    local net_pane = MultiPane{parent=net_cfg,x=1,y=4,panes={net_c_1,net_c_2,net_c_3,net_c_4}}

    TextBox{parent=net_cfg,x=1,y=2,height=1,text=" Network Configuration",fg_bg=cpair(colors.black,colors.lightBlue)}

    TextBox{parent=net_c_1,x=1,y=1,height=1,text="Please set the network channels below."}
    TextBox{parent=net_c_1,x=1,y=3,height=4,text="Each of the 5 uniquely named channels, including the 3 below, must be the same for each device in this SCADA network. For multiplayer servers, it is recommended to not use the default channels.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=8,height=1,width=18,text="Supervisor Channel"}
    local svr_chan = NumberField{parent=net_c_1,x=21,y=8,width=7,default=ini_cfg.SVR_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=29,y=8,height=4,text="[SVR_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=10,height=1,width=19,text="Coordinator Channel"}
    local crd_chan = NumberField{parent=net_c_1,x=21,y=10,width=7,default=ini_cfg.CRD_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=29,y=10,height=4,text="[CRD_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=12,height=1,width=14,text="Pocket Channel"}
    local pkt_chan = NumberField{parent=net_c_1,x=21,y=12,width=7,default=ini_cfg.PKT_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=29,y=12,height=4,text="[PKT_CHANNEL]",fg_bg=g_lg_fg_bg}

    local chan_err = TextBox{parent=net_c_1,x=8,y=14,height=1,width=35,text="Please set all channels.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_channels()
        local svr_c, crd_c, pkt_c = tonumber(svr_chan.get_value()), tonumber(crd_chan.get_value()), tonumber(pkt_chan.get_value())
        if svr_c ~= nil and crd_c ~= nil and pkt_c ~= nil then
            tmp_cfg.SVR_Channel, tmp_cfg.CRD_Channel, tmp_cfg.PKT_Channel = svr_c, crd_c, pkt_c
            net_pane.set_value(2)
            chan_err.hide(true)
        else chan_err.show() end
    end

    PushButton{parent=net_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_1,x=44,y=14,text="Next \x1a",callback=submit_channels,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_2,x=1,y=1,height=1,text="Please set the connection timeouts below."}
    TextBox{parent=net_c_2,x=1,y=3,height=4,text="You generally should not need to modify these. On slow servers, you can try to increase this to make the system wait longer before assuming a disconnection. The default for all is 5 seconds.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_2,x=1,y=8,height=1,width=19,text="Supervisor Timeout"}
    local svr_timeout = NumberField{parent=net_c_2,x=20,y=8,width=7,default=ini_cfg.SVR_Timeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=net_c_2,x=1,y=10,height=1,width=14,text="Pocket Timeout"}
    local api_timeout = NumberField{parent=net_c_2,x=20,y=10,width=7,default=ini_cfg.API_Timeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=net_c_2,x=28,y=8,height=4,width=7,text="seconds\n\nseconds",fg_bg=g_lg_fg_bg}

    local ct_err = TextBox{parent=net_c_2,x=8,y=14,height=1,width=35,text="Please set all connection timeouts.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_timeouts()
        local svr_cto, api_cto = tonumber(svr_timeout.get_value()), tonumber(api_timeout.get_value())
        if svr_cto ~= nil and api_cto ~= nil then
            tmp_cfg.SVR_Timeout, tmp_cfg.API_Timeout = svr_cto, api_cto
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
            comms.set_trusted_range(range_val)
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
            -- prep supervisor connection screen
            tool_ctl.sv_next.hide()
            tool_ctl.sv_skip.disable()
            tool_ctl.sv_skip.show()
            tool_ctl.sv_conn_button.enable()
            tool_ctl.sv_conn_status.set_value("")
            tool_ctl.sv_conn_detail.set_value("")

            tmp_cfg.AuthKey = key.get_value()
            key_err.hide(true)

            -- init mac for supervisor connection
            if string.len(v) >= 8 then network.init_mac(tmp_cfg.AuthKey) else network.deinit_mac() end

            main_pane.set_value(3)

            tcd.dispatch_unique(2, function () tool_ctl.sv_skip.enable() end)
        else key_err.show() end
    end

    PushButton{parent=net_c_4,x=1,y=14,text="\x1b Back",callback=function()net_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_4,x=44,y=14,text="Next \x1a",callback=submit_auth,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Facility

    local fac_c_1 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_2 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_3 = Div{parent=fac_cfg,x=2,y=4,width=49}

    local fac_pane = MultiPane{parent=mon_cfg,x=1,y=4,panes={fac_c_1,fac_c_2,fac_c_3}}

    TextBox{parent=fac_cfg,x=1,y=2,height=1,text=" Facility Configuration",fg_bg=cpair(colors.black,colors.yellow)}

    TextBox{parent=fac_c_1,x=1,y=1,height=4,text="This tool can attempt to connect to your supervisor computer. This would load facility information in order to get the unit count and aid monitor setup."}
    TextBox{parent=fac_c_1,x=1,y=6,height=2,text="The supervisor startup app must be running and fully configured on your supervisor computer."}

    tool_ctl.sv_conn_status = TextBox{parent=fac_c_1,x=11,y=9,height=1,text=""}
    tool_ctl.sv_conn_detail = TextBox{parent=fac_c_1,x=1,y=11,height=2,text=""}

    tool_ctl.sv_conn_button = PushButton{parent=fac_c_1,x=1,y=9,text="Connect",min_width=9,callback=function()tool_ctl.sv_connect()end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg,dis_fg_bg=dis_fg_bg}

    local function sv_skip()
        tcd.abort(handle_timeout)
        tool_ctl.sv_cool_conf = nil
        tool_ctl.net_listen = false
        fac_pane.set_value(2)
    end

    local function sv_next()
        tool_ctl.show_sv_cfg()
        tool_ctl.update_mon_reqs()
        fac_pane.set_value(3)
    end

    PushButton{parent=fac_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.sv_skip = PushButton{parent=fac_c_1,x=44,y=14,text="Skip \x1a",callback=sv_skip,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg,dis_fg_bg=dis_fg_bg}
    tool_ctl.sv_next = PushButton{parent=fac_c_1,x=44,y=14,text="Next \x1a",callback=sv_next,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,hidden=true}

    TextBox{parent=fac_c_2,x=1,y=1,height=3,text="Please enter the number of reactors you have, also referred to as reactor units or 'units' for short. A maximum of 4 is currently supported."}
    local num_units = NumberField{parent=fac_c_2,x=1,y=5,width=5,max_chars=2,default=ini_cfg.UnitCount,min=1,max=4,fg_bg=bw_fg_bg}
    TextBox{parent=fac_c_2,x=7,y=5,height=1,text="reactors"}
    TextBox{parent=fac_c_2,x=1,y=7,height=3,text="This will decide how many monitors you need. If this does not match the supervisor's number of reactor units, the coordinator will not connect.",fg_bg=g_lg_fg_bg}
    TextBox{parent=fac_c_2,x=1,y=10,height=3,text="Since you skipped supervisor sync, the main monitor minimum height can't be determined precisely. It is marked with * on the next page.",fg_bg=g_lg_fg_bg}

    local nu_error = TextBox{parent=fac_c_2,x=8,y=14,height=1,width=35,text="Please set the number of reactors.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_num_units()
        local count = tonumber(num_units.get_value())
        if count ~= nil and count > 0 and count < 5 then
            nu_error.hide(true)
            tmp_cfg.UnitCount = count
            tool_ctl.update_mon_reqs()
            main_pane.set_value(4)
        else nu_error.show() end
    end

    PushButton{parent=fac_c_2,x=1,y=14,text="\x1b Back",callback=function()fac_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_2,x=44,y=14,text="Next \x1a",callback=submit_num_units,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=fac_c_3,x=1,y=1,height=2,text="The following facility configuration was fetched from your supervisor computer."}

    local fac_config_list = ListBox{parent=fac_c_3,x=1,y=4,height=9,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    PushButton{parent=fac_c_3,x=1,y=14,text="\x1b Back",callback=function()fac_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_3,x=44,y=14,text="Next \x1a",callback=function()main_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Monitors

    local mon_c_1 = Div{parent=mon_cfg,x=2,y=4,width=49}
    local mon_c_2 = Div{parent=mon_cfg,x=2,y=4,width=49}
    local mon_c_3 = Div{parent=mon_cfg,x=2,y=4,width=49}
    local mon_c_4 = Div{parent=mon_cfg,x=2,y=4,width=49}

    local mon_pane = MultiPane{parent=mon_cfg,x=1,y=4,panes={mon_c_1,mon_c_2,mon_c_3,mon_c_4}}

    TextBox{parent=mon_cfg,x=1,y=2,height=1,text=" Monitor Configuration",fg_bg=cpair(colors.black,colors.blue)}

    TextBox{parent=mon_c_1,x=1,y=1,height=5,text="Your configuration requires the following monitors. The main and flow monitors' heights are dependent on your unit count and cooling setup. If you manually entered the unit count, a * will be shown on potentially inaccurate calculations."}
    local mon_reqs = ListBox{parent=mon_c_1,x=1,y=7,height=6,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function next_from_reqs()
        -- unassign unit monitors above the unit count
        for i = tmp_cfg.UnitCount + 1, 4 do tmp_cfg.UnitDisplays[i] = nil end

        tool_ctl.gen_mon_list()
        mon_pane.set_value(2)
    end

    PushButton{parent=mon_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mon_c_1,x=8,y=14,text="Legacy Options",min_width=16,callback=function()mon_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mon_c_1,x=44,y=14,text="Next \x1a",callback=next_from_reqs,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=mon_c_2,x=1,y=1,height=5,text="Please configure your monitors below. You can go back to the prior page without losing progress to double check what you need. All of those monitors must be assigned before you can proceed."}

    local mon_list = ListBox{parent=mon_c_2,x=1,y=6,height=7,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local assign_err = TextBox{parent=mon_c_2,x=8,y=14,height=1,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_monitors()
        if tmp_cfg.MainDisplay == nil then
            assign_err.set_value("Please assign the main monitor.")
        elseif tmp_cfg.FlowDisplay == nil and not tmp_cfg.DisableFlowView then
            assign_err.set_value("Please assign the flow monitor.")
        elseif util.table_len(tmp_cfg.UnitDisplays) ~= tmp_cfg.UnitCount then
            for i = 1, tmp_cfg.UnitCount do
                if tmp_cfg.UnitDisplays[i] == nil then
                    assign_err.set_value("Please assign the unit " .. i .. " monitor.")
                    break
                end
            end
        else
            assign_err.hide(true)
            main_pane.set_value(5)
            return
        end

        assign_err.show()
    end

    PushButton{parent=mon_c_2,x=1,y=14,text="\x1b Back",callback=function()mon_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mon_c_2,x=44,y=14,text="Next \x1a",callback=submit_monitors,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    local mon_desc = TextBox{parent=mon_c_3,x=1,y=1,height=4,text=""}

    local mon_unit_l, mon_unit = nil, nil   ---@type graphics_element, graphics_element

    local mon_warn = TextBox{parent=mon_c_3,x=1,y=11,height=2,text="",fg_bg=cpair(colors.red,colors.lightGray)}

    ---@param val integer assignment type
    local function on_assign_mon(val)
        if val == 2 and tmp_cfg.DisableFlowView then
            tool_ctl.apply_mon.disable()
            mon_warn.set_value("You disabled having a flow view monitor. It can't be set unless you go back and enable it.")
            mon_warn.show()
        elseif not util.table_contains(tool_ctl.mon_expect, val) then
            tool_ctl.apply_mon.disable()
            mon_warn.set_value("That assignment doesn't fit monitor dimensions. You'll need to resize the monitor for it to work.")
            mon_warn.show()
        else
            tool_ctl.apply_mon.enable()
            mon_warn.hide(true)
        end

        if val == 3 then
            mon_unit_l.show()
            mon_unit.show()
        else
            mon_unit_l.hide(true)
            mon_unit.hide(true)
        end

        local value = mon_unit.get_value()
        mon_unit.set_max(tmp_cfg.UnitCount)
        if value == "0" or value == nil then mon_unit.set_value(0) end
    end

    TextBox{parent=mon_c_3,x=1,y=6,width=10,height=1,text="Assignment"}
    local mon_assign = RadioButton{parent=mon_c_3,x=1,y=7,default=1,options={"Main Monitor","Flow Monitor","Unit Monitor"},callback=on_assign_mon,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.blue}

    mon_unit_l = TextBox{parent=mon_c_3,x=18,y=6,width=7,height=1,text="Unit ID"}
    mon_unit = NumberField{parent=mon_c_3,x=18,y=7,width=10,max_chars=2,min=1,max=4,fg_bg=bw_fg_bg}

    local mon_u_err = TextBox{parent=mon_c_3,x=8,y=14,height=1,width=35,text="Please provide a unit ID.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    -- purge all assignments for a given monitor
    ---@param iface string
    local function purge_assignments(iface)
        if tmp_cfg.MainDisplay == iface then
            tmp_cfg.MainDisplay = nil
        elseif tmp_cfg.FlowDisplay == iface then
            tmp_cfg.FlowDisplay = nil
        else
            for i = 1, tmp_cfg.UnitCount do
                if tmp_cfg.UnitDisplays[i] == iface then tmp_cfg.UnitDisplays[i] = nil end
            end
        end
    end

    local function apply_monitor()
        local iface = tool_ctl.mon_iface
        local type = mon_assign.get_value()
        local u_id = tonumber(mon_unit.get_value())

        if type == 1 then
            purge_assignments(iface)
            tmp_cfg.MainDisplay = iface
        elseif type == 2 then
            purge_assignments(iface)
            tmp_cfg.FlowDisplay = iface
        elseif u_id and u_id > 0 then
            purge_assignments(iface)
            tmp_cfg.UnitDisplays[u_id] = iface
        else
            mon_u_err.show()
            return
        end

        tool_ctl.gen_mon_list()
        mon_u_err.hide(true)
        mon_pane.set_value(2)
    end

    PushButton{parent=mon_c_3,x=1,y=14,text="\x1b Back",callback=function()mon_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.apply_mon = PushButton{parent=mon_c_3,x=43,y=14,min_width=7,text="Apply",callback=apply_monitor,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=dis_fg_bg}

    TextBox{parent=mon_c_4,x=1,y=1,height=3,text="For legacy compatibility with facilities built without space for a flow monitor, you can disable the flow monitor requirement here."}
    TextBox{parent=mon_c_4,x=1,y=5,height=3,text="Please be aware that THIS OPTION WILL BE REMOVED ON RELEASE. Disabling it will only be available for the remainder of the beta."}

    local dis_flow_view = CheckBox{parent=mon_c_4,x=1,y=9,default=ini_cfg.DisableFlowView,label="Disable Flow View Monitor",box_fg_bg=cpair(colors.blue,colors.black)}

    local function back_from_legacy()
        tmp_cfg.DisableFlowView = dis_flow_view.get_value()
        tool_ctl.update_mon_reqs()
        mon_pane.set_value(1)
    end

    PushButton{parent=mon_c_4,x=44,y=14,min_width=6,text="Done",callback=back_from_legacy,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Speaker

    local spkr_c = Div{parent=spkr_cfg,x=2,y=4,width=49}

    TextBox{parent=spkr_cfg,x=1,y=2,height=1,text=" Speaker Configuration",fg_bg=cpair(colors.black,colors.cyan)}

    TextBox{parent=spkr_c,x=1,y=1,height=2,text="The coordinator uses a speaker to play alarm sounds."}
    TextBox{parent=spkr_c,x=1,y=4,height=3,text="You can change the speaker audio volume from the default. The range is 0.0 to 3.0, where 1.0 is standard volume."}

    local s_vol = NumberField{parent=spkr_c,x=1,y=8,width=9,max_chars=7,allow_decimal=true,default=ini_cfg.SpeakerVolume,min=0,max=3,fg_bg=bw_fg_bg}

    TextBox{parent=spkr_c,x=1,y=10,height=3,text="Note: alarm sine waves are at half scale so that multiple will be required to reach full scale.",fg_bg=g_lg_fg_bg}

    local s_vol_err = TextBox{parent=spkr_c,x=8,y=14,height=1,width=35,text="Please set a volume.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_vol()
        local vol = tonumber(s_vol.get_value())
        if vol ~= nil then
            s_vol_err.hide(true)
            tmp_cfg.SpeakerVolume = vol
            main_pane.set_value(6)
        else s_vol_err.show() end
    end

    PushButton{parent=spkr_c,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=spkr_c,x=44,y=14,text="Next \x1a",callback=submit_vol,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Coordinator UI

    local crd_c_1 = Div{parent=crd_cfg,x=2,y=4,width=49}

    TextBox{parent=crd_cfg,x=1,y=2,height=1,text=" Coordinator UI Configuration",fg_bg=cpair(colors.black,colors.lime)}

    TextBox{parent=crd_c_1,x=1,y=1,height=3,text="Configure the UI interface options below if you wish to customize formats."}

    TextBox{parent=crd_c_1,x=1,y=4,height=1,text="Clock Time Format"}
    local clock_fmt = RadioButton{parent=crd_c_1,x=1,y=5,default=util.trinary(ini_cfg.Time24Hour,1,2),options={"24-Hour","12-Hour"},callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lime}

    TextBox{parent=crd_c_1,x=1,y=8,height=1,text="Temperature Scale"}
    local temp_scale = RadioButton{parent=crd_c_1,x=1,y=9,default=ini_cfg.TempScale,options={"Kelvin","Celsius","Fahrenheit","Rankine"},callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lime}

    local function submit_ui_opts()
        tmp_cfg.Time24Hour = clock_fmt.get_value() == 1
        tmp_cfg.TempScale = temp_scale.get_value()
        main_pane.set_value(7)
    end

    PushButton{parent=crd_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(5)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=crd_c_1,x=44,y=14,text="Next \x1a",callback=submit_ui_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

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
            main_pane.set_value(8)
        else path_err.show() end
    end

    PushButton{parent=log_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(6)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=log_c_1,x=44,y=14,text="Next \x1a",callback=submit_log,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Color Options

    local clr_c_1 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_2 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_3 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_4 = Div{parent=clr_cfg,x=2,y=4,width=49}

    local clr_pane = MultiPane{parent=clr_cfg,x=1,y=4,panes={clr_c_1,clr_c_2,clr_c_3,clr_c_4}}

    TextBox{parent=clr_cfg,x=1,y=2,height=1,text=" Color Configuration",fg_bg=cpair(colors.black,colors.magenta)}

    TextBox{parent=clr_c_1,x=1,y=1,height=2,text="Here you can select the color themes for the different UI displays."}
    TextBox{parent=clr_c_1,x=1,y=4,height=2,text="Click 'Accessibility' below to access colorblind assistive options.",fg_bg=g_lg_fg_bg}

    TextBox{parent=clr_c_1,x=1,y=7,height=1,text="Main UI Theme"}
    local main_theme = RadioButton{parent=clr_c_1,x=1,y=8,default=ini_cfg.MainTheme,options=themes.UI_THEME_NAMES,callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.magenta}

    TextBox{parent=clr_c_1,x=18,y=7,height=1,text="Front Panel Theme"}
    local fp_theme = RadioButton{parent=clr_c_1,x=18,y=8,default=ini_cfg.FrontPanelTheme,options=themes.FP_THEME_NAMES,callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.magenta}

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
        main_pane.set_value(util.trinary(tool_ctl.jumped_to_color, 1, 7))
        tool_ctl.jumped_to_color = false
        recolor(1)
    end

    local function show_access()
        clr_pane.set_value(2)
        recolor(c_mode.get_value())
    end

    local function submit_colors()
        tmp_cfg.MainTheme = main_theme.get_value()
        tmp_cfg.FrontPanelTheme = fp_theme.get_value()
        tmp_cfg.ColorMode = c_mode.get_value()

        if tool_ctl.jumped_to_color then
            settings.set("MainTheme", tmp_cfg.MainTheme)
            settings.set("FrontPanelTheme", tmp_cfg.FrontPanelTheme)
            settings.set("ColorMode", tmp_cfg.ColorMode)

            if settings.save("/coordinator.settings") then
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
            main_pane.set_value(9)
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

    local function back_from_summary()
        if tool_ctl.viewing_config or tool_ctl.importing_legacy then
            main_pane.set_value(1)
            tool_ctl.viewing_config = false
            tool_ctl.importing_legacy = false
            tool_ctl.settings_apply.show()
        else
            main_pane.set_value(8)
        end
    end

    ---@param element graphics_element
    ---@param data any
    local function try_set(element, data)
        if data ~= nil then element.set_value(data) end
    end

    local function save_and_continue()
        for k, v in pairs(tmp_cfg) do settings.set(k, v) end

        if settings.save("/coordinator.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)

            try_set(svr_chan, ini_cfg.SVR_Channel)
            try_set(crd_chan, ini_cfg.CRD_Channel)
            try_set(pkt_chan, ini_cfg.PKT_Channel)
            try_set(svr_timeout, ini_cfg.SVR_Timeout)
            try_set(api_timeout, ini_cfg.API_Timeout)
            try_set(range, ini_cfg.TrustedRange)
            try_set(key, ini_cfg.AuthKey)
            try_set(num_units, ini_cfg.UnitCount)
            try_set(dis_flow_view, ini_cfg.DisableFlowView)
            try_set(s_vol, ini_cfg.SpeakerVolume)
            try_set(clock_fmt, util.trinary(ini_cfg.Time24Hour, 1, 2))
            try_set(mode, ini_cfg.LogMode)
            try_set(path, ini_cfg.LogPath)
            try_set(en_dbg, ini_cfg.LogDebug)
            try_set(main_theme, ini_cfg.MainTheme)
            try_set(fp_theme, ini_cfg.FrontPanelTheme)
            try_set(c_mode, ini_cfg.ColorMode)

            preset_monitor_fields()

            tool_ctl.gen_mon_list()

            tool_ctl.view_cfg.enable()
            tool_ctl.color_cfg.enable()

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

    PushButton{parent=sum_c_1,x=1,y=14,text="\x1b Back",callback=back_from_summary,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.show_key_btn = PushButton{parent=sum_c_1,x=8,y=14,min_width=17,text="Unhide Auth Key",callback=function()tool_ctl.show_auth_key()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=dis_fg_bg}
    tool_ctl.settings_apply = PushButton{parent=sum_c_1,x=43,y=14,min_width=7,text="Apply",callback=save_and_continue,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_2,x=1,y=1,height=1,text="Settings saved!"}

    local function go_home()
        main_pane.set_value(1)
        net_pane.set_value(1)
        fac_pane.set_value(1)
        mon_pane.set_value(1)
        clr_pane.set_value(1)
        sum_pane.set_value(1)
    end

    PushButton{parent=sum_c_2,x=1,y=14,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_2,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_3,x=1,y=1,height=2,text="The old config.lua and coord.settings files will now be deleted, then the configurator will exit."}

    local function delete_legacy()
        fs.delete("/coordinator/config.lua")
        fs.delete("/coord.settings")
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

    -- load a legacy config file
    function tool_ctl.load_legacy()
        local config = require("coordinator.config")

        tmp_cfg.SVR_Channel = config.SVR_CHANNEL
        tmp_cfg.CRD_Channel = config.CRD_CHANNEL
        tmp_cfg.PKT_Channel = config.PKT_CHANNEL
        tmp_cfg.SVR_Timeout = config.SV_TIMEOUT
        tmp_cfg.API_Timeout = config.API_TIMEOUT
        tmp_cfg.TrustedRange = config.TRUSTED_RANGE
        tmp_cfg.AuthKey = config.AUTH_KEY or ""

        tmp_cfg.UnitCount = config.NUM_UNITS
        tmp_cfg.DisableFlowView = config.DISABLE_FLOW_VIEW
        tmp_cfg.SpeakerVolume = config.SOUNDER_VOLUME
        tmp_cfg.Time24Hour = config.TIME_24_HOUR

        tmp_cfg.LogMode = config.LOG_MODE
        tmp_cfg.LogPath = config.LOG_PATH
        tmp_cfg.LogDebug = config.LOG_DEBUG or false

        settings.load("/coord.settings")

        tmp_cfg.MainDisplay = settings.get("PRIMARY_DISPLAY")
        tmp_cfg.FlowDisplay = settings.get("FLOW_DISPLAY")
        tmp_cfg.UnitDisplays = settings.get("UNIT_DISPLAYS", {})

        -- if there are extra monitor entries, delete them now
        -- not doing so will cause the app to fail to start
        if is_int_min_max(tmp_cfg.UnitCount, 1, 4) then
            for i = tmp_cfg.UnitCount + 1, 4 do tmp_cfg.UnitDisplays[i] = nil end
        end

        if settings.get("ControlStates") == nil then
            local ctrl_states = {
                process = settings.get("PROCESS"),
                waste_modes = settings.get("WASTE_MODES"),
                priority_groups = settings.get("PRIORITY_GROUPS"),
            }

            settings.set("ControlStates", ctrl_states)
        end

        settings.unset("PRIMARY_DISPLAY")
        settings.unset("FLOW_DISPLAY")
        settings.unset("UNIT_DISPLAYS")
        settings.unset("PROCESS")
        settings.unset("WASTE_MODES")
        settings.unset("PRIORITY_GROUPS")

        tool_ctl.gen_summary(tmp_cfg)
        sum_pane.set_value(1)
        main_pane.set_value(9)
        tool_ctl.importing_legacy = true
    end

    -- attempt a connection to the supervisor to get cooling info
    function tool_ctl.sv_connect()
        tool_ctl.sv_conn_button.disable()
        tool_ctl.sv_conn_detail.set_value("")

        local modem = ppm.get_wireless_modem()
        if modem == nil then
            tool_ctl.sv_conn_status.set_value("Please connect an ender/wireless modem.")
        else
            tool_ctl.sv_conn_status.set_value("Modem found, connecting...")
            if tool_ctl.nic == nil then tool_ctl.nic = network.nic(modem) end

            tool_ctl.nic.closeAll()
            tool_ctl.nic.open(tmp_cfg.CRD_Channel)

            tool_ctl.sv_addr = comms.BROADCAST
            tool_ctl.sv_seq_num = 0
            tool_ctl.net_listen = true

            send_sv(MGMT_TYPE.ESTABLISH, { comms.version, "0.0.0", DEVICE_TYPE.CRD })

            tcd.dispatch_unique(8, handle_timeout)
        end
    end

    -- show the facility's unit count and cooling configuration data
    function tool_ctl.show_sv_cfg()
        local conf = tool_ctl.sv_cool_conf
        fac_config_list.remove_all()

        local str = util.sprintf("Facility has %d reactor unit%s:", #conf, util.trinary(#conf==1,"","s"))
        TextBox{parent=fac_config_list,height=1,text=str,fg_bg=cpair(colors.gray,colors.white)}

        for i = 1, #conf do
            local num_b, num_t = conf[i][1], conf[i][2]
            str = util.sprintf("\x07 Unit %d has %d boiler%s and %d turbine%s", i, num_b, util.trinary(num_b == 1, "", "s"), num_t, util.trinary(num_t == 1, "", "s"))
            TextBox{parent=fac_config_list,height=1,text=str,fg_bg=cpair(colors.gray,colors.white)}
        end
    end

    -- update list of monitor requirements
    function tool_ctl.update_mon_reqs()
        local plural = tmp_cfg.UnitCount > 1

        if tool_ctl.sv_cool_conf ~= nil then
            local cnf = tool_ctl.sv_cool_conf

            local row1_tall = cnf[1][1] > 1 or cnf[1][2] > 2 or (cnf[2] and (cnf[2][1] > 1 or cnf[2][2] > 2))
            local row1_short = (cnf[1][1] == 0 and cnf[1][2] == 1) and (cnf[2] == nil or (cnf[2][1] == 0 and cnf[2][2] == 1))
            local row2_tall = (cnf[3] and (cnf[3][1] > 1 or cnf[3][2] > 2)) or (cnf[4] and (cnf[4][1] > 1 or cnf[4][2] > 2))
            local row2_short = (cnf[3] == nil or (cnf[3][1] == 0 and cnf[3][2] == 1)) and (cnf[4] == nil or (cnf[4][1] == 0 and cnf[4][2] == 1))

            if tmp_cfg.UnitCount <= 2 then
                tool_ctl.main_mon_h = util.trinary(row1_tall, 5, 4)
            else
                -- is only one tall and the other short, or are both tall? -> 5 or 6; are neither tall? -> 5
                if row1_tall or row2_tall then
                    tool_ctl.main_mon_h = util.trinary((row1_short and row2_tall) or (row1_tall and row2_short), 5, 6)
                else tool_ctl.main_mon_h = 5 end
            end
        else
            tool_ctl.main_mon_h = util.trinary(tmp_cfg.UnitCount <= 2, 4, 5)
        end

        tool_ctl.flow_mon_h = 2 + tmp_cfg.UnitCount

        local asterisk = util.trinary(tool_ctl.sv_cool_conf == nil, "*", "")
        local m_at_least = util.trinary(tool_ctl.main_mon_h < 6, "at least ", "")
        local f_at_least = util.trinary(tool_ctl.flow_mon_h < 6, "at least ", "")

        mon_reqs.remove_all()

        TextBox{parent=mon_reqs,x=1,y=1,height=1,text="\x1a "..tmp_cfg.UnitCount.." Unit View Monitor"..util.trinary(plural,"s","")}
        TextBox{parent=mon_reqs,x=1,y=1,height=1,text="  "..util.trinary(plural,"each ","").."must be 4 blocks wide by 4 tall",fg_bg=cpair(colors.gray,colors.white)}
        TextBox{parent=mon_reqs,x=1,y=1,height=1,text="\x1a 1 Main View Monitor"}
        TextBox{parent=mon_reqs,x=1,y=1,height=1,text="  must be 8 blocks wide by "..m_at_least..tool_ctl.main_mon_h..asterisk.." tall",fg_bg=cpair(colors.gray,colors.white)}
        if not tmp_cfg.DisableFlowView then
            TextBox{parent=mon_reqs,x=1,y=1,height=1,text="\x1a 1 Flow View Monitor"}
            TextBox{parent=mon_reqs,x=1,y=1,height=1,text="  must be 8 blocks wide by "..f_at_least..tool_ctl.flow_mon_h.." tall",fg_bg=cpair(colors.gray,colors.white)}
        end
    end

    -- set/edit a monitor's assignment
    ---@param iface string
    ---@param device ppm_entry
    function tool_ctl.edit_monitor(iface, device)
        tool_ctl.mon_iface = iface

        local dev = device.dev
        local w, h = ppm.monitor_block_size(dev.getSize())

        local msg = "This size doesn't match a required screen. Please go back and resize it, or configure below at the risk of it not working."

        tool_ctl.mon_expect = {}
        mon_assign.set_value(1)
        mon_unit.set_value(0)

        if w == 4 and h == 4 then
            msg = "This could work as a unit display. Please configure below."
            tool_ctl.mon_expect = { 3 }
            mon_assign.set_value(3)
        elseif w == 8 then
            if h >= tool_ctl.main_mon_h and h >= tool_ctl.flow_mon_h then
                msg = "This could work as either your main monitor or flow monitor. Please configure below."
                tool_ctl.mon_expect = { 1, 2 }
                if tmp_cfg.MainDisplay then mon_assign.set_value(2) end
            elseif h >= tool_ctl.main_mon_h then
                msg = "This could work as your main monitor. Please configure below."
                tool_ctl.mon_expect = { 1 }
            elseif h >= tool_ctl.flow_mon_h then
                msg = "This could work as your flow monitor. Please configure below."
                tool_ctl.mon_expect = { 2 }
                mon_assign.set_value(2)
            end
        end

        -- override if a config exists
        if tmp_cfg.MainDisplay == iface then
            mon_assign.set_value(1)
        elseif tmp_cfg.FlowDisplay == iface then
            mon_assign.set_value(2)
        else
            for i = 1, tmp_cfg.UnitCount do
                if tmp_cfg.UnitDisplays[i] == iface then
                    mon_assign.set_value(3)
                    mon_unit.set_value(i)
                    break
                end
            end
        end

        on_assign_mon(mon_assign.get_value())

        mon_desc.set_value(util.c("You have selected '", iface, "', which has a block size of ", w, " wide by ", h, " tall. ", msg))
        mon_pane.set_value(3)
    end

    -- generate the list of available monitors
    function tool_ctl.gen_mon_list()
        mon_list.remove_all()

        local missing = { main = tmp_cfg.MainDisplay ~= nil, flow = tmp_cfg.FlowDisplay ~= nil, unit = {} }
        for i = 1, tmp_cfg.UnitCount do missing.unit[i] = tmp_cfg.UnitDisplays[i] ~= nil end

        -- list connected monitors
        local monitors = ppm.get_monitor_list()
        for iface, device in pairs(monitors) do
            local dev = device.dev

            dev.setTextScale(0.5)
            dev.setTextColor(colors.white)
            dev.setBackgroundColor(colors.black)
            dev.clear()
            dev.setCursorPos(1, 1)
            dev.setTextColor(colors.magenta)
            dev.write("This is monitor")
            dev.setCursorPos(1, 2)
            dev.setTextColor(colors.white)
            dev.write(iface)

            local assignment = "Unused"

            if tmp_cfg.MainDisplay == iface then
                assignment = "Main"
                missing.main = false
            elseif tmp_cfg.FlowDisplay == iface then
                assignment = "Flow"
                missing.flow = false
            else
                for i = 1, tmp_cfg.UnitCount do
                    if tmp_cfg.UnitDisplays[i] == iface then
                        missing.unit[i] = false
                        assignment = "Unit " .. i
                        break
                    end
                end
            end

            local line = Div{parent=mon_list,x=1,y=1,height=1}

            TextBox{parent=line,x=1,y=1,width=6,height=1,text=assignment,fg_bg=cpair(util.trinary(assignment=="Unused",colors.red,colors.blue),colors.white)}
            TextBox{parent=line,x=8,y=1,height=1,text=iface}

            local w, h = ppm.monitor_block_size(dev.getSize())

            local function unset_mon()
                purge_assignments(iface)
                tool_ctl.gen_mon_list()
            end

            TextBox{parent=line,x=33,y=1,width=4,height=1,text=w.."x"..h,fg_bg=cpair(colors.black,colors.white)}
            PushButton{parent=line,x=37,y=1,min_width=5,height=1,text="SET",callback=function()tool_ctl.edit_monitor(iface,device)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
            local unset = PushButton{parent=line,x=42,y=1,min_width=7,height=1,text="UNSET",callback=unset_mon,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.black,colors.gray)}

            if assignment == "Unused" then unset.disable() end
        end

        local dc_list = {} -- disconnected monitor list

        if missing.main then table.insert(dc_list, { "Main", tmp_cfg.MainDisplay }) end
        if missing.flow then table.insert(dc_list, { "Flow", tmp_cfg.FlowDisplay }) end
        for i = 1, tmp_cfg.UnitCount do
            if missing.unit[i] then table.insert(dc_list, { "Unit " .. i, tmp_cfg.UnitDisplays[i] }) end
        end

        -- add monitors that are assigned but not connected
        for i = 1, #dc_list do
            local line = Div{parent=mon_list,x=1,y=1,height=1}

            TextBox{parent=line,x=1,y=1,width=6,height=1,text=dc_list[i][1],fg_bg=cpair(colors.blue,colors.white)}
            TextBox{parent=line,x=8,y=1,height=1,text="disconnected",fg_bg=cpair(colors.red,colors.white)}

            local function unset_mon()
                purge_assignments(dc_list[i][2])
                tool_ctl.gen_mon_list()
            end

            TextBox{parent=line,x=33,y=1,width=4,height=1,text="?x?",fg_bg=cpair(colors.black,colors.white)}
            PushButton{parent=line,x=37,y=1,min_width=5,height=1,text="SET",callback=function()end,dis_fg_bg=cpair(colors.black,colors.gray)}.disable()
            PushButton{parent=line,x=42,y=1,min_width=7,height=1,text="UNSET",callback=unset_mon,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.black,colors.gray)}
        end
    end

    -- expose the auth key on the summary page
    function tool_ctl.show_auth_key()
        tool_ctl.show_key_btn.disable()
        tool_ctl.auth_key_textbox.set_value(tool_ctl.auth_key_value)
    end

    -- generate the summary list
    ---@param cfg crd_config
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
            elseif f[1] == "TempScale" then
                if raw == 1 then val = "Kelvin" elseif raw == 2 then val = "Celsius" elseif raw == 3 then val = "Fahrenheit" elseif raw == 4 then val = "Rankine" end
            elseif f[1] == "MainTheme" then
                val = util.strval(themes.ui_theme_name(raw))
            elseif f[1] == "FrontPanelTheme" then
                val = util.strval(themes.fp_theme_name(raw))
            elseif f[1] == "ColorMode" then
                val = util.strval(themes.color_mode_name(raw))
            elseif f[1] == "UnitDisplays" and type(cfg.UnitDisplays) == "table" then
                val = ""
                for idx = 1, #cfg.UnitDisplays do
                    val = val .. util.trinary(idx == 1, "", "\n") .. util.sprintf(" \x07 Unit %d - %s", idx, cfg.UnitDisplays[idx])
                end
            end

            if val == "nil" then val = "<not set>" end

            local c = util.trinary(alternate, g_lg_fg_bg, cpair(colors.gray,colors.white))
            alternate = not alternate

            if string.len(val) > val_max_w then
                local lines = util.strwrap(val, inner_width)
                height = #lines + 1
            end

            if (f[1] == "UnitDisplays") and (height == 1) and (val ~= "<not set>") then height = 2 end

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
            elseif event == "modem_message" and tool_ctl.nic ~= nil and tool_ctl.net_listen then
                local s_pkt = tool_ctl.nic.receive(param1, param2, param3, param4, param5)

                if s_pkt and s_pkt.protocol() == PROTOCOL.SCADA_MGMT then
                    local mgmt_pkt = comms.mgmt_packet()
                    if mgmt_pkt.decode(s_pkt) then
                        tcd.abort(handle_timeout)
                        handle_packet(mgmt_pkt.get())
                    end
                end
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
