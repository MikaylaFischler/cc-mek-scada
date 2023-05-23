--
-- Main SCADA Coordinator GUI
--

local util          = require("scada-common.util")

local config        = require("supervisor.config")
local databus       = require("supervisor.databus")

local style         = require("supervisor.panel.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.div")
local ListBox       = require("graphics.elements.listbox")
local MultiPane     = require("graphics.elements.multipane")
local Rectangle     = require("graphics.elements.rectangle")
local TextBox       = require("graphics.elements.textbox")

local PushButton    = require("graphics.elements.controls.push_button")
local TabBar        = require("graphics.elements.controls.tabbar")

local LED           = require("graphics.elements.indicators.led")
local LEDPair       = require("graphics.elements.indicators.ledpair")
local RGBLED        = require("graphics.elements.indicators.ledrgb")
local DataIndicator = require("graphics.elements.indicators.data")

local TEXT_ALIGN = core.TEXT_ALIGN

local cpair = core.cpair
local border = core.border

-- create new main view
---@param panel graphics_element main displaybox
local function init(panel)
    TextBox{parent=panel,y=1,text="SCADA SUPERVISOR",alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    local page_div = Div{parent=panel,x=1,y=3}

    --
    -- system indicators
    --

    local main_page = Div{parent=page_div,x=1,y=1}

    local system = Div{parent=main_page,width=14,height=17,x=2,y=2}

    local on = LED{parent=system,label="POWER",colors=cpair(colors.green,colors.red)}
    local heartbeat = LED{parent=system,label="HEARTBEAT",colors=cpair(colors.green,colors.green_off)}
    on.update(true)
    system.line_break()

    heartbeat.register(databus.ps, "heartbeat", heartbeat.update)

    local modem = LED{parent=system,label="MODEM",colors=cpair(colors.green,colors.green_off)}
    system.line_break()

    modem.register(databus.ps, "has_modem", modem.update)

    --  
    -- about footer
    --

    local about   = Div{parent=main_page,width=15,height=3,x=1,y=16,fg_bg=cpair(colors.lightGray,colors.ivory)}
    local fw_v    = TextBox{parent=about,x=1,y=1,text="FW: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}
    local comms_v = TextBox{parent=about,x=1,y=2,text="NT: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}

    fw_v.register(databus.ps, "version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    comms_v.register(databus.ps, "comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    --
    -- page handling
    --

    -- plc page

    local plc_page = Div{parent=page_div,x=1,y=1}
    local plc_list = Div{parent=plc_page,x=2,y=2,width=49}

    for i = 1, config.NUM_REACTORS do
        local ps_prefix = "plc_" .. i .. "_"
        local plc_entry = Div{parent=plc_list,height=3,fg_bg=cpair(colors.black,colors.white)}

        TextBox{parent=plc_entry,x=1,y=1,text="",width=8,height=1,fg_bg=cpair(colors.black,colors.lightGray)}
        TextBox{parent=plc_entry,x=1,y=2,text="UNIT "..i,alignment=TEXT_ALIGN.CENTER,width=8,height=1,fg_bg=cpair(colors.black,colors.lightGray)}
        TextBox{parent=plc_entry,x=1,y=3,text="",width=8,height=1,fg_bg=cpair(colors.black,colors.lightGray)}

        local conn = LED{parent=plc_entry,x=10,y=2,label="CONN",colors=cpair(colors.green,colors.green_off)}
        conn.register(databus.ps, ps_prefix .. "conn", conn.update)

        local plc_chan = TextBox{parent=plc_entry,x=17,y=2,text=" --- ",width=5,height=1,fg_bg=cpair(colors.gray,colors.white)}
        plc_chan.register(databus.ps, ps_prefix .. "chan", plc_chan.set_value)

        TextBox{parent=plc_entry,x=23,y=2,text="FW:",width=3,height=1}
        local plc_fw_v = TextBox{parent=plc_entry,x=27,y=2,text=" ------- ",width=9,height=1,fg_bg=cpair(colors.lightGray,colors.white)}
        plc_fw_v.register(databus.ps, ps_prefix .. "fw", plc_fw_v.set_value)

        TextBox{parent=plc_entry,x=37,y=2,text="RTT:",width=4,height=1}
        local plc_rtt = DataIndicator{parent=plc_entry,x=42,y=2,label="",unit="",format="%4d",value=0,width=4,fg_bg=cpair(colors.lightGray,colors.white)}
        TextBox{parent=plc_entry,x=47,y=2,text="ms",width=4,height=1,fg_bg=cpair(colors.lightGray,colors.white)}
        plc_rtt.register(databus.ps, ps_prefix .. "rtt", plc_rtt.update)
        plc_rtt.register(databus.ps, ps_prefix .. "rtt_color", plc_rtt.recolor)

        plc_list.line_break()
    end

    -- rtu page

    local rtu_page = Div{parent=page_div,x=1,y=1}
    local rtu_list = Div{parent=rtu_page,x=2,y=2,width=49}

    -- coordinator page

    local crd_page = Div{parent=page_div,x=1,y=1}
    local crd_box = Div{parent=crd_page,x=2,y=2,width=49,height=4,fg_bg=cpair(colors.black,colors.white)}

    local crd_conn = LED{parent=crd_box,x=2,y=2,label="CONNECTION",colors=cpair(colors.green,colors.green_off)}
    crd_conn.register(databus.ps, "crd_conn", crd_conn.update)

    TextBox{parent=crd_box,x=4,y=3,text="CHANNEL ",width=8,height=1,fg_bg=cpair(colors.gray,colors.white)}
    local crd_chan = TextBox{parent=crd_box,x=12,y=3,text="---",width=5,height=1,fg_bg=cpair(colors.gray,colors.white)}
    crd_chan.register(databus.ps, "crd_chan", crd_chan.set_value)

    TextBox{parent=crd_box,x=22,y=2,text="FW:",width=3,height=1}
    local crd_fw_v = TextBox{parent=crd_box,x=26,y=2,text=" ------- ",width=9,height=1,fg_bg=cpair(colors.lightGray,colors.white)}
    crd_fw_v.register(databus.ps, "crd_fw", crd_fw_v.set_value)

    TextBox{parent=crd_box,x=36,y=2,text="RTT:",width=4,height=1}
    local crd_rtt = DataIndicator{parent=crd_box,x=41,y=2,label="",unit="",format="%5d",value=0,width=5,fg_bg=cpair(colors.lightGray,colors.white)}
    TextBox{parent=crd_box,x=47,y=2,text="ms",width=4,height=1,fg_bg=cpair(colors.lightGray,colors.white)}
    crd_rtt.register(databus.ps, "crd_rtt", crd_rtt.update)
    crd_rtt.register(databus.ps, "crd_rtt_color", crd_rtt.recolor)

    -- pocket page

    local pkt_page = Div{parent=page_div,x=1,y=1}
    local pkt_box = Div{parent=pkt_page,x=2,y=2,width=49}

    local panes = { main_page, plc_page, rtu_page, crd_page, pkt_page }

    local page_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}

    local tabs = {
        { name = "SVR", color = cpair(colors.black, colors.ivory) },
        { name = "PLC", color = cpair(colors.black, colors.ivory) },
        { name = "RTU", color = cpair(colors.black, colors.ivory) },
        { name = "CRD", color = cpair(colors.black, colors.ivory) },
        { name = "PKT", color = cpair(colors.black, colors.ivory) },
    }

    TabBar{parent=panel,y=2,tabs=tabs,min_width=9,callback=page_pane.set_value,fg_bg=cpair(colors.black,colors.white)}
end

return init
