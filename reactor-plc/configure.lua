--
-- Configuration GUI
--

local log = require("scada-common.log")
local tcd = require("scada-common.tcd")
local util = require("scada-common.util")

log.init("/log.txt", log.MODE.APPEND, true)

local core       = require("graphics.core")

local DisplayBox = require("graphics.elements.displaybox")
local Div        = require("graphics.elements.div")
local MultiPane  = require("graphics.elements.multipane")
local Rectangle  = require("graphics.elements.rectangle")
local TextBox    = require("graphics.elements.textbox")

local RadioButton       = require("graphics.elements.controls.radio_button")
local PushButton = require("graphics.elements.controls.push_button")
local CheckBox = require("graphics.elements.controls.checkbox")

local NumberField = require("graphics.elements.form.number_field")
local TextField = require("graphics.elements.form.text_field")

local ListBox = require("graphics.elements.listbox")

local print = util.print
local println = util.println

local cpair = core.cpair

local LEFT = core.TEXT_ALIGN.LEFT
local CENTER = core.TEXT_ALIGN.CENTER
local RIGHT = core.TEXT_ALIGN.RIGHT

---@class plc_configurator
local configurator = {}

local style = {}

style.root = cpair(colors.black, colors.lightGray)
style.header = cpair(colors.white, colors.gray)
style.label = cpair(colors.gray, colors.lightGray)

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
    -- { c = colors.white,     hex = 0xf0f0f0 },
    { c = colors.lightGray, hex = 0xcacaca },
    { c = colors.gray,      hex = 0x575757 },
    -- { c = colors.black,     hex = 0x191919 },
    -- { c = colors.brown,     hex = 0x7f664c }
}

local tool_ctl = {
    need_config = false,

    set_networked = nil, ---@type function
    next_from_plc = nil, ---@type function
    back_from_log = nil, ---@type function
    gen_summary = nil    ---@type function
}

local tmp_cfg = {
    Networked = false,
    UnitID = 0,
    SVR_Channel = 0,
    PLC_Channel = 0,
    ConnTimeout = 0,
    TrustedRange = 0,
    AuthKey = "",
    LogMode = 0,
    LogPath = "",
    LogDebug = false,
}

local fields = {
    -- printed name, tmp_cfg name, requires_network
    { "Networked", "Networked", false },
    { "Unit ID", "UnitID", false },
    { "SVR Channel", "SVR_Channel", true },
    { "PLC Channel", "PLC_Channel", true },
    { "Connection Timeout", "ConnTimeout", true },
    { "Trusted Range", "TrustedRange", true },
    { "Facility Auth Key", "AuthKey", true },
    { "Log Mode", "LogMode", false },
    { "Log Path", "LogPath", false },
    { "Log Debug Messages", "LogDebug", false }
}

local function _config_view(display)
    -- window header message
    TextBox{parent=display,y=1,text="Reactor PLC Configurator",alignment=CENTER,height=1,fg_bg=style.header}

    local root_pane_div = Div{parent=display,x=1,y=2}

    local main_page = Div{parent=root_pane_div,x=1,y=1}
    local plc_cfg = Div{parent=root_pane_div,x=1,y=1}
    local net_cfg = Div{parent=root_pane_div,x=1,y=1}
    local log_cfg = Div{parent=root_pane_div,x=1,y=1}
    local summary = Div{parent=root_pane_div,x=1,y=1}

    local main_pane = MultiPane{parent=root_pane_div,x=1,y=1,panes={main_page,plc_cfg,net_cfg,log_cfg,summary}}

    -- MAIN PAGE

    local y_offset = 0

    TextBox{parent=main_page,x=2,y=2,height=2,text_align=CENTER,text="Welcome to the Reactor PLC configurator! Please select one of the following options."}

    if tool_ctl.need_config then
        y_offset = 3
        TextBox{parent=main_page,x=2,y=5,height=2,text_align=CENTER,text="Notice: This Reactor PLC is not configured. The configurator has been automatically started.",fg_bg=cpair(colors.red,colors.lightGray)}
    end

    PushButton{parent=main_page,x=2,y=y_offset+5,min_width=18,text="Configure System",callback=function()main_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=cpair(colors.white,colors.gray)}
    PushButton{parent=main_page,x=2,y=y_offset+7,min_width=20,text="View Configuration",callback=function()end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=cpair(colors.white,colors.gray)}

    if fs.exists("/reactor-plc/config.lua") then
        PushButton{parent=main_page,x=2,y=y_offset+9,min_width=28,text="Import Legacy 'config.lua'",callback=function()end,fg_bg=cpair(colors.black,colors.cyan),active_fg_bg=cpair(colors.white,colors.gray)}
    end

