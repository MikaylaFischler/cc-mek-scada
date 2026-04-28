local log         = require("scada-common.log")
local ppm         = require("scada-common.ppm")
local types       = require("scada-common.types")
local util        = require("scada-common.util")

local facility    = require("supervisor.config.facility")
local mekanism    = require("supervisor.config.mekanism")

local core        = require("graphics.core")
local themes      = require("graphics.themes")

local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local Checkbox    = require("graphics.elements.controls.Checkbox")
local PushButton  = require("graphics.elements.controls.PushButton")
local Radio2D     = require("graphics.elements.controls.Radio2D")
local RadioButton = require("graphics.elements.controls.RadioButton")

local NumberField = require("graphics.elements.form.NumberField")
local TextField   = require("graphics.elements.form.TextField")

local IndLight    = require("graphics.elements.indicators.IndicatorLight")

local tri = util.trinary

local cpair = core.cpair

local LISTEN_MODE = types.LISTEN_MODE

local RIGHT = core.ALIGN.RIGHT

local self = {
    importing_legacy = false,

    update_net_cfg = nil,   ---@type function
    show_auth_key = nil,    ---@type function

    pkt_test = nil,         ---@type Checkbox
    pkt_chan = nil,         ---@type NumberField
    pkt_timeout = nil,      ---@type NumberField
    show_key_btn = nil,     ---@type PushButton
    auth_key_textbox = nil, ---@type TextBox

    auth_key_value = ""
}

local system = {}

