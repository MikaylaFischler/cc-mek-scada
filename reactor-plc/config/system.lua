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
local Radio2D     = require("graphics.elements.controls.Radio2D")
local RadioButton = require("graphics.elements.controls.RadioButton")

local NumberField = require("graphics.elements.form.NumberField")
local TextField   = require("graphics.elements.form.TextField")

local IndLight    = require("graphics.elements.indicators.IndicatorLight")

local tri = util.trinary

local cpair = core.cpair

local RIGHT = core.ALIGN.RIGHT

local self = {
    importing_legacy = false,

    set_networked = nil,    ---@type function
    bundled_emcool = nil,   ---@type function

    wireless = nil,         ---@type Checkbox
    wl_pref = nil,          ---@type Checkbox
    wired = nil,            ---@type Checkbox
    range = nil,            ---@type NumberField
    show_auth_key = nil,    ---@type function
    show_key_btn = nil,     ---@type PushButton
    auth_key_textbox = nil, ---@type TextBox
    auth_key_value = ""
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

local system = {}

-- create the system configuration view
---@param tool_ctl _plc_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ plc_config, plc_config, plc_config, { [1]: string, [2]: string, [3]: any }[], function ]
---@param divs Div[]
---@param style { [string]: cpair }
---@param exit function
function system.create(tool_ctl, main_pane, cfg_sys, divs, style, exit)
    local settings_cfg, ini_cfg, tmp_cfg, fields, load_settings = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]
    local plc_cfg, net_cfg, log_cfg, clr_cfg, summary = divs[1], divs[2], divs[3], divs[4], divs[5]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    --#region PLC

    local plc_c_1 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_2 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_3 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_4 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_5 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_6 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_7 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_8 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_9 = Div{parent=plc_cfg,x=2,y=4,width=49}

    local plc_pane = MultiPane{parent=plc_cfg,y=4,panes={plc_c_1,plc_c_2,plc_c_3,plc_c_4,plc_c_5,plc_c_6,plc_c_7,plc_c_8,plc_c_9}}

    TextBox{parent=plc_cfg,y=2,text=" PLC Configuration",fg_bg=cpair(colors.black,colors.orange)}

    TextBox{parent=plc_c_1,y=1,text="Would you like to set this PLC as networked?"}
    TextBox{parent=plc_c_1,y=3,height=4,text="If you have a supervisor, select the box. You will later be prompted to select the network configuration. If you instead want to use this as a standalone safety system, don't select the box.",fg_bg=g_lg_fg_bg}

    local networked = Checkbox{parent=plc_c_1,y=8,label="Networked",default=ini_cfg.Networked,box_fg_bg=cpair(colors.orange,colors.black)}

    local function submit_networked()
        self.set_networked(networked.get_value())
        plc_pane.set_value(2)
    end

    PushButton{parent=plc_c_1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_1,x=44,y=14,text="Next \x1a",callback=submit_networked,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=plc_c_2,y=1,text="Please enter the reactor unit ID for this PLC."}
    TextBox{parent=plc_c_2,y=3,height=3,text="If this is a networked PLC, currently only IDs 1 through 4 are acceptable.",fg_bg=g_lg_fg_bg}

    TextBox{parent=plc_c_2,y=6,text="Unit #"}
    local u_id = NumberField{parent=plc_c_2,x=7,y=6,width=5,max_chars=3,default=ini_cfg.UnitID,min=1,fg_bg=bw_fg_bg}

    local u_id_err = TextBox{parent=plc_c_2,x=8,y=14,width=35,text="Please set a unit ID.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    function self.set_networked(enable)
        tmp_cfg.Networked = enable
        if enable then u_id.set_max(4) else u_id.set_max(999) end
    end

    local function submit_id()
        local unit_id = tonumber(u_id.get_value())
        if unit_id ~= nil then
            u_id_err.hide(true)
            tmp_cfg.UnitID = unit_id
            plc_pane.set_value(3)
        else u_id_err.show() end
    end

    PushButton{parent=plc_c_2,y=14,text="\x1b Back",callback=function()plc_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_2,x=44,y=14,text="Next \x1a",callback=submit_id,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=plc_c_3,y=1,height=4,text="When networked, the Supervisor takes care of emergency coolant via RTUs. However, you can configure independent emergency coolant via the PLC."}
    TextBox{parent=plc_c_3,y=6,height=5,text="This independent control can be used with or without a supervisor. To configure, you would next select the interface of the redstone output connected to one or more mekanism pipes.",fg_bg=g_lg_fg_bg}

    local en_em_cool = Checkbox{parent=plc_c_3,y=11,label="Enable PLC Emergency Coolant Control",default=ini_cfg.EmerCoolEnable,box_fg_bg=cpair(colors.orange,colors.black)}

    local function next_from_emcool()
        if tmp_cfg.Networked then plc_pane.set_value(6) else main_pane.set_value(4) end
    end

    local function submit_en_emcool()
        tmp_cfg.EmerCoolEnable = en_em_cool.get_value()
        if tmp_cfg.EmerCoolEnable then plc_pane.set_value(4) else next_from_emcool() end
    end

    PushButton{parent=plc_c_3,y=14,text="\x1b Back",callback=function()plc_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_3,x=44,y=14,text="Next \x1a",callback=submit_en_emcool,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=plc_c_4,y=1,text="Emergency Coolant Redstone Output Side"}
    local side = Radio2D{parent=plc_c_4,y=2,rows=2,columns=3,default=side_to_idx(ini_cfg.EmerCoolSide),options=side_options,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.orange}

    TextBox{parent=plc_c_4,y=5,text="Bundled Redstone Configuration"}
    local bundled = Checkbox{parent=plc_c_4,y=6,label="Is Bundled?",default=ini_cfg.EmerCoolColor~=nil,box_fg_bg=cpair(colors.orange,colors.black),callback=function(v)self.bundled_emcool(v)end}
    local color = Radio2D{parent=plc_c_4,y=8,rows=4,columns=4,default=color_to_idx(ini_cfg.EmerCoolColor),options=color_options,radio_colors=cpair(colors.lightGray,colors.black),color_map=color_options_map,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
    if ini_cfg.EmerCoolColor == nil then color.disable() end

    function self.bundled_emcool(en) if en then color.enable() else color.disable() end end

    TextBox{parent=plc_c_5,y=1,height=5,text="Advanced Options"}
    local invert = Checkbox{parent=plc_c_5,y=3,label="Invert",default=ini_cfg.EmerCoolInvert,box_fg_bg=cpair(colors.orange,colors.black)}
    TextBox{parent=plc_c_5,x=3,y=4,height=4,text="Digital I/O is already inverted (or not) based on intended use. If you have a non-standard setup, you can use this option to avoid needing a redstone inverter.",fg_bg=cpair(colors.gray,colors.lightGray)}
    PushButton{parent=plc_c_5,y=14,text="\x1b Back",callback=function()plc_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    local function submit_emcool()
        tmp_cfg.EmerCoolSide = side_options_map[side.get_value()]
        tmp_cfg.EmerCoolColor = tri(bundled.get_value(), color_options_map[color.get_value()], nil)
        tmp_cfg.EmerCoolInvert = invert.get_value()
        next_from_emcool()
    end

    PushButton{parent=plc_c_4,y=14,text="\x1b Back",callback=function()plc_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_4,x=33,y=14,min_width=10,text="Advanced",callback=function()plc_pane.set_value(5)end,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    PushButton{parent=plc_c_4,x=44,y=14,text="Next \x1a",callback=submit_emcool,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=plc_c_6,y=1,height=6,text="Slow ramping is always used up to 40 mB/t, which is ~5 mB/t per second. If you enable fast ramping, it will then hold at 40 mB/t until cooled coolant stabilizes (at least 2 seconds) then increase to a faster ramp rate, which is a percentage of the maximum burn rate."}
    TextBox{parent=plc_c_6,y=8,height=3,text="When fast ramping is used, if the reactor drops below 80% cooled coolant, it will scale back the ramping proportionally as the coolant level drops.",fg_bg=g_lg_fg_bg}

    local fast_ramp = Checkbox{parent=plc_c_6,y=12,label="Enable Fast Ramping",default=ini_cfg.FastRamp,box_fg_bg=cpair(colors.orange,colors.black)}
    TextBox{parent=plc_c_6,x=23,y=12,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision

    local function submit_ramp()
        tmp_cfg.FastRamp = fast_ramp.get_value()

        if tmp_cfg.FastRampConfirmed or ini_cfg.FastRampConfirmed then
            plc_pane.set_value(8)
        else plc_pane.set_value(7) end
    end

    PushButton{parent=plc_c_6,y=14,text="\x1b Back",callback=function()plc_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_6,x=44,y=14,text="Next \x1a",callback=submit_ramp,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=plc_c_7,y=1,text="!! CAUTION !!",fg_bg=cpair(colors.red,colors._INHERIT)}
    TextBox{parent=plc_c_7,y=2,height=6,text="Fast ramping has an increased risk of your reactor running low on coolant and overheating. First test this under supervision, as an insufficient cooling setup or lack of auxiliary coolant can cause the reactor to ramp faster than your turbine(s)/boiler(s) can handle."}
    TextBox{parent=plc_c_7,y=9,height=3,text="In nearly all cases, the automatic SCRAM will still prevent a meltdown if coolant was not lost.",fg_bg=g_lg_fg_bg}
    TextBox{parent=plc_c_7,y=12,height=1,text="If you didn't mean to enable this, go back.",fg_bg=cpair(colors.cyan,colors._INHERIT)}

    local fast_ramp_confirm = Checkbox{parent=plc_c_7,y=14,x=13,label="Don't show this warning again",default=ini_cfg.FastRampConfirmed,box_fg_bg=cpair(colors.orange,colors.black)}

    local function submit_ramp_conf()
        tmp_cfg.FastRampConfirmed = fast_ramp_confirm.get_value()
        plc_pane.set_value(8)
    end

    PushButton{parent=plc_c_7,y=14,text="\x1b Back",callback=function()plc_pane.set_value(6)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_7,x=8,y=14,text=" OK ",callback=submit_ramp_conf,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=plc_c_8,y=1,height=2,text="Below you can enable burn rate limiting under low fuel conditions during automatic control."}
    TextBox{parent=plc_c_8,y=4,height=4,text="When under automatic control and below 30% fuel, the PLC can attempt to limit the maximum burn rate to a sustainable level until fuel is filled beyond 40%.",fg_bg=g_lg_fg_bg}

    local fuel_limit = Checkbox{parent=plc_c_8,y=9,label="Enable Low-Fuel Burn Rate Limiting",default=ini_cfg.FuelAutoLimiting,box_fg_bg=cpair(colors.orange,colors.black)}
    TextBox{parent=plc_c_8,x=3,y=10,text="Supervisor Auto Control Only",fg_bg=g_lg_fg_bg}
    TextBox{parent=plc_c_8,x=38,y=9,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision

    local function submit_fuel_limit()
        tmp_cfg.FuelAutoLimiting = fuel_limit.get_value()
        plc_pane.set_value(9)
    end

    PushButton{parent=plc_c_8,y=14,text="\x1b Back",callback=function()plc_pane.set_value(6)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_8,x=44,y=14,text="Next \x1a",callback=submit_fuel_limit,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=plc_c_9,y=1,height=3,text="A separate front panel page can be enabled to view diagnostics information. This is useful for debugging, development, or satisfying curiosity."}
    TextBox{parent=plc_c_9,y=5,height=6,text="A DIAG button will be shown on the front panel to access it. Be aware that the diagnostics rapidly refresh with information, which can negatively impact performance. When not in use, use BACK to close it. Using escape to close out the computer does not stop the page from updating.",fg_bg=g_lg_fg_bg}

    local en_diag = Checkbox{parent=plc_c_9,y=12,label="Enable Diagnostics Panel",default=ini_cfg.EnableDiagnostics,box_fg_bg=cpair(colors.orange,colors.black)}
    TextBox{parent=plc_c_9,x=28,y=12,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision

    local function submit_diag()
        tmp_cfg.EnableDiagnostics = en_diag.get_value()
        main_pane.set_value(3)
    end

    PushButton{parent=plc_c_9,y=14,text="\x1b Back",callback=function()plc_pane.set_value(8)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=plc_c_9,x=44,y=14,text="Next \x1a",callback=submit_diag,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Network

    local net_c_1 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_2 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_3 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_4 = Div{parent=net_cfg,x=2,y=4,width=49}

    local net_pane = MultiPane{parent=net_cfg,y=4,panes={net_c_1,net_c_2,net_c_3,net_c_4}}

    TextBox{parent=net_cfg,y=2,text=" Network Configuration",fg_bg=cpair(colors.black,colors.lightBlue)}

    TextBox{parent=net_c_1,y=1,text="Please select the network interface(s)."}
    TextBox{parent=net_c_1,x=41,y=1,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision

    local function en_dis_pref()
        if self.wireless.get_value() and self.wired.get_value() then
            self.wl_pref.enable()
        else
            self.wl_pref.set_value(self.wireless.get_value())
            self.wl_pref.disable()
        end
    end

    local function on_wired_change(_)
        en_dis_pref()
        tool_ctl.gen_modem_list()
    end

    self.wireless = Checkbox{parent=net_c_1,y=3,label="Wireless/Ender Modem",default=ini_cfg.WirelessModem,box_fg_bg=cpair(colors.lightBlue,colors.black),callback=en_dis_pref}
    self.wl_pref = Checkbox{parent=net_c_1,x=30,y=3,label="Prefer Wireless",default=ini_cfg.PreferWireless,box_fg_bg=cpair(colors.lightBlue,colors.black),disable_fg_bg=g_lg_fg_bg}
    self.wired = Checkbox{parent=net_c_1,y=5,label="Wired Modem",default=ini_cfg.WiredModem~=false,box_fg_bg=cpair(colors.lightBlue,colors.black),callback=on_wired_change}
    TextBox{parent=net_c_1,x=3,y=6,text="this one MUST ONLY connect to SCADA computers",fg_bg=cpair(colors.red,colors._INHERIT)}
    TextBox{parent=net_c_1,x=3,y=7,text="connecting it to peripherals will cause issues",fg_bg=g_lg_fg_bg}
    local modem_list = ListBox{parent=net_c_1,y=8,height=5,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local modem_err = TextBox{parent=net_c_1,x=8,y=14,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    en_dis_pref()

    local function submit_interfaces()
        tmp_cfg.WirelessModem = self.wireless.get_value()

        if tmp_cfg.WirelessModem and tmp_cfg.WiredModem then
            tmp_cfg.PreferWireless = self.wl_pref.get_value()
        else
            tmp_cfg.PreferWireless = tmp_cfg.WirelessModem
            self.wl_pref.set_value(tmp_cfg.PreferWireless)
        end

        if not self.wired.get_value() then
            tmp_cfg.WiredModem = false
            tool_ctl.gen_modem_list()
        end

        if not (self.wired.get_value() or self.wireless.get_value()) then
            modem_err.set_value("Please select a modem type.")
            modem_err.show()
        elseif self.wired.get_value() and type(tmp_cfg.WiredModem) ~= "string" then
            modem_err.set_value("Please select a wired modem.")
            modem_err.show()
        else
            if tmp_cfg.WirelessModem then
                self.range.enable()
            else
                self.range.set_value(0)
                self.range.disable()
            end

            net_pane.set_value(2)
            modem_err.hide(true)
        end
    end

    PushButton{parent=net_c_1,y=14,text="\x1b Back",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_1,x=44,y=14,text="Next \x1a",callback=submit_interfaces,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_2,y=1,text="Please set the network channels below."}
    TextBox{parent=net_c_2,y=3,height=4,text="Each of the 5 uniquely named channels, including the 2 below, must be the same for each device in this SCADA network. For multiplayer servers, it is recommended to not use the default channels.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_2,y=8,text="Supervisor Channel"}
    local svr_chan = NumberField{parent=net_c_2,y=9,width=7,default=ini_cfg.SVR_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_2,x=9,y=9,height=4,text="[SVR_CHANNEL]",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_2,y=11,text="PLC Channel"}
    local plc_chan = NumberField{parent=net_c_2,y=12,width=7,default=ini_cfg.PLC_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_2,x=9,y=12,height=4,text="[PLC_CHANNEL]",fg_bg=g_lg_fg_bg}

    local chan_err = TextBox{parent=net_c_2,x=8,y=14,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_channels()
        local svr_c = tonumber(svr_chan.get_value())
        local plc_c = tonumber(plc_chan.get_value())
        if svr_c ~= nil and plc_c ~= nil then
            tmp_cfg.SVR_Channel = svr_c
            tmp_cfg.PLC_Channel = plc_c
            net_pane.set_value(3)
            chan_err.hide(true)
        elseif svr_c == nil then
            chan_err.set_value("Please set the supervisor channel.")
            chan_err.show()
        else
            chan_err.set_value("Please set the PLC channel.")
            chan_err.show()
        end
    end

    PushButton{parent=net_c_2,y=14,text="\x1b Back",callback=function()net_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_2,x=44,y=14,text="Next \x1a",callback=submit_channels,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_3,y=1,text="Connection Timeout"}
    local timeout = NumberField{parent=net_c_3,y=2,width=7,default=ini_cfg.ConnTimeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_3,x=9,y=2,height=2,text="seconds (default 5)",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_3,y=3,height=4,text="You generally do not want or need to modify this. On slow servers, you can increase this to make the system wait longer before assuming a disconnection.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_3,y=8,text="Trusted Range (Wireless Only)"}
    self.range = NumberField{parent=net_c_3,y=9,width=10,default=ini_cfg.TrustedRange,min=0,max_chars=20,allow_decimal=true,fg_bg=bw_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    TextBox{parent=net_c_3,y=10,height=4,text="Setting this to a value larger than 0 prevents wireless connections with devices that many meters (blocks) away in any direction.",fg_bg=g_lg_fg_bg}

    local n3_err = TextBox{parent=net_c_3,x=8,y=14,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_ct_tr()
        local timeout_val = tonumber(timeout.get_value())
        local range_val = tonumber(self.range.get_value())

        if timeout_val == nil then
            n3_err.set_value("Please set the connection timeout.")
            n3_err.show()
        elseif tmp_cfg.WirelessModem and (range_val == nil) then
            n3_err.set_value("Please set the trusted range.")
            n3_err.show()
        else
            tmp_cfg.ConnTimeout = timeout_val
            tmp_cfg.TrustedRange = tri(tmp_cfg.WirelessModem, range_val, 0)

            if tmp_cfg.WirelessModem then
                net_pane.set_value(4)
            else
                main_pane.set_value(4)
                tmp_cfg.AuthKey = ""
            end

            n3_err.hide(true)
        end
    end

    PushButton{parent=net_c_3,y=14,text="\x1b Back",callback=function()net_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_3,x=44,y=14,text="Next \x1a",callback=submit_ct_tr,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_4,y=1,height=2,text="Optionally, set the facility authentication key below. Do NOT use one of your passwords."}
    TextBox{parent=net_c_4,y=4,height=6,text="This enables verifying that messages are authentic, so it is intended for wireless security on multiplayer servers. All devices on the same wireless network MUST use the same key if any device has a key. This does result in some extra computation (can slow things down).",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_4,y=11,text="Auth Key (Wireless Only, Not Used for Wired)"}
    local key, _ = TextField{parent=net_c_4,y=12,max_len=64,value=ini_cfg.AuthKey,width=32,height=1,fg_bg=bw_fg_bg}

    local function censor_key(enable) key.censor(tri(enable, "*", nil)) end

    local hide_key = Checkbox{parent=net_c_4,x=34,y=12,label="Hide",box_fg_bg=cpair(colors.lightBlue,colors.black),callback=censor_key}

    hide_key.set_value(true)
    censor_key(true)

    local key_err = TextBox{parent=net_c_4,x=8,y=14,width=35,text="Key must be at least 8 characters.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_auth()
        local v = key.get_value()
        if string.len(v) == 0 or string.len(v) >= 8 then
            tmp_cfg.AuthKey = key.get_value()
            main_pane.set_value(4)
            key_err.hide(true)
        else key_err.show() end
    end

    PushButton{parent=net_c_4,y=14,text="\x1b Back",callback=function()net_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_4,x=44,y=14,text="Next \x1a",callback=submit_auth,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

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
            main_pane.set_value(5)
        else path_err.show() end
    end

    local function back_from_log()
        if tmp_cfg.Networked then main_pane.set_value(3) else main_pane.set_value(2) end
    end

    PushButton{parent=log_c_1,y=14,text="\x1b Back",callback=back_from_log,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
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
            self.importing_legacy = false
            tool_ctl.settings_apply.show()
            main_pane.set_value(6)
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
            main_pane.set_value(5)
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

        if settings.save("/reactor-plc.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)

            try_set(networked, ini_cfg.Networked)
            try_set(u_id, ini_cfg.UnitID)
            try_set(en_em_cool, ini_cfg.EmerCoolEnable)
            try_set(side, side_to_idx(ini_cfg.EmerCoolSide))
            try_set(bundled, ini_cfg.EmerCoolColor ~= nil)
            if ini_cfg.EmerCoolColor ~= nil then try_set(color, color_to_idx(ini_cfg.EmerCoolColor)) end
            try_set(invert, ini_cfg.EmerCoolInvert)
            try_set(fast_ramp, ini_cfg.FastRamp)
            try_set(fast_ramp_confirm, ini_cfg.FastRampConfirmed)
            try_set(fuel_limit, ini_cfg.FuelAutoLimiting)
            try_set(en_diag, ini_cfg.EnableDiagnostics)
            try_set(self.wireless, ini_cfg.WirelessModem)
            try_set(self.wired, ini_cfg.WiredModem ~= false)
            try_set(self.wl_pref, ini_cfg.PreferWireless)
            try_set(svr_chan, ini_cfg.SVR_Channel)
            try_set(plc_chan, ini_cfg.PLC_Channel)
            try_set(timeout, ini_cfg.ConnTimeout)
            try_set(self.range, ini_cfg.TrustedRange)
            try_set(key, ini_cfg.AuthKey)
            try_set(mode, ini_cfg.LogMode)
            try_set(path, ini_cfg.LogPath)
            try_set(en_dbg, ini_cfg.LogDebug)
            try_set(fp_theme, ini_cfg.FrontPanelTheme)
            try_set(c_mode, ini_cfg.ColorMode)

            tool_ctl.view_cfg.enable()
            tool_ctl.color_cfg.enable()

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
    TextBox{parent=sum_c_2,y=3,text="Tip: you can run a Self-Check from the configurator home screen to make sure everything is going to work right!"}

    local function go_home()
        main_pane.set_value(1)
        plc_pane.set_value(1)
        net_pane.set_value(1)
        clr_pane.set_value(1)
        sum_pane.set_value(1)
    end

    PushButton{parent=sum_c_2,y=14,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_2,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_3,y=1,height=2,text="The old config.lua file will now be deleted, then the configurator will exit."}

    local function delete_legacy()
        fs.delete("/reactor-plc/config.lua")
        exit()
    end

    PushButton{parent=sum_c_3,y=14,min_width=8,text="Cancel",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_3,x=44,y=14,min_width=6,text="OK",callback=delete_legacy,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_4,y=1,height=5,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=sum_c_4,y=14,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_4,x=44,y=14,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    --#endregion

    --#region Tool Functions

    -- load a legacy config file
    function tool_ctl.load_legacy()
        local config = require("reactor-plc.config")

        tmp_cfg.Networked = config.NETWORKED
        tmp_cfg.UnitID = config.REACTOR_ID
        tmp_cfg.FastRamp = false
        tmp_cfg.FastRampConfirmed = false
        tmp_cfg.FuelAutoLimiting = false
        tmp_cfg.EnableDiagnostics = false
        tmp_cfg.EmerCoolEnable = type(config.EMERGENCY_COOL) == "table"

        if tmp_cfg.EmerCoolEnable then
            tmp_cfg.EmerCoolSide = config.EMERGENCY_COOL.side
            tmp_cfg.EmerCoolColor = config.EMERGENCY_COOL.color
            tmp_cfg.EmerCoolInvert = false
        else
            tmp_cfg.EmerCoolSide = nil
            tmp_cfg.EmerCoolColor = nil
            tmp_cfg.EmerCoolInvert = false
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
        self.importing_legacy = true
    end

    -- expose the auth key on the summary page
    function self.show_auth_key()
        self.show_key_btn.disable()
        self.auth_key_textbox.set_value(self.auth_key_value)
    end

    -- generate the summary list
    ---@param cfg plc_config
    function tool_ctl.gen_summary(cfg)
        setting_list.remove_all()

        local alternate = false
        local inner_width = setting_list.get_width() - 1

        if cfg.AuthKey then self.show_key_btn.enable() else self.show_key_btn.disable() end
        self.auth_key_value = cfg.AuthKey or "" -- to show auth key

        for i = 1, #fields do
            local f = fields[i]
            local height = 1
            local label_w = string.len(f[2])
            local val_max_w = (inner_width - label_w) + 1
            local raw = cfg[f[1]]
            local val = util.strval(raw)

            if f[1] == "AuthKey" and raw then val = string.rep("*", string.len(val))
            elseif f[1] == "LogMode" then val = tri(raw == log.MODE.APPEND, "append", "replace")
            elseif f[1] == "EmerCoolColor" and raw ~= nil then val = rsio.color_name(raw)
            elseif f[1] == "FrontPanelTheme" then
                val = util.strval(themes.fp_theme_name(raw))
            elseif f[1] == "ColorMode" then
                val = util.strval(themes.color_mode_name(raw))
            end

            if val == "nil" then val = "<not set>" end

            local c = tri(alternate, g_lg_fg_bg, cpair(colors.gray,colors.white))

            if (string.len(val) > val_max_w) or string.find(val, "\n") then
                local lines = util.strwrap(val, inner_width)
                height = #lines + 1
            end

            local textbox

            if f[1] ~= "FastRampConfirmed" then
                alternate = not alternate

                local line = Div{parent=setting_list,height=height,fg_bg=c}
                TextBox{parent=line,text=f[2],width=string.len(f[2]),fg_bg=cpair(colors.black,line.get_fg_bg().bkg)}

                if height > 1 then
                    textbox = TextBox{parent=line,y=2,text=val,height=height-1}
                else
                    textbox = TextBox{parent=line,x=label_w+1,y=1,text=val,alignment=RIGHT}
                end
            end

            if f[1] == "AuthKey" then self.auth_key_textbox = textbox end
        end
    end

    -- generate the list of available/assigned wired modems
    function tool_ctl.gen_modem_list()
        modem_list.remove_all()

        local enable = self.wired.get_value()

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
