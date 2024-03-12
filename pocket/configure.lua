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
local RadioButton = require("graphics.elements.controls.radio_button")

local NumberField = require("graphics.elements.form.number_field")
local TextField   = require("graphics.elements.form.text_field")

local println = util.println
local tri = util.trinary

local cpair = core.cpair

local LEFT = core.ALIGN.LEFT
local CENTER = core.ALIGN.CENTER
local RIGHT = core.ALIGN.RIGHT

-- changes to the config data/format to let the user know
local changes = {}

---@class pkt_configurator
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

local tool_ctl = {
    ask_config = false,
    has_config = false,
    viewing_config = false,
    importing_legacy = false,

    view_cfg = nil,         ---@type graphics_element
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

---@class pkt_config
local tmp_cfg = {
    SVR_Channel = nil,  ---@type integer
    CRD_Channel = nil,  ---@type integer
    PKT_Channel = nil,  ---@type integer
    ConnTimeout = nil,  ---@type number
    TrustedRange = nil, ---@type number
    AuthKey = nil,      ---@type string|nil
    LogMode = 0,
    LogPath = "",
    LogDebug = false,
}

---@class pkt_config
local ini_cfg = {}
---@class pkt_config
local settings_cfg = {}

-- all settings fields, their nice names, and their default values
local fields = {
    { "SVR_Channel", "SVR Channel", 16240 },
    { "CRD_Channel", "CRD Channel", 16243 },
    { "PKT_Channel", "PKT Channel", 16244 },
    { "ConnTimeout", "Connection Timeout", 5 },
    { "TrustedRange", "Trusted Range", 0 },
    { "AuthKey", "Facility Auth Key" , ""},
    { "LogMode", "Log Mode", log.MODE.APPEND },
    { "LogPath", "Log Path", "/log.txt" },
    { "LogDebug", "Log Debug Messages", false }
}

-- load data from the settings file
---@param target pkt_config
---@param raw boolean? true to not use default values
local function load_settings(target, raw)
    for _, v in pairs(fields) do settings.unset(v[1]) end

    local loaded = settings.load("/pocket.settings")

    for _, v in pairs(fields) do target[v[1]] = settings.get(v[1], tri(raw, nil, v[3])) end

    return loaded
end

-- create the config view
---@param display graphics_element
local function config_view(display)
---@diagnostic disable-next-line: undefined-field
    local function exit() os.queueEvent("terminate") end

    TextBox{parent=display,y=1,text="Pocket Configurator",alignment=CENTER,height=1,fg_bg=style.header}

    local root_pane_div = Div{parent=display,x=1,y=2}

    local main_page = Div{parent=root_pane_div,x=1,y=1}
    local net_cfg = Div{parent=root_pane_div,x=1,y=1}
    local log_cfg = Div{parent=root_pane_div,x=1,y=1}
    local summary = Div{parent=root_pane_div,x=1,y=1}
    local changelog = Div{parent=root_pane_div,x=1,y=1}

    local main_pane = MultiPane{parent=root_pane_div,x=1,y=1,panes={main_page,net_cfg,log_cfg,summary,changelog}}

    -- Main Page

    local y_start = 7

    TextBox{parent=main_page,x=2,y=2,height=4,text="Welcome to the Pocket configurator! Please select one of the following options."}

    if tool_ctl.ask_config then
        TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text="Please configure before starting up.",fg_bg=cpair(colors.red,colors.lightGray)}
        y_start = y_start + 3
    end

    local function view_config()
        tool_ctl.viewing_config = true
        tool_ctl.gen_summary(settings_cfg)
        tool_ctl.settings_apply.hide(true)
        main_pane.set_value(4)
    end

    if fs.exists("/pocket/config.lua") then
        PushButton{parent=main_page,x=2,y=y_start,min_width=22,text="Import Legacy Config",callback=function()tool_ctl.load_legacy()end,fg_bg=cpair(colors.black,colors.cyan),active_fg_bg=btn_act_fg_bg}
        y_start = y_start + 2
    end

    PushButton{parent=main_page,x=2,y=y_start,min_width=18,text="Configure Device",callback=function()main_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    tool_ctl.view_cfg = PushButton{parent=main_page,x=2,y=y_start+2,min_width=20,text="View Configuration",callback=view_config,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=dis_fg_bg}

    if not tool_ctl.has_config then tool_ctl.view_cfg.disable() end

    PushButton{parent=main_page,x=2,y=18,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=main_page,x=14,y=18,min_width=12,text="Change Log",callback=function()main_pane.set_value(5)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#region Network

    local net_c_1 = Div{parent=net_cfg,x=2,y=4,width=24}
    local net_c_2 = Div{parent=net_cfg,x=2,y=4,width=24}
    local net_c_3 = Div{parent=net_cfg,x=2,y=4,width=24}
    local net_c_4 = Div{parent=net_cfg,x=2,y=4,width=24}

    local net_pane = MultiPane{parent=net_cfg,x=1,y=4,panes={net_c_1,net_c_2,net_c_3,net_c_4}}

    TextBox{parent=net_cfg,x=1,y=2,height=1,text=" Network Configuration",fg_bg=cpair(colors.black,colors.lightBlue)}

    TextBox{parent=net_c_1,x=1,y=1,height=1,text="Set network channels."}
    TextBox{parent=net_c_1,x=1,y=3,height=4,text="Each of the named channels must be the same within a particular SCADA network.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=8,height=1,width=18,text="Supervisor Channel"}
    local svr_chan = NumberField{parent=net_c_1,x=1,y=9,width=7,default=ini_cfg.SVR_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=9,height=4,text="[SVR_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=10,height=1,width=19,text="Coordinator Channel"}
    local crd_chan = NumberField{parent=net_c_1,x=1,y=11,width=7,default=ini_cfg.CRD_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=11,height=4,text="[CRD_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=12,height=1,width=14,text="Pocket Channel"}
    local pkt_chan = NumberField{parent=net_c_1,x=1,y=13,width=7,default=ini_cfg.PKT_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=13,height=4,text="[PKT_CHANNEL]",fg_bg=g_lg_fg_bg}

    local chan_err = TextBox{parent=net_c_1,x=1,y=14,height=1,width=24,text="Please set all channels.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_channels()
        local svr_c, crd_c, pkt_c = tonumber(svr_chan.get_value()), tonumber(crd_chan.get_value()), tonumber(pkt_chan.get_value())
        if svr_c ~= nil and crd_c ~= nil and pkt_c ~= nil then
            tmp_cfg.SVR_Channel, tmp_cfg.CRD_Channel, tmp_cfg.PKT_Channel = svr_c, crd_c, pkt_c
            net_pane.set_value(2)
            chan_err.hide(true)
        else chan_err.show() end
    end

    PushButton{parent=net_c_1,x=1,y=15,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_1,x=19,y=15,text="Next \x1a",callback=submit_channels,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_2,x=1,y=1,height=1,text="Set connection timeout."}
    TextBox{parent=net_c_2,x=1,y=3,height=7,text="You generally should not need to modify this. On slow servers, you can try to increase this to make the system wait longer before assuming a disconnection.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_2,x=1,y=11,height=1,width=19,text="Connection Timeout"}
    local timeout = NumberField{parent=net_c_2,x=1,y=12,width=7,default=ini_cfg.ConnTimeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=net_c_2,x=9,y=12,height=2,text="seconds\n(default 5)",fg_bg=g_lg_fg_bg}

    local ct_err = TextBox{parent=net_c_2,x=1,y=14,height=1,width=24,text="Please set timeout.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_timeouts()
        local timeout_val = tonumber(timeout.get_value())
        if timeout_val ~= nil then
            tmp_cfg.ConnTimeout = timeout_val
            net_pane.set_value(3)
            ct_err.hide(true)
        else ct_err.show() end
    end

    PushButton{parent=net_c_2,x=1,y=15,text="\x1b Back",callback=function()net_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_2,x=19,y=15,text="Next \x1a",callback=submit_timeouts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_3,x=1,y=1,height=1,text="Set the trusted range."}
    TextBox{parent=net_c_3,x=1,y=3,height=4,text="Setting this to a value larger than 0 prevents connections with devices that many blocks away.",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_3,x=1,y=8,height=4,text="This is optional. You can disable this functionality by setting the value to 0.",fg_bg=g_lg_fg_bg}

    local range = NumberField{parent=net_c_3,x=1,y=13,width=10,default=ini_cfg.TrustedRange,min=0,max_chars=20,allow_decimal=true,fg_bg=bw_fg_bg}

    local tr_err = TextBox{parent=net_c_3,x=1,y=14,height=1,width=24,text="Set the trusted range.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_tr()
        local range_val = tonumber(range.get_value())
        if range_val ~= nil then
            tmp_cfg.TrustedRange = range_val
            net_pane.set_value(4)
            tr_err.hide(true)
        else tr_err.show() end
    end

    PushButton{parent=net_c_3,x=1,y=15,text="\x1b Back",callback=function()net_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_3,x=19,y=15,text="Next \x1a",callback=submit_tr,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_4,x=1,y=1,height=4,text="Optionally, set the facility authentication key. Do NOT use one of your passwords."}
    TextBox{parent=net_c_4,x=1,y=6,height=6,text="This enables verifying that messages are authentic, so it is intended for security on multiplayer servers.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_4,x=1,y=12,height=1,text="Facility Auth Key"}
    local key, _, censor = TextField{parent=net_c_4,x=1,y=13,max_len=64,value=ini_cfg.AuthKey,width=24,height=1,fg_bg=bw_fg_bg}

    local function censor_key(enable) censor(util.trinary(enable, "*", nil)) end

    -- declare back first so tabbing makes sense visually
    PushButton{parent=net_c_4,x=1,y=15,text="\x1b Back",callback=function()net_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    local hide_key = CheckBox{parent=net_c_4,x=8,y=15,label="Hide Key",box_fg_bg=cpair(colors.lightBlue,colors.black),callback=censor_key}

    hide_key.set_value(true)
    censor_key(true)

    local key_err = TextBox{parent=net_c_4,x=1,y=14,height=1,width=24,text="Length must be > 7.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_auth()
        local v = key.get_value()
        if string.len(v) == 0 or string.len(v) >= 8 then
            tmp_cfg.AuthKey = key.get_value()
            main_pane.set_value(3)
            key_err.hide(true)
        else key_err.show() end
    end

    PushButton{parent=net_c_4,x=19,y=15,text="Next \x1a",callback=submit_auth,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Logging

    local log_c_1 = Div{parent=log_cfg,x=2,y=4,width=24}

    TextBox{parent=log_cfg,x=1,y=2,height=1,text=" Logging Configuration",fg_bg=cpair(colors.black,colors.pink)}

    TextBox{parent=log_c_1,x=1,y=1,height=1,text="Configure logging below."}

    TextBox{parent=log_c_1,x=1,y=3,height=1,text="Log File Mode"}
    local mode = RadioButton{parent=log_c_1,x=1,y=4,default=ini_cfg.LogMode+1,options={"Append on Startup","Replace on Startup"},callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.pink}

    TextBox{parent=log_c_1,x=1,y=7,height=1,text="Log File Path"}
    local path = TextField{parent=log_c_1,x=1,y=8,width=24,height=1,value=ini_cfg.LogPath,max_len=128,fg_bg=bw_fg_bg}

    local en_dbg = CheckBox{parent=log_c_1,x=1,y=10,default=ini_cfg.LogDebug,label="Enable Debug Messages",box_fg_bg=cpair(colors.pink,colors.black)}
    TextBox{parent=log_c_1,x=3,y=11,height=4,text="This results in much larger log files. Use only as needed.",fg_bg=g_lg_fg_bg}

    local path_err = TextBox{parent=log_c_1,x=1,y=14,height=1,width=24,text="Provide a log file path.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

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
            main_pane.set_value(4)
        else path_err.show() end
    end

    PushButton{parent=log_c_1,x=1,y=15,text="\x1b Back",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=log_c_1,x=19,y=15,text="Next \x1a",callback=submit_log,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Summary and Saving

    local sum_c_1 = Div{parent=summary,x=2,y=4,width=24}
    local sum_c_2 = Div{parent=summary,x=2,y=4,width=24}
    local sum_c_3 = Div{parent=summary,x=2,y=4,width=24}
    local sum_c_4 = Div{parent=summary,x=2,y=4,width=24}

    local sum_pane = MultiPane{parent=summary,x=1,y=4,panes={sum_c_1,sum_c_2,sum_c_3,sum_c_4}}

    TextBox{parent=summary,x=1,y=2,height=1,text=" Summary",fg_bg=cpair(colors.black,colors.green)}

    local setting_list = ListBox{parent=sum_c_1,x=1,y=1,height=11,width=24,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function back_from_summary()
        if tool_ctl.viewing_config or tool_ctl.importing_legacy then
            main_pane.set_value(1)
            tool_ctl.viewing_config = false
            tool_ctl.importing_legacy = false
            tool_ctl.settings_apply.show()
        else
            main_pane.set_value(3)
        end
    end

    ---@param element graphics_element
    ---@param data any
    local function try_set(element, data)
        if data ~= nil then element.set_value(data) end
    end

    local function save_and_continue()
        for k, v in pairs(tmp_cfg) do settings.set(k, v) end

        if settings.save("/pocket.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)

            try_set(svr_chan, ini_cfg.SVR_Channel)
            try_set(crd_chan, ini_cfg.CRD_Channel)
            try_set(pkt_chan, ini_cfg.PKT_Channel)
            try_set(timeout, ini_cfg.ConnTimeout)
            try_set(range, ini_cfg.TrustedRange)
            try_set(key, ini_cfg.AuthKey)
            try_set(mode, ini_cfg.LogMode)
            try_set(path, ini_cfg.LogPath)
            try_set(en_dbg, ini_cfg.LogDebug)

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

    PushButton{parent=sum_c_1,x=1,y=15,text="\x1b Back",callback=back_from_summary,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.show_key_btn = PushButton{parent=sum_c_1,x=1,y=13,min_width=17,text="Unhide Auth Key",callback=function()tool_ctl.show_auth_key()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=dis_fg_bg}
    tool_ctl.settings_apply = PushButton{parent=sum_c_1,x=18,y=15,min_width=7,text="Apply",callback=save_and_continue,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_2,x=1,y=1,height=1,text="Settings saved!"}

    local function go_home()
        main_pane.set_value(1)
        net_pane.set_value(1)
        sum_pane.set_value(1)
    end

    PushButton{parent=sum_c_2,x=1,y=15,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_2,x=19,y=15,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_3,x=1,y=1,height=4,text="The old config.lua file will now be deleted, then the configurator will exit."}

    local function delete_legacy()
        fs.delete("/pocket/config.lua")
        exit()
    end

    PushButton{parent=sum_c_3,x=1,y=15,min_width=8,text="Cancel",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_3,x=19,y=15,min_width=6,text="OK",callback=delete_legacy,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_4,x=1,y=1,height=8,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=sum_c_4,x=1,y=15,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_4,x=19,y=15,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    --#endregion

    -- Config Change Log

    local cl = Div{parent=changelog,x=2,y=4,width=24}

    TextBox{parent=changelog,x=1,y=2,height=1,text=" Config Change Log",fg_bg=bw_fg_bg}

    local c_log = ListBox{parent=cl,x=1,y=1,height=13,width=24,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    for _, change in ipairs(changes) do
        TextBox{parent=c_log,text=change[1],height=1,fg_bg=bw_fg_bg}
        for _, v in ipairs(change[2]) do
            local e = Div{parent=c_log,height=#util.strwrap(v,21)}
            TextBox{parent=e,y=1,x=1,text="- ",height=1,fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=e,y=1,x=3,text=v,height=e.get_height(),fg_bg=cpair(colors.gray,colors.white)}
        end
    end

    PushButton{parent=cl,x=1,y=15,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    -- set tool functions now that we have the elements

    -- load a legacy config file
    function tool_ctl.load_legacy()
        local config = require("pocket.config")

        tmp_cfg.SVR_Channel = config.SVR_CHANNEL
        tmp_cfg.CRD_Channel = config.CRD_CHANNEL
        tmp_cfg.PKT_Channel = config.PKT_CHANNEL
        tmp_cfg.ConnTimeout = config.COMMS_TIMEOUT
        tmp_cfg.TrustedRange = config.TRUSTED_RANGE
        tmp_cfg.AuthKey = config.AUTH_KEY or ""

        tmp_cfg.LogMode = config.LOG_MODE
        tmp_cfg.LogPath = config.LOG_PATH
        tmp_cfg.LogDebug = config.LOG_DEBUG or false

        tool_ctl.gen_summary(tmp_cfg)
        sum_pane.set_value(1)
        main_pane.set_value(4)
        tool_ctl.importing_legacy = true
    end

    -- expose the auth key on the summary page
    function tool_ctl.show_auth_key()
        tool_ctl.show_key_btn.disable()
        tool_ctl.auth_key_textbox.set_value(tool_ctl.auth_key_value)
    end

    -- generate the summary list
    ---@param cfg pkt_config
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
            local val_max_w = (inner_width - label_w) - 1
            local raw = cfg[f[1]]
            local val = util.strval(raw)

            if f[1] == "AuthKey" then val = string.rep("*", string.len(val))
            elseif f[1] == "LogMode" then val = util.trinary(raw == log.MODE.APPEND, "append", "replace") end

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

-- run the pcoket configurator
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