---@diagnostic disable-next-line: undefined-field
    PushButton{parent=main_page,x=2,y=17,min_width=6,text="Exit",callback=function()os.queueEvent("terminate")end,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    local nav_fg_bg = cpair(colors.black,colors.white)
    local nav_a_fg_bg = cpair(colors.white,colors.gray)

    -- PLC CONFIG

    local plc_c_1 = Div{parent=plc_cfg,x=2,y=4,width=49}
    local plc_c_2 = Div{parent=plc_cfg,x=2,y=4,width=49}

    local plc_pane = MultiPane{parent=plc_cfg,x=1,y=4,panes={plc_c_1,plc_c_2}}

    TextBox{parent=plc_cfg,x=1,y=2,height=1,text_align=CENTER,text=" PLC Configuration",fg_bg=cpair(colors.black,colors.orange)}

    TextBox{parent=plc_c_1,x=1,y=1,height=1,text_align=CENTER,text="Would you like to set this PLC as networked?"}
    TextBox{parent=plc_c_1,x=1,y=3,height=4,text_align=CENTER,text="If you have a supervisor, select the box. You will later be prompted to select the network configuration. If you instead want to use this as a standalone safety system, don't select the box.",fg_bg=cpair(colors.gray,colors.lightGray)}

    CheckBox{parent=plc_c_1,x=1,y=8,label="Networked",box_fg_bg=cpair(colors.orange,colors.black),callback=function(v)tool_ctl.set_networked(v)end}

    PushButton{parent=plc_c_1,x=1,y=14,min_width=6,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}
    PushButton{parent=plc_c_1,x=44,y=14,min_width=6,text="Next \x1a",callback=function()plc_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}

    TextBox{parent=plc_c_2,x=1,y=1,height=1,text_align=CENTER,text="Please enter the reactor unit ID for this PLC."}
    TextBox{parent=plc_c_2,x=1,y=3,height=3,text_align=CENTER,text="If this is a networked PLC, currently only IDs 1 through 4 are acceptable.",fg_bg=cpair(colors.gray,colors.lightGray)}

    TextBox{parent=plc_c_2,x=1,y=6,height=1,text_align=CENTER,text="Unit #"}
    local u_id = NumberField{parent=plc_c_2,x=7,y=6,width=5,max_digits=3,default=1,min=1,fg_bg=cpair(colors.black,colors.white)}

    local function submit_id()
        tmp_cfg.UnitID = u_id.get_value()
        tool_ctl.next_from_plc()
    end

    PushButton{parent=plc_c_2,x=1,y=14,min_width=6,text="\x1b Back",callback=function()plc_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}
    PushButton{parent=plc_c_2,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_id,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}

    -- NET CONFIG

    local net_c_1 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_2 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_3 = Div{parent=net_cfg,x=2,y=4,width=49}

    local net_pane = MultiPane{parent=net_cfg,x=1,y=4,panes={net_c_1,net_c_2,net_c_3}}

    TextBox{parent=net_cfg,x=1,y=2,height=1,text_align=CENTER,text=" Network Configuration",fg_bg=cpair(colors.black,colors.lightBlue)}

    TextBox{parent=net_c_1,x=1,y=1,height=1,text_align=CENTER,text="Please set the network channels below."}
    TextBox{parent=net_c_1,x=1,y=3,height=4,text_align=CENTER,text="Each of the 5 uniquely named channels must be the same for each device in this SCADA network. For multiplayer servers, it is recommended to not use the default channels.",fg_bg=cpair(colors.gray,colors.lightGray)}

    TextBox{parent=net_c_1,x=1,y=8,height=1,text_align=CENTER,text="Supervisor Channel"}
    local svr_chan = NumberField{parent=net_c_1,x=1,y=9,width=7,default=16240,min=1,max=65535,fg_bg=cpair(colors.black,colors.white)}
    TextBox{parent=net_c_1,x=9,y=9,height=4,text_align=CENTER,text="[SVR_CHANNEL]",fg_bg=cpair(colors.gray,colors.lightGray)}
    TextBox{parent=net_c_1,x=1,y=11,height=1,text_align=CENTER,text="PLC Channel"}
    local plc_chan = NumberField{parent=net_c_1,x=1,y=12,width=7,default=16241,min=1,max=65535,fg_bg=cpair(colors.black,colors.white)}
    TextBox{parent=net_c_1,x=9,y=12,height=4,text_align=CENTER,text="[PLC_CHANNEL]",fg_bg=cpair(colors.gray,colors.lightGray)}

    local function submit_channels()
        tmp_cfg.SVR_Channel = svr_chan.get_value()
        tmp_cfg.PLC_Channel = plc_chan.get_value()
        net_pane.set_value(2)
    end

    PushButton{parent=net_c_1,x=1,y=14,min_width=6,text="\x1b Back",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}
    PushButton{parent=net_c_1,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_channels,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}

    TextBox{parent=net_c_2,x=1,y=1,height=1,text_align=CENTER,text="Connection Timeout"}
    local timeout = NumberField{parent=net_c_2,x=1,y=2,width=7,default=5,min=2,max=25,fg_bg=cpair(colors.black,colors.white)}
    TextBox{parent=net_c_2,x=9,y=2,height=2,text_align=CENTER,text="seconds (default 5)",fg_bg=cpair(colors.gray,colors.lightGray)}
    TextBox{parent=net_c_2,x=1,y=3,height=4,text_align=CENTER,text="You generally do not want or need to modify this. On slow servers, you can increase this to make the system wait longer before assuming a disconnection.",fg_bg=cpair(colors.gray,colors.lightGray)}

    TextBox{parent=net_c_2,x=1,y=8,height=1,text_align=CENTER,text="Trusted Range"}
    local range = NumberField{parent=net_c_2,x=1,y=9,width=10,default=0,min=0,max_digits=20,allow_decimal=true,fg_bg=cpair(colors.black,colors.white)}
    TextBox{parent=net_c_2,x=1,y=10,height=4,text_align=CENTER,text="Setting this to a value larger than 0 prevents connections with devices that many meters (blocks) away in any direction.",fg_bg=cpair(colors.gray,colors.lightGray)}

    local function submit_ct_tr()
        tmp_cfg.ConnTimeout = timeout.get_value()
        tmp_cfg.TrustedRange = range.get_value()
        net_pane.set_value(3)
    end

    PushButton{parent=net_c_2,x=1,y=14,min_width=6,text="\x1b Back",callback=function()net_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}
    PushButton{parent=net_c_2,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_ct_tr,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}

    TextBox{parent=net_c_3,x=1,y=1,height=2,text_align=CENTER,text="Optionally, set the facility authentication key below. Do NOT use one of your passwords."}
    TextBox{parent=net_c_3,x=1,y=4,height=6,text_align=CENTER,text="This enables verifying that messages are authentic, so it is intended for security on multiplayer servers. All devices on the same network MUST use the same key if any device has a key. This does result in some extra compution (can slow things down).",fg_bg=cpair(colors.gray,colors.lightGray)}

    TextBox{parent=net_c_3,x=1,y=11,height=1,text_align=CENTER,text="Facility Auth Key"}
    local key, _, censor = TextField{parent=net_c_3,x=1,y=12,max_len=64,width=32,height=1,fg_bg=cpair(colors.black,colors.white)}
    local hide_key = CheckBox{parent=net_c_3,x=34,y=12,label="Hide",box_fg_bg=cpair(colors.lightBlue,colors.black),callback=function(v)censor(util.trinary(v,"*",nil))end}

    local function submit_auth()
        tmp_cfg.AuthKey = key.get_value()
        main_pane.set_value(4)
    end

    PushButton{parent=net_c_3,x=1,y=14,min_width=6,text="\x1b Back",callback=function()net_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}
    PushButton{parent=net_c_3,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_auth,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}

    -- LOG CONFIG

    local log_c_1 = Div{parent=log_cfg,x=2,y=4,width=49}

    TextBox{parent=log_cfg,x=1,y=2,height=1,text_align=CENTER,text=" Logging Configuration",fg_bg=cpair(colors.black,colors.pink)}

    TextBox{parent=log_c_1,x=1,y=1,height=1,text_align=CENTER,text="Please configure logging below."}

    TextBox{parent=log_c_1,x=1,y=3,height=1,text_align=CENTER,text="Log File Mode"}
    local mode = RadioButton{parent=log_c_1,x=1,y=4,options={"Append on Startup","Replace on Startup"},callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.pink}

    TextBox{parent=log_c_1,x=1,y=7,height=1,text_align=CENTER,text="Log File Path"}
    local path = TextField{parent=log_c_1,x=1,y=8,width=49,height=1,value="/log.txt",max_len=128,fg_bg=cpair(colors.black,colors.white)}

    local en_dbg = CheckBox{parent=log_c_1,x=1,y=10,label="Enable Logging Debug Messages",box_fg_bg=cpair(colors.pink,colors.black),callback=function(v)end}
    TextBox{parent=log_c_1,x=3,y=11,height=2,text_align=CENTER,text="This results in much larger log files. It is best to only use this when there is a problem.",fg_bg=cpair(colors.gray,colors.lightGray)}

    local function submit_log()
        tmp_cfg.LogMode = mode.get_value()
        tmp_cfg.LogPath = path.get_value()
        tmp_cfg.LogDebug = en_dbg.get_value()
        tool_ctl.gen_summary()
        main_pane.set_value(5)
    end

    PushButton{parent=log_c_1,x=1,y=14,min_width=6,text="\x1b Back",callback=function()tool_ctl.back_from_log()end,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}
    PushButton{parent=log_c_1,x=44,y=14,min_width=6,text="Next \x1a",callback=submit_log,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}

    -- SUMMARY OF CHANGES

    local sum_c_1 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_2 = Div{parent=summary,x=2,y=4,width=49}

    local sum_pane = MultiPane{parent=summary,x=1,y=4,panes={sum_c_1,sum_c_2}}

    TextBox{parent=summary,x=1,y=2,height=1,text_align=CENTER,text=" Summary",fg_bg=cpair(colors.black,colors.green)}

    local setting_list = ListBox{parent=sum_c_1,x=1,y=1,height=12,width=51,scroll_height=100,fg_bg=cpair(colors.black,colors.white),nav_fg_bg=cpair(colors.gray,colors.lightGray),nav_active=cpair(colors.black,colors.gray)}

    local function save_and_continue()
        -- settings.load(".plc.settings")
        -- settings.set("UnitID", tmp_cfg.UnitID)
        -- settings.save(".plc.settings")
        sum_pane.set_value(2)
    end

    PushButton{parent=sum_c_1,x=1,y=14,min_width=6,text="\x1b Back",callback=function()main_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}
    PushButton{parent=sum_c_1,x=43,y=14,min_width=7,text="Apply",callback=save_and_continue,fg_bg=cpair(colors.black,colors.green),active_fg_bg=nav_a_fg_bg}

    TextBox{parent=sum_c_2,x=1,y=1,height=1,text_align=CENTER,text="Settings saved!"}

    local function go_home()
        main_pane.set_value(1)
        plc_pane.set_value(1)
        net_pane.set_value(1)
        sum_pane.set_value(1)
    end

    PushButton{parent=sum_c_2,x=1,y=14,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=nav_a_fg_bg}
---@diagnostic disable-next-line: undefined-field
    PushButton{parent=sum_c_2,x=44,y=14,min_width=6,text="Exit",callback=function()os.queueEvent("terminate")end,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    -- overwrite functions now that we have the elements

    function tool_ctl.set_networked(enable)
        tmp_cfg.Networked = enable
        if enable then u_id.set_max(4) else u_id.set_max(999) end
    end

    function tool_ctl.next_from_plc()
        if tmp_cfg.Networked then main_pane.set_value(3) else main_pane.set_value(4) end
    end

    function tool_ctl.back_from_log()
        if tmp_cfg.Networked then main_pane.set_value(3) else main_pane.set_value(2) end
    end

    function tool_ctl.gen_summary()
        setting_list.remove_all()

        local alternate = false
        local inner_width = setting_list.get_width() - 1

        for i = 1, #fields do
            local f = fields[i]
            local height = 1
            local label_w = string.len(f[1])
            local val_max_w = (inner_width - label_w) + 1
            local val = util.strval(tmp_cfg[f[2]])

            if f[3] and not tmp_cfg.Networked then val = "n/a" end
            if f[2] == "AuthKey" and hide_key.get_value() then val = string.rep("*", string.len(val)) end

            local c = util.trinary(alternate, cpair(colors.gray,colors.lightGray), cpair(colors.gray,colors.white))
            alternate = not alternate

            if (f[2] == "LogPath" or f[2] == "AuthKey") and string.len(val) > val_max_w then
                local lines = util.strwrap(val, inner_width)
                height = #lines + 1
            end

            local line = Div{parent=setting_list,height=height,fg_bg=c}
            TextBox{parent=line,text=f[1],width=string.len(f[1]),fg_bg=cpair(colors.black,line.get_fg_bg().bkg)}

            if height > 1 then
                TextBox{parent=line,x=1,y=2,text=val,height=height-1,alignment=LEFT}
            else
                TextBox{parent=line,x=label_w+1,y=1,text=val,alignment=RIGHT}
            end
        end
    end
end

function configurator.configure(need_config)
    log.debug("configurator started")

    tool_ctl.need_config = true

    -- reset terminal
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)

    -- set overridden colors
    for i = 1, #style.colors do
        term.setPaletteColor(style.colors[i].c, style.colors[i].hex)
    end

    -- init front panel view
    local display = DisplayBox{window=term.current(),fg_bg=style.root}
    _config_view(display)

    local function clear()
        display.delete()
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
    end

    while true do
        local event, param1, param2, param3 = util.pull_event()

        -- handle event
        if event == "timer" then
            -- notify timer callback dispatcher if no other timer case claimed this event
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

        -- check for termination request
        if event == "terminate" then
            clear()
            println("terminate requested, exiting config")
            return false
        end
    end
end

return configurator