-- create the system configuration view
---@param tool_ctl _svr_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ svr_config, svr_config, svr_config, { [1]: string, [2]: string, [3]: any }[], function ]
---@param divs Div[]
---@param fac_pane MultiPane
---@param mek_pane MultiPane
---@param style { [string]: cpair }
---@param exit function
function system.create(tool_ctl, main_pane, cfg_sys, divs, fac_pane, mek_pane, style, exit)
    local settings_cfg, ini_cfg, tmp_cfg, fields, load_settings = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]
    local net_cfg, log_cfg, clr_cfg, summary, import_err = divs[1], divs[2], divs[3], divs[4], divs[5]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    --#region Network

    local net_c_1 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_2 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_3 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_4 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_5 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_6 = Div{parent=net_cfg,x=2,y=4,width=49}

    local net_pane = MultiPane{parent=net_cfg,y=4,panes={net_c_1,net_c_2,net_c_3,net_c_4,net_c_5,net_c_6}}

    TextBox{parent=net_cfg,y=2,text=" Network Configuration",fg_bg=cpair(colors.black,colors.lightBlue)}

    TextBox{parent=net_c_1,y=1,text="Please select the network interface(s)."}
    TextBox{parent=net_c_1,x=41,y=1,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision

    local function on_wired_change(_) tool_ctl.gen_modem_list() end

    local wireless = Checkbox{parent=net_c_1,y=3,label="Wireless/Ender Modem",default=ini_cfg.WirelessModem,box_fg_bg=cpair(colors.lightBlue,colors.black)}
    TextBox{parent=net_c_1,x=24,y=3,text="(required for Pocket)",fg_bg=g_lg_fg_bg}
    local wired = Checkbox{parent=net_c_1,y=5,label="Wired Modem",default=ini_cfg.WiredModem~=false,box_fg_bg=cpair(colors.lightBlue,colors.black),callback=on_wired_change}
    TextBox{parent=net_c_1,x=3,y=6,text="this one MUST ONLY connect to SCADA computers",fg_bg=cpair(colors.red,colors._INHERIT)}
    TextBox{parent=net_c_1,x=3,y=7,text="connecting it to peripherals will cause issues",fg_bg=g_lg_fg_bg}
    local modem_list = ListBox{parent=net_c_1,y=8,height=5,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local modem_err = TextBox{parent=net_c_1,x=8,y=14,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_interfaces()
        tmp_cfg.WirelessModem = wireless.get_value()

        if not wired.get_value() then
            tmp_cfg.WiredModem = false
            tool_ctl.gen_modem_list()
        end

        if not (wired.get_value() or wireless.get_value()) then
            modem_err.set_value("Please select a modem type.")
            modem_err.show()
        elseif wired.get_value() and type(tmp_cfg.WiredModem) ~= "string" then
            modem_err.set_value("Please select a wired modem.")
            modem_err.show()
        else
            self.update_net_cfg()
            net_pane.set_value(2)
            modem_err.hide(true)
        end
    end

    PushButton{parent=net_c_1,y=14,text="\x1b Back",callback=function()main_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_1,x=44,y=14,text="Next \x1a",callback=submit_interfaces,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_2,y=1,text="Please assign device connection interfaces if you selected multiple network interfaces."}
    TextBox{parent=net_c_2,x=39,y=2,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision
    TextBox{parent=net_c_2,y=4,text="Reactor PLC\nRTU Gateway\nCoordinator",fg_bg=g_lg_fg_bg}
    local opts = { "Wireless", "Wired", "Both" }
    local plc_listen = Radio2D{parent=net_c_2,x=14,y=4,rows=1,columns=3,default=ini_cfg.PLC_Listen,options=opts,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lightBlue,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
    local rtu_listen = Radio2D{parent=net_c_2,x=14,rows=1,columns=3,default=ini_cfg.RTU_Listen,options=opts,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lightBlue,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
    local crd_listen = Radio2D{parent=net_c_2,x=14,rows=1,columns=3,default=ini_cfg.CRD_Listen,options=opts,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lightBlue,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}

    local function on_pocket_en(en)
        if not en then
            self.pkt_test.set_value(false)
            self.pkt_test.disable()
        else self.pkt_test.enable() end
    end

    TextBox{parent=net_c_2,y=8,text="With a wireless modem, configure Pocket access."}
    local pkt_en = Checkbox{parent=net_c_2,y=10,label="Enable Pocket Access",default=ini_cfg.PocketEnabled,callback=on_pocket_en,box_fg_bg=cpair(colors.lightBlue,colors.black),disable_fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_2,x=24,y=10,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision
    self.pkt_test = Checkbox{parent=net_c_2,label="Enable Pocket Remote System Testing",default=ini_cfg.PocketTest,box_fg_bg=cpair(colors.lightBlue,colors.black),disable_fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_2,x=39,y=11,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision
    TextBox{parent=net_c_2,x=3,text="This allows remotely playing alarm sounds.",fg_bg=g_lg_fg_bg}

    local function submit_net_cfg_opts()
        if tmp_cfg.WirelessModem and tmp_cfg.WiredModem then
            tmp_cfg.PLC_Listen = plc_listen.get_value()
            tmp_cfg.RTU_Listen = rtu_listen.get_value()
            tmp_cfg.CRD_Listen = crd_listen.get_value()
        else
            if tmp_cfg.WiredModem then
                tmp_cfg.PLC_Listen = LISTEN_MODE.WIRED
                tmp_cfg.RTU_Listen = LISTEN_MODE.WIRED
                tmp_cfg.CRD_Listen = LISTEN_MODE.WIRED
            else
                tmp_cfg.PLC_Listen = LISTEN_MODE.WIRELESS
                tmp_cfg.RTU_Listen = LISTEN_MODE.WIRELESS
                tmp_cfg.CRD_Listen = LISTEN_MODE.WIRELESS
            end
        end

        if tmp_cfg.WirelessModem then
            tmp_cfg.PocketEnabled = pkt_en.get_value()
            tmp_cfg.PocketTest = self.pkt_test.get_value()
        else
            tmp_cfg.PocketEnabled = false
            tmp_cfg.PocketTest = false
        end

        if tmp_cfg.PocketEnabled then
            self.pkt_chan.enable()
            self.pkt_timeout.enable()
        else
            self.pkt_chan.disable()
            self.pkt_timeout.disable()
        end

        net_pane.set_value(3)
    end

    PushButton{parent=net_c_2,y=14,text="\x1b Back",callback=function()net_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_2,x=44,y=14,text="Next \x1a",callback=submit_net_cfg_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_3,y=1,text="Please set the network channels below."}
    TextBox{parent=net_c_3,y=3,height=4,text="Each of the 5 uniquely named channels must be the same for each device in this SCADA network. For multiplayer servers, it is recommended to not use the default channels.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_3,y=8,width=18,text="Supervisor Channel"}
    local svr_chan = NumberField{parent=net_c_3,x=21,y=8,width=7,default=ini_cfg.SVR_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_3,x=29,y=8,height=4,text="[SVR_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_3,y=9,width=11,text="PLC Channel"}
    local plc_chan = NumberField{parent=net_c_3,x=21,y=9,width=7,default=ini_cfg.PLC_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_3,x=29,y=9,height=4,text="[PLC_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_3,y=10,width=19,text="RTU Gateway Channel"}
    local rtu_chan = NumberField{parent=net_c_3,x=21,y=10,width=7,default=ini_cfg.RTU_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_3,x=29,y=10,height=4,text="[RTU_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_3,y=11,width=19,text="Coordinator Channel"}
    local crd_chan = NumberField{parent=net_c_3,x=21,y=11,width=7,default=ini_cfg.CRD_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_3,x=29,y=11,height=4,text="[CRD_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_3,y=12,width=14,text="Pocket Channel"}
    self.pkt_chan = NumberField{parent=net_c_3,x=21,y=12,width=7,default=ini_cfg.PKT_Channel,min=1,max=65535,fg_bg=bw_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    TextBox{parent=net_c_3,x=29,y=12,height=4,text="[PKT_CHANNEL]",fg_bg=g_lg_fg_bg}

    local chan_err = TextBox{parent=net_c_3,x=8,y=14,width=35,text="Please set all channels.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_channels()
        local svr_c, plc_c, rtu_c = tonumber(svr_chan.get_value()), tonumber(plc_chan.get_value()), tonumber(rtu_chan.get_value())
        local crd_c, pkt_c = tonumber(crd_chan.get_value()), tonumber(self.pkt_chan.get_value())

        if not tmp_cfg.PocketEnabled then pkt_c = tmp_cfg.PKT_Channel or 16244 end

        if svr_c ~= nil and plc_c ~= nil and rtu_c ~= nil and crd_c ~= nil and pkt_c ~= nil then
            tmp_cfg.SVR_Channel, tmp_cfg.PLC_Channel, tmp_cfg.RTU_Channel = svr_c, plc_c, rtu_c
            tmp_cfg.CRD_Channel, tmp_cfg.PKT_Channel = crd_c, pkt_c
            net_pane.set_value(4)
            chan_err.hide(true)
        else chan_err.show() end
    end

    PushButton{parent=net_c_3,y=14,text="\x1b Back",callback=function()net_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_3,x=44,y=14,text="Next \x1a",callback=submit_channels,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_4,y=1,text="Please set the connection timeouts below."}
    TextBox{parent=net_c_4,y=3,height=4,text="You generally should not need to modify these. On slow servers, you can try to increase this to make the system wait longer before assuming a disconnection. The default for all is 5 seconds.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_4,y=8,width=11,text="PLC Timeout"}
    local plc_timeout = NumberField{parent=net_c_4,x=21,y=8,width=7,default=ini_cfg.PLC_Timeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=net_c_4,y=9,width=19,text="RTU Gateway Timeout"}
    local rtu_timeout = NumberField{parent=net_c_4,x=21,y=9,width=7,default=ini_cfg.RTU_Timeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=net_c_4,y=10,width=19,text="Coordinator Timeout"}
    local crd_timeout = NumberField{parent=net_c_4,x=21,y=10,width=7,default=ini_cfg.CRD_Timeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=net_c_4,y=11,width=14,text="Pocket Timeout"}
    self.pkt_timeout = NumberField{parent=net_c_4,x=21,y=11,width=7,default=ini_cfg.PKT_Timeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}

    TextBox{parent=net_c_4,x=29,y=8,height=4,width=7,text="seconds\nseconds\nseconds\nseconds",fg_bg=g_lg_fg_bg}

    local ct_err = TextBox{parent=net_c_4,x=8,y=14,width=35,text="Please set all connection timeouts.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_timeouts()
        local plc_cto, rtu_cto, crd_cto, pkt_cto = tonumber(plc_timeout.get_value()), tonumber(rtu_timeout.get_value()), tonumber(crd_timeout.get_value()), tonumber(self.pkt_timeout.get_value())

        if not tmp_cfg.PocketEnabled then pkt_cto = tmp_cfg.PKT_Timeout or 5 end

        if plc_cto ~= nil and rtu_cto ~= nil and crd_cto ~= nil and pkt_cto ~= nil then
            tmp_cfg.PLC_Timeout, tmp_cfg.RTU_Timeout, tmp_cfg.CRD_Timeout, tmp_cfg.PKT_Timeout = plc_cto, rtu_cto, crd_cto, pkt_cto

            if tmp_cfg.WirelessModem then
                net_pane.set_value(5)
            else
                tmp_cfg.TrustedRange = 0
                tmp_cfg.AuthKey = ""
                main_pane.set_value(5)
            end

            ct_err.hide(true)
        else ct_err.show() end
    end

    PushButton{parent=net_c_4,y=14,text="\x1b Back",callback=function()net_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_4,x=44,y=14,text="Next \x1a",callback=submit_timeouts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_5,y=1,text="Please set the wireless trusted range below."}
    TextBox{parent=net_c_5,y=3,height=3,text="Setting this to a value larger than 0 prevents wireless connections with devices that many meters (blocks) away in any direction.",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_5,y=7,height=2,text="This is optional. You can disable this functionality by setting the value to 0.",fg_bg=g_lg_fg_bg}

    local range = NumberField{parent=net_c_5,y=10,width=10,default=ini_cfg.TrustedRange,min=0,max_chars=20,allow_decimal=true,fg_bg=bw_fg_bg}

    local tr_err = TextBox{parent=net_c_5,x=8,y=14,width=35,text="Please set the trusted range.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_tr()
        local range_val = tonumber(range.get_value())
        if range_val ~= nil then
            tmp_cfg.TrustedRange = range_val
            net_pane.set_value(6)
            tr_err.hide(true)
        else tr_err.show() end
    end

    PushButton{parent=net_c_5,y=14,text="\x1b Back",callback=function()net_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_5,x=44,y=14,text="Next \x1a",callback=submit_tr,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_6,y=1,height=2,text="Optionally, set the facility authentication key below. Do NOT use one of your passwords."}
    TextBox{parent=net_c_6,y=4,height=6,text="This enables verifying that messages are authentic, so it is intended for wireless security on multiplayer servers. All devices on the same wireless network MUST use the same key if any device has a key. This does result in some extra computation (can slow things down).",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_6,y=11,text="Auth Key (Wireless Only, Not Used for Wired)"}
    local key, _ = TextField{parent=net_c_6,y=12,max_len=64,value=ini_cfg.AuthKey,width=32,height=1,fg_bg=bw_fg_bg}

    local function censor_key(enable) key.censor(tri(enable, "*", nil)) end

    local hide_key = Checkbox{parent=net_c_6,x=34,y=12,label="Hide",box_fg_bg=cpair(colors.lightBlue,colors.black),callback=censor_key}

    hide_key.set_value(true)
    censor_key(true)

    local key_err = TextBox{parent=net_c_6,x=8,y=14,width=35,text="Key must be at least 8 characters.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_auth()
        local v = key.get_value()
        if string.len(v) == 0 or string.len(v) >= 8 then
            tmp_cfg.AuthKey = key.get_value()
            main_pane.set_value(5)
            key_err.hide(true)
        else key_err.show() end
    end

    PushButton{parent=net_c_6,y=14,text="\x1b Back",callback=function()net_pane.set_value(5)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_6,x=44,y=14,text="Next \x1a",callback=submit_auth,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Logging

    local log_c_1 = Div{parent=log_cfg,x=2,y=4,width=49}

    TextBox{parent=log_cfg,y=2,text=" Logging Configuration",fg_bg=cpair(colors.black,colors.pink)}

    TextBox{parent=log_c_1,y=1,text="Please configure logging below."}

    TextBox{parent=log_c_1,y=3,text="Log File Mode"}
    local mode = RadioButton{parent=log_c_1,y=4,default=ini_cfg.LogMode+1,options={"Append on Startup","Replace on Startup"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.pink}

    TextBox{parent=log_c_1,y=7,text="Log File Path"}
    local path = TextField{parent=log_c_1,y=8,width=49,height=1,value=ini_cfg.LogPath,max_len=128,fg_bg=bw_fg_bg}

    local en_dbg = Checkbox{parent=log_c_1,y=10,default=ini_cfg.LogDebug,label="Enable Logging Debug Messages",box_fg_bg=cpair(colors.pink,colors.black)}
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
            main_pane.set_value(6)
        else path_err.show() end
    end

    PushButton{parent=log_c_1,y=14,text="\x1b Back",callback=function()main_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=log_c_1,x=44,y=14,text="Next \x1a",callback=submit_log,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Color Options

    local clr_c_1 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_2 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_3 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_4 = Div{parent=clr_cfg,x=2,y=4,width=49}

    local clr_pane = MultiPane{parent=clr_cfg,y=4,panes={clr_c_1,clr_c_2,clr_c_3,clr_c_4}}

    TextBox{parent=clr_cfg,y=2,text=" Color Configuration",fg_bg=cpair(colors.black,colors.magenta)}

    TextBox{parent=clr_c_1,y=1,height=2,text="Here you can select the color theme for the front panel."}
    TextBox{parent=clr_c_1,y=4,height=2,text="Click 'Accessibility' below to access colorblind assistive options.",fg_bg=g_lg_fg_bg}

    TextBox{parent=clr_c_1,y=7,text="Front Panel Theme"}
    local fp_theme = RadioButton{parent=clr_c_1,y=8,default=ini_cfg.FrontPanelTheme,options=themes.FP_THEME_NAMES,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.magenta}

    TextBox{parent=clr_c_2,y=1,height=6,text="This system uses color heavily to distinguish ok and not, with some indicators using many colors. By selecting a mode below, indicators will change as shown. For non-standard modes, indicators with more than two colors will be split up."}

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

    TextBox{parent=clr_c_2,y=7,width=10,text="Color Mode"}
    local c_mode = RadioButton{parent=clr_c_2,y=8,default=ini_cfg.ColorMode,options=themes.COLOR_MODE_NAMES,callback=recolor,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.magenta}

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
            self.importing_legacy = false
            tool_ctl.settings_apply.show()
            main_pane.set_value(7)
        end
    end

    PushButton{parent=clr_c_1,y=14,text="\x1b Back",callback=back_from_colors,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=clr_c_1,x=8,y=14,min_width=15,text="Accessibility",callback=show_access,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.color_next = PushButton{parent=clr_c_1,x=44,y=14,text="Next \x1a",callback=submit_colors,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.color_apply = PushButton{parent=clr_c_1,x=43,y=14,min_width=7,text="Apply",callback=submit_colors,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    tool_ctl.color_apply.hide(true)

    local function c_go_home()
        main_pane.set_value(1)
        clr_pane.set_value(1)
    end

    TextBox{parent=clr_c_3,y=1,text="Settings saved!"}
    PushButton{parent=clr_c_3,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}
    PushButton{parent=clr_c_3,x=44,y=14,min_width=6,text="Home",callback=c_go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=clr_c_4,y=1,height=5,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=clr_c_4,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}
    PushButton{parent=clr_c_4,x=44,y=14,min_width=6,text="Home",callback=c_go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Summary and Saving

    local sum_c_1 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_2 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_3 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_4 = Div{parent=summary,x=2,y=4,width=49}

    local sum_pane = MultiPane{parent=summary,y=4,panes={sum_c_1,sum_c_2,sum_c_3,sum_c_4}}

    TextBox{parent=summary,y=2,text=" Summary",fg_bg=cpair(colors.black,colors.green)}

    local setting_list = ListBox{parent=sum_c_1,y=1,height=12,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function back_from_settings()
        if tool_ctl.viewing_config or self.importing_legacy then
            main_pane.set_value(1)
            tool_ctl.viewing_config = false
            self.importing_legacy = false
            tool_ctl.settings_apply.show()
        else
            main_pane.set_value(6)
        end
    end

    ---@param element graphics_element
    ---@param data any
    local function try_set(element, data)
        if data ~= nil then element.set_value(data) end
    end

    local function save_and_continue()
        for _, field in ipairs(fields) do
            local k, v = field[1], tmp_cfg[field[1]]
            if v == nil then settings.unset(k) else settings.set(k, v) end
        end

        if settings.save("/supervisor.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)

            try_set(tool_ctl.num_units, ini_cfg.UnitCount)
            try_set(tool_ctl.tank_mode, ini_cfg.FacilityTankMode)
            try_set(wireless, ini_cfg.WirelessModem)
            try_set(wired, ini_cfg.WiredModem ~= false)
            try_set(plc_listen, ini_cfg.PLC_Listen)
            try_set(rtu_listen, ini_cfg.RTU_Listen)
            try_set(crd_listen, ini_cfg.CRD_Listen)
            try_set(pkt_en, ini_cfg.PocketEnabled)
            try_set(self.pkt_test, ini_cfg.PocketTest)
            try_set(svr_chan, ini_cfg.SVR_Channel)
            try_set(plc_chan, ini_cfg.PLC_Channel)
            try_set(rtu_chan, ini_cfg.RTU_Channel)
            try_set(crd_chan, ini_cfg.CRD_Channel)
            try_set(self.pkt_chan, ini_cfg.PKT_Channel)
            try_set(plc_timeout, ini_cfg.PLC_Timeout)
            try_set(rtu_timeout, ini_cfg.RTU_Timeout)
            try_set(crd_timeout, ini_cfg.CRD_Timeout)
            try_set(self.pkt_timeout, ini_cfg.PKT_Timeout)
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

            for i = 1, #ini_cfg.AuxiliaryCoolant do
                try_set(tool_ctl.aux_cool_elems[i].enable, ini_cfg.AuxiliaryCoolant[i])
            end

            for i = 1, #ini_cfg.TankFluidTypes do
                if tool_ctl.tank_fluid_opts[i] then
                    if (ini_cfg.TankFluidTypes[i] > 0) then
                        tool_ctl.tank_fluid_opts[i].enable()
                        tool_ctl.tank_fluid_opts[i].set_value(ini_cfg.TankFluidTypes[i])
                    else
                        tool_ctl.tank_fluid_opts[i].disable()
                    end
                end
            end

            try_set(tool_ctl.en_fac_tanks, ini_cfg.FacilityTankMode > 0)

            for k, v in pairs(ini_cfg.MekanismConfig) do
                try_set(tool_ctl.custom_configs[k], v)
            end

            for i = 1, #mekanism.profiles do
                if ini_cfg.MekanismProfile == mekanism.profiles[i].name then
                    try_set(tool_ctl.mek_profile, i)
                    break
                end

                if i == #mekanism.profiles then
                    -- custom profile
                    try_set(tool_ctl.mek_profile, #mekanism.profiles + 1)
                end
            end

            try_set(tool_ctl.waste_products[1], ini_cfg.MekanismWasteToPu[1])
            try_set(tool_ctl.waste_products[2], ini_cfg.MekanismWasteToPu[2])
            try_set(tool_ctl.waste_products[3], ini_cfg.MekanismWasteToPo[1])
            try_set(tool_ctl.waste_products[4], ini_cfg.MekanismWasteToPo[2])

            tool_ctl.view_cfg.enable()

            if self.importing_legacy then
                self.importing_legacy = false
                sum_pane.set_value(3)
            else
                sum_pane.set_value(2)
            end
        else
            sum_pane.set_value(4)
        end
    end

    PushButton{parent=sum_c_1,y=14,text="\x1b Back",callback=back_from_settings,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    self.show_key_btn = PushButton{parent=sum_c_1,x=8,y=14,min_width=17,text="Unhide Auth Key",callback=function()self.show_auth_key()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    tool_ctl.settings_apply = PushButton{parent=sum_c_1,x=43,y=14,min_width=7,text="Apply",callback=save_and_continue,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_2,y=1,text="Settings saved!"}

    local function go_home()
        main_pane.set_value(1)
        fac_pane.set_value(1)
        mek_pane.set_value(1)
        net_pane.set_value(1)
        clr_pane.set_value(1)
        sum_pane.set_value(1)
    end

    PushButton{parent=sum_c_2,y=14,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_2,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_3,y=1,height=2,text="The old config.lua file will now be deleted, then the configurator will exit."}

    local function delete_legacy()
        fs.delete("/supervisor/config.lua")
        exit()
    end

    PushButton{parent=sum_c_3,y=14,min_width=8,text="Cancel",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_3,x=44,y=14,min_width=6,text="OK",callback=delete_legacy,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_4,y=1,height=5,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=sum_c_4,y=14,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_4,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    --#endregion

    --#region Import Error

    local i_err = Div{parent=import_err,x=2,y=4,width=49}

    TextBox{parent=import_err,y=2,text=" Import Error",fg_bg=cpair(colors.black,colors.red)}
    TextBox{parent=i_err,y=1,text="There is a problem with your config.lua file:"}

    local import_err_msg = TextBox{parent=i_err,y=3,height=6,text=""}

    PushButton{parent=i_err,y=14,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=i_err,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    --#endregion

    --#region Tool Functions

    -- expose the auth key on the summary page
    function self.show_auth_key()
        self.show_key_btn.disable()
        self.auth_key_textbox.set_value(self.auth_key_value)
    end

    -- update the network interface configuration options
    function self.update_net_cfg()
        if tmp_cfg.WirelessModem and tmp_cfg.WiredModem then
            plc_listen.enable()
            rtu_listen.enable()
            crd_listen.enable()
        else
            plc_listen.disable()
            rtu_listen.disable()
            crd_listen.disable()
        end

        if tmp_cfg.WirelessModem then
            pkt_en.enable()
            self.pkt_test.enable()
            self.pkt_chan.enable()
            self.pkt_timeout.enable()
        else
            pkt_en.set_value(false)
            self.pkt_test.set_value(false)
            pkt_en.disable()
            self.pkt_test.disable()
            self.pkt_chan.disable()
            self.pkt_timeout.disable()
        end
    end

    -- load a legacy config file
    function tool_ctl.load_legacy()
        local config = require("supervisor.config")

        tmp_cfg.UnitCount = config.NUM_REACTORS

        if config.REACTOR_COOLING == nil or tmp_cfg.UnitCount ~= #config.REACTOR_COOLING then
            import_err_msg.set_value("Cooling configuration table length must match the number of units.")
            main_pane.set_value(9)
            return
        end

        for i = 1, tmp_cfg.UnitCount do
            local cfg = config.REACTOR_COOLING[i]

            if type(cfg) ~= "table" then
                import_err_msg.set_value("Cooling configuration for unit " .. i .. " must be a table.")
                main_pane.set_value(9)
                return
            end

            tmp_cfg.CoolingConfig[i] = { BoilerCount = cfg.BOILERS or 0, TurbineCount = cfg.TURBINES or 1, TankConnection = cfg.TANK or false }
        end

        tmp_cfg.FacilityTankMode = config.FAC_TANK_MODE

        if not (util.is_int(tmp_cfg.FacilityTankMode) and tmp_cfg.FacilityTankMode >= 0 and tmp_cfg.FacilityTankMode <= 8) then
            import_err_msg.set_value("Invalid tank mode present in config. FAC_TANK_MODE must be a number 0 through 8.")
            main_pane.set_value(9)
            return
        end

        if config.FAC_TANK_MODE > 0 then
            if config.FAC_TANK_DEFS == nil or tmp_cfg.UnitCount ~= #config.FAC_TANK_DEFS then
                import_err_msg.set_value("Facility tank definitions table length must match the number of units when using facility tanks.")
                main_pane.set_value(9)
                return
            end

            for i = 1, tmp_cfg.UnitCount do
                tmp_cfg.FacilityTankDefs[i] = config.FAC_TANK_DEFS[i]
            end
        else
            tmp_cfg.FacilityTankMode = 0
            tmp_cfg.FacilityTankDefs = {}

            -- on facility tank mode 0, setup tank defs to match unit tank option
            for i = 1, tmp_cfg.UnitCount do
                tmp_cfg.FacilityTankDefs[i] = tri(tmp_cfg.CoolingConfig[i].TankConnection, 1, 0)
            end
        end

        tmp_cfg.FacilityTankList, tmp_cfg.FacilityTankConns = facility.generate_tank_list_and_conns(tmp_cfg.FacilityTankMode, tmp_cfg.FacilityTankDefs)

        for i = 1, tmp_cfg.UnitCount do tmp_cfg.AuxiliaryCoolant[i] = false end
        for i = 1, tmp_cfg.FacilityTankList do tmp_cfg.TankFluidTypes[i] = types.COOLANT_TYPE.WATER end

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
        main_pane.set_value(7)
        self.importing_legacy = true
    end

    -- generate the summary list
    ---@param cfg svr_config
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
            local skip = false

            if f[1] == "AuthKey" then val = string.rep("*", string.len(val))
            elseif f[1] == "LogMode" then val = tri(raw == log.MODE.APPEND, "append", "replace")
            elseif f[1] == "FrontPanelTheme" then
                val = util.strval(themes.fp_theme_name(raw))
            elseif f[1] == "ColorMode" then
                val = util.strval(themes.color_mode_name(raw))
            elseif f[1] == "CoolingConfig" and type(cfg.CoolingConfig) == "table" then
                val = ""

                for idx = 1, #cfg.CoolingConfig do
                    local ccfg = cfg.CoolingConfig[idx]
                    local b_plural = tri(ccfg.BoilerCount == 1, "", "s")
                    local t_plural = tri(ccfg.TurbineCount == 1, "", "s")
                    local tank = tri(ccfg.TankConnection, "has tank conn", "no tank conn")
                    val = val .. tri(idx == 1, "", "\n") ..
                            util.sprintf(" \x07 unit %d - %d boiler%s, %d turbine%s, %s", idx, ccfg.BoilerCount, b_plural, ccfg.TurbineCount, t_plural, tank)
                end

                if val == "" then val = "no facility tanks" end
            elseif f[1] == "FacilityTankMode" and raw == 0 then val = "no facility tanks"
            elseif f[1] == "FacilityTankDefs" and type(cfg.FacilityTankDefs) == "table" then
                local tank_name_list = { table.unpack(cfg.FacilityTankList) } ---@type (string|integer)[]
                local next_f = 1

                val = ""

                for idx = 1, #tank_name_list do
                    if tank_name_list[idx] == 1 then
                        tank_name_list[idx] = "U" .. idx
                    elseif tank_name_list[idx] == 2 then
                        tank_name_list[idx] = "F" .. next_f
                        next_f = next_f + 1
                    end
                end

                for idx = 1, #cfg.FacilityTankDefs do
                    local t_mode = "not connected to a tank"
                    if cfg.FacilityTankDefs[idx] == 1 then
                        t_mode = "connected to its unit tank (" .. tank_name_list[cfg.FacilityTankConns[idx]] .. ")"
                    elseif cfg.FacilityTankDefs[idx] == 2 then
                        t_mode = "connected to facility tank " .. tank_name_list[cfg.FacilityTankConns[idx]]
                    end

                    val = val .. tri(idx == 1, "", "\n") .. util.sprintf(" \x07 unit %d - %s", idx, t_mode)
                end

                if val == "" then val = "no facility tanks" end
            elseif f[1] == "FacilityTankList" or f[1] == "FacilityTankConns" then
                -- hide these since this info is available in the FacilityTankDefs list (connections) and TankFluidTypes list (list of tanks)
                skip = true
            elseif f[1] == "TankFluidTypes" and type(cfg.TankFluidTypes) == "table" and type(cfg.FacilityTankList) == "table" then
                local tank_list = cfg.FacilityTankList
                local next_f = 1

                val = ""

                local count = 0
                for idx = 1, #tank_list do
                    if tank_list[idx] > 0 then count = count + 1 end
                end

                local bullet = tri(count < 2, "", " \x07 ")

                for idx = 1, #tank_list do
                    local prefix = "?"
                    local fluid = "water"
                    local type = cfg.TankFluidTypes[idx]

                    if tank_list[idx] > 0 then
                        if tank_list[idx] == 1 then
                            prefix = "U" .. idx
                        elseif tank_list[idx] == 2 then
                            prefix = "F" .. next_f
                            next_f = next_f + 1
                        end

                        if type == types.COOLANT_TYPE.SODIUM then
                            fluid = "sodium"
                        end

                        val = val .. tri(val == "", "", "\n") .. util.sprintf(bullet .. "tank %s - %s", prefix, fluid)
                    end
                end

                if val == "" then val = "no emergency coolant tanks" end
            elseif f[1] == "AuxiliaryCoolant" then
                val = ""

                local count = 0
                for idx = 1, #cfg.AuxiliaryCoolant do
                    if cfg.AuxiliaryCoolant[idx] then count = count + 1 end
                end

                local bullet = tri(count < 2, "", " \x07 ")

                for idx = 1, #cfg.AuxiliaryCoolant do
                    if cfg.AuxiliaryCoolant[idx] then
                        val = val .. tri(val == "", "", "\n") .. util.sprintf(bullet .. "unit %d", idx)
                    end
                end

                if val == "" then val = "no auxiliary coolant" end
            elseif f[1] == "MekanismConfig" then
                val = ""

                if type(cfg.MekanismConfig) == "table" then
                    for k, v in pairs(cfg.MekanismConfig) do
                        local value = (string.format("%.10f", v)):gsub("%.?0+$", "")
                        val = val .. tri(val == "", "", "\n") .. util.sprintf(" \x07 %s = %s", k, value)
                    end
                end
            elseif f[1] == "MekanismWasteToPu" or f[1] == "MekanismWasteToPo" then
                val = raw[1] .. ":" .. raw[2]
            elseif f[1] == "PLC_Listen" or f[1] == "RTU_Listen" or f[1] == "CRD_Listen" then
                if raw == LISTEN_MODE.WIRELESS then val = "Wireless Only"
                elseif raw == LISTEN_MODE.WIRED then val = "Wired Only"
                elseif raw == LISTEN_MODE.ALL then val = "Wireless and Wired" end
            end

            if not skip then
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
                    textbox = TextBox{parent=line,y=2,text=val,height=height-1}
                else
                    textbox = TextBox{parent=line,x=label_w+1,y=1,text=val,alignment=RIGHT}
                end

                if f[1] == "AuthKey" then self.auth_key_textbox = textbox end
            end
        end
    end

    -- generate the list of available/assigned wired modems
    function tool_ctl.gen_modem_list()
        modem_list.remove_all()

        local enable = wired.get_value()

        local function select(iface)
            tmp_cfg.WiredModem = iface
            tool_ctl.gen_modem_list()
        end

        local modems  = ppm.get_wired_modem_list()
        local missing = { tmp = true, ini = true }

        for iface, _ in pairs(modems) do
            if ini_cfg.WiredModem == iface then missing.ini = false end
            if tmp_cfg.WiredModem == iface then missing.tmp = false end
        end

        if missing.tmp and tmp_cfg.WiredModem then
            local line = Div{parent=modem_list,y=1,height=1}

            TextBox{parent=line,y=1,width=4,text="Used",fg_bg=cpair(tri(enable,colors.blue,colors.gray),colors.white)}
            PushButton{parent=line,x=6,y=1,min_width=8,height=1,text="SELECT",callback=function()end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=g_lg_fg_bg}.disable()
            TextBox{parent=line,x=15,y=1,text="[missing]",fg_bg=cpair(colors.red,colors.white)}
            TextBox{parent=line,x=25,y=1,text=tmp_cfg.WiredModem}
        end

        if missing.ini and ini_cfg.WiredModem and (tmp_cfg.WiredModem ~= ini_cfg.WiredModem) then
            local line = Div{parent=modem_list,y=1,height=1}
            local used = tmp_cfg.WiredModem == ini_cfg.WiredModem

            TextBox{parent=line,y=1,width=4,text=tri(used,"Used","----"),fg_bg=cpair(tri(used and enable,colors.blue,colors.gray),colors.white)}
            local select_btn = PushButton{parent=line,x=6,y=1,min_width=8,height=1,text="SELECT",callback=function()select(ini_cfg.WiredModem)end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=g_lg_fg_bg}
            TextBox{parent=line,x=15,y=1,text="[missing]",fg_bg=cpair(colors.red,colors.white)}
            TextBox{parent=line,x=25,y=1,text=ini_cfg.WiredModem}

            if used or not enable then select_btn.disable() end
        end

        -- list wired modems
        for iface, _ in pairs(modems) do
            local line = Div{parent=modem_list,y=1,height=1}
            local used = tmp_cfg.WiredModem == iface

            TextBox{parent=line,y=1,width=4,text=tri(used,"Used","----"),fg_bg=cpair(tri(used and enable,colors.blue,colors.gray),colors.white)}
            local select_btn = PushButton{parent=line,x=6,y=1,min_width=8,height=1,text="SELECT",callback=function()select(iface)end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=g_lg_fg_bg}
            TextBox{parent=line,x=15,y=1,text=iface}

            if used or not enable then select_btn.disable() end
        end
    end

    --#endregion
end

return system
