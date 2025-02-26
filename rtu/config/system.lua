local log         = require("scada-common.log")
local ppm         = require("scada-common.ppm")
local rsio        = require("scada-common.rsio")
local util        = require("scada-common.util")

local core        = require("graphics.core")
local themes      = require("graphics.themes")

local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local Checkbox    = require("graphics.elements.controls.Checkbox")
local PushButton  = require("graphics.elements.controls.PushButton")
local RadioButton = require("graphics.elements.controls.RadioButton")

local NumberField = require("graphics.elements.form.NumberField")
local TextField   = require("graphics.elements.form.TextField")

local IndLight    = require("graphics.elements.indicators.IndicatorLight")

local tri = util.trinary

local cpair = core.cpair

local RIGHT = core.ALIGN.RIGHT

local self = {
    importing_legacy = false,
    importing_any_dc = false,

    show_auth_key = nil,      ---@type function
    show_key_btn = nil,       ---@type PushButton
    auth_key_textbox = nil,   ---@type TextBox
    auth_key_value = ""
}

local system = {}

-- create the system configuration view
---@param tool_ctl _rtu_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ rtu_config, rtu_config, rtu_config, { [1]: string, [2]: string, [3]: any }[], function ]
---@param divs Div[]
---@param ext [ MultiPane, MultiPane, string[], function, function, function ]
---@param style { [string]: cpair }
function system.create(tool_ctl, main_pane, cfg_sys, divs, ext, style)
    local settings_cfg, ini_cfg, tmp_cfg, fields, load_settings = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]
    local spkr_cfg, net_cfg, log_cfg, clr_cfg, summary = divs[1], divs[2], divs[3], divs[4], divs[5]
    local peri_pane, rs_pane, NEEDS_UNIT, show_peri_conns, show_rs_conns, exit = ext[1], ext[2], ext[3], ext[4], ext[5], ext[6]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    --#region Speakers

    local spkr_c = Div{parent=spkr_cfg,x=2,y=4,width=49}

    TextBox{parent=spkr_cfg,x=1,y=2,text=" Speaker Configuration",fg_bg=cpair(colors.black,colors.cyan)}

    TextBox{parent=spkr_c,x=1,y=1,height=2,text="Speakers can be connected to this RTU gateway without RTU unit configuration entries."}
    TextBox{parent=spkr_c,x=1,y=4,height=3,text="You can change the speaker audio volume from the default. The range is 0.0 to 3.0, where 1.0 is standard volume."}

    local s_vol = NumberField{parent=spkr_c,x=1,y=8,width=9,max_chars=7,allow_decimal=true,default=ini_cfg.SpeakerVolume,min=0,max=3,fg_bg=bw_fg_bg}

    TextBox{parent=spkr_c,x=1,y=10,height=3,text="Note: alarm sine waves are at half scale so that multiple will be required to reach full scale.",fg_bg=g_lg_fg_bg}

    local s_vol_err = TextBox{parent=spkr_c,x=8,y=14,width=35,text="Please set a volume.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

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

    TextBox{parent=net_cfg,x=1,y=2,text=" Network Configuration",fg_bg=cpair(colors.black,colors.lightBlue)}

    TextBox{parent=net_c_1,x=1,y=1,text="Please set the network channels below."}
    TextBox{parent=net_c_1,x=1,y=3,height=4,text="Each of the 5 uniquely named channels, including the 2 below, must be the same for each device in this SCADA network. For multiplayer servers, it is recommended to not use the default channels.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,x=1,y=8,text="Supervisor Channel"}
    local svr_chan = NumberField{parent=net_c_1,x=1,y=9,width=7,default=ini_cfg.SVR_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=9,height=4,text="[SVR_CHANNEL]",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_1,x=1,y=11,text="RTU Channel"}
    local rtu_chan = NumberField{parent=net_c_1,x=1,y=12,width=7,default=ini_cfg.RTU_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=12,height=4,text="[RTU_CHANNEL]",fg_bg=g_lg_fg_bg}

    local chan_err = TextBox{parent=net_c_1,x=8,y=14,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

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

    TextBox{parent=net_c_2,x=1,y=1,text="Connection Timeout"}
    local timeout = NumberField{parent=net_c_2,x=1,y=2,width=7,default=ini_cfg.ConnTimeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_2,x=9,y=2,height=2,text="seconds (default 5)",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_2,x=1,y=3,height=4,text="You generally do not want or need to modify this. On slow servers, you can increase this to make the system wait longer before assuming a disconnection.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_2,x=1,y=8,text="Trusted Range"}
    local range = NumberField{parent=net_c_2,x=1,y=9,width=10,default=ini_cfg.TrustedRange,min=0,max_chars=20,allow_decimal=true,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_2,x=1,y=10,height=4,text="Setting this to a value larger than 0 prevents connections with devices that many meters (blocks) away in any direction.",fg_bg=g_lg_fg_bg}

    local p2_err = TextBox{parent=net_c_2,x=8,y=14,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

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
    TextBox{parent=net_c_3,x=1,y=4,height=6,text="This enables verifying that messages are authentic, so it is intended for security on multiplayer servers. All devices on the same network MUST use the same key if any device has a key. This does result in some extra computation (can slow things down).",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_3,x=1,y=11,text="Facility Auth Key"}
    local key, _ = TextField{parent=net_c_3,x=1,y=12,max_len=64,value=ini_cfg.AuthKey,width=32,height=1,fg_bg=bw_fg_bg}

    local function censor_key(enable) key.censor(tri(enable, "*", nil)) end

    local hide_key = Checkbox{parent=net_c_3,x=34,y=12,label="Hide",box_fg_bg=cpair(colors.lightBlue,colors.black),callback=censor_key}

    hide_key.set_value(true)
    censor_key(true)

    local key_err = TextBox{parent=net_c_3,x=8,y=14,width=35,text="Key must be at least 8 characters.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

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

    TextBox{parent=log_cfg,x=1,y=2,text=" Logging Configuration",fg_bg=cpair(colors.black,colors.pink)}

    TextBox{parent=log_c_1,x=1,y=1,text="Please configure logging below."}

    TextBox{parent=log_c_1,x=1,y=3,text="Log File Mode"}
    local mode = RadioButton{parent=log_c_1,x=1,y=4,default=ini_cfg.LogMode+1,options={"Append on Startup","Replace on Startup"},callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.pink}

    TextBox{parent=log_c_1,x=1,y=7,text="Log File Path"}
    local path = TextField{parent=log_c_1,x=1,y=8,width=49,height=1,value=ini_cfg.LogPath,max_len=128,fg_bg=bw_fg_bg}

    local en_dbg = Checkbox{parent=log_c_1,x=1,y=10,default=ini_cfg.LogDebug,label="Enable Logging Debug Messages",box_fg_bg=cpair(colors.pink,colors.black)}
    TextBox{parent=log_c_1,x=3,y=11,height=2,text="This results in much larger log files. It is best to only use this when there is a problem.",fg_bg=g_lg_fg_bg}

    local path_err = TextBox{parent=log_c_1,x=8,y=14,width=35,text="Please provide a log file path.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

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

    TextBox{parent=clr_cfg,x=1,y=2,text=" Color Configuration",fg_bg=cpair(colors.black,colors.magenta)}

    TextBox{parent=clr_c_1,x=1,y=1,height=2,text="Here you can select the color theme for the front panel."}
    TextBox{parent=clr_c_1,x=1,y=4,height=2,text="Click 'Accessibility' below to access colorblind assistive options.",fg_bg=g_lg_fg_bg}

    TextBox{parent=clr_c_1,x=1,y=7,text="Front Panel Theme"}
    local fp_theme = RadioButton{parent=clr_c_1,x=1,y=8,default=ini_cfg.FrontPanelTheme,options=themes.FP_THEME_NAMES,callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.magenta}

    TextBox{parent=clr_c_2,x=1,y=1,height=6,text="This system uses color heavily to distinguish ok and not, with some indicators using many colors. By selecting a mode below, indicators will change as shown. For non-standard modes, indicators with more than two colors will be split up."}

    TextBox{parent=clr_c_2,x=21,y=7,text="Preview"}
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

    TextBox{parent=clr_c_2,x=1,y=7,width=10,text="Color Mode"}
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
            self.importing_legacy = false
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

    TextBox{parent=clr_c_3,x=1,y=1,text="Settings saved!"}
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

    TextBox{parent=summary,x=1,y=2,text=" Summary",fg_bg=cpair(colors.black,colors.green)}

    local setting_list = ListBox{parent=sum_c_1,x=1,y=1,height=12,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function back_from_settings()
        if tool_ctl.viewing_config or self.importing_legacy then
            if self.importing_legacy and self.importing_any_dc then
                sum_pane.set_value(7)
            else
                self.importing_legacy = false
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
        for _, field in ipairs(fields) do
            local k, v = field[1], tmp_cfg[field[1]]
            if not (exclude_conns and (k == "Peripherals" or k == "Redstone")) then
                if v == nil then settings.unset(k) else settings.set(k, v) end
            end
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
                tmp_cfg.Peripherals = tool_ctl.deep_copy_peri(ini_cfg.Peripherals)
                tmp_cfg.Redstone = tool_ctl.deep_copy_rs(ini_cfg.Redstone)

                tool_ctl.update_peri_list()
            end

            tool_ctl.dev_cfg.enable()
            tool_ctl.rs_cfg.enable()
            tool_ctl.view_gw_cfg.enable()

            if self.importing_legacy then
                self.importing_legacy = false
                sum_pane.set_value(5)
            else sum_pane.set_value(4) end
        else sum_pane.set_value(6) end
    end

    PushButton{parent=sum_c_1,x=1,y=14,text="\x1b Back",callback=back_from_settings,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    self.show_key_btn = PushButton{parent=sum_c_1,x=8,y=14,min_width=17,text="Unhide Auth Key",callback=function()self.show_auth_key()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    tool_ctl.settings_apply = PushButton{parent=sum_c_1,x=43,y=14,min_width=7,text="Apply",callback=function()save_and_continue(true)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}
    tool_ctl.settings_confirm = PushButton{parent=sum_c_1,x=41,y=14,min_width=9,text="Confirm",callback=function()sum_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}
    tool_ctl.settings_confirm.hide()

    TextBox{parent=sum_c_2,x=1,y=1,text="The following peripherals will be imported:"}
    local peri_import_list = ListBox{parent=sum_c_2,x=1,y=3,height=10,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    PushButton{parent=sum_c_2,x=1,y=14,text="\x1b Back",callback=function()sum_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_2,x=41,y=14,min_width=9,text="Confirm",callback=function()sum_pane.set_value(3)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_3,x=1,y=1,text="The following redstone entries will be imported:"}
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

    TextBox{parent=sum_c_4,x=1,y=1,text="Settings saved!"}
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

    --#region Tool Functions

    -- load a legacy config file
    function tool_ctl.load_legacy()
        local config = require("rtu.config")

        self.importing_any_dc = false

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
            local mount = mounts[def.name]

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
            else self.importing_any_dc = true end

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
            TextBox{parent=line,x=1,y=1,text="@ "..def.name,fg_bg=cpair(colors.black,colors.white)}
            TextBox{parent=line,x=1,y=2,text=status,fg_bg=cpair(color,colors.white)}
            TextBox{parent=line,x=1,y=3,text=desc,fg_bg=cpair(colors.gray,colors.white)}
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
                TextBox{parent=line,x=1,y=1,width=1,text=io_dir,fg_bg=cpair(colors.lightGray,colors.white)}
                TextBox{parent=line,x=2,y=1,width=14,text=name}
                TextBox{parent=line,x=18,y=1,width=string.len(conn),text=conn,fg_bg=cpair(colors.gray,colors.white)}
                TextBox{parent=line,x=40,y=1,text=unit,fg_bg=cpair(colors.gray,colors.white)}
            end
        end

        tool_ctl.gen_summary(tmp_cfg)
        if self.importing_any_dc then sum_pane.set_value(7) else sum_pane.set_value(1) end
        main_pane.set_value(6)
        tool_ctl.settings_apply.hide(true)
        tool_ctl.settings_confirm.show()
        self.importing_legacy = true
    end

    -- go back to the home page
    function tool_ctl.go_home()
        tool_ctl.viewing_config = false
        self.importing_legacy = false
        self.importing_any_dc = false

        main_pane.set_value(1)
        net_pane.set_value(1)
        clr_pane.set_value(1)
        sum_pane.set_value(1)
        peri_pane.set_value(1)
        rs_pane.set_value(1)
    end

    -- expose the auth key on the summary page
    function self.show_auth_key()
        self.show_key_btn.disable()
        self.auth_key_textbox.set_value(self.auth_key_value)
    end

    -- generate the summary list
    ---@param cfg rtu_config
    function tool_ctl.gen_summary(cfg)
        setting_list.remove_all()

        local alternate = false
        local inner_width = setting_list.get_width() - 1

        self.show_key_btn.enable()
        self.auth_key_value = cfg.AuthKey or "" -- to show auth key

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

            if (string.len(val) > val_max_w) or string.find(val, "\n") then
                local lines = util.strwrap(val, inner_width)
                height = #lines + 1
            end

            local line = Div{parent=setting_list,height=height,fg_bg=c}
            TextBox{parent=line,text=f[2],width=string.len(f[2]),fg_bg=cpair(colors.black,line.get_fg_bg().bkg)}

            local textbox
            if height > 1 then
                textbox = TextBox{parent=line,x=1,y=2,text=val,height=height-1}
            else
                textbox = TextBox{parent=line,x=label_w+1,y=1,text=val,alignment=RIGHT}
            end

            if f[1] == "AuthKey" then self.auth_key_textbox = textbox end
        end
    end

    --#endregion
end

return system
