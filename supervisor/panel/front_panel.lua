--
-- Main SCADA Coordinator GUI
--

local util       = require("scada-common.util")

local databus    = require("supervisor.databus")

local style      = require("supervisor.panel.style")

local core       = require("graphics.core")

local Div        = require("graphics.elements.div")
local MultiPane  = require("graphics.elements.multipane")
local Rectangle  = require("graphics.elements.rectangle")
local TextBox    = require("graphics.elements.textbox")

local PushButton = require("graphics.elements.controls.push_button")
local TabBar     = require("graphics.elements.controls.tabbar")

local LED        = require("graphics.elements.indicators.led")
local LEDPair    = require("graphics.elements.indicators.ledpair")
local RGBLED     = require("graphics.elements.indicators.ledrgb")

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

    databus.rx_field("heartbeat", heartbeat.update)

    local modem = LED{parent=system,label="MODEM",colors=cpair(colors.green,colors.green_off)}
    system.line_break()

    databus.rx_field("has_modem", modem.update)

    --  
    -- about footer
    --

    local about   = Div{parent=main_page,width=15,height=3,x=1,y=16,fg_bg=cpair(colors.lightGray,colors.ivory)}
    local fw_v    = TextBox{parent=about,x=1,y=1,text="FW: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}
    local comms_v = TextBox{parent=about,x=1,y=2,text="NT: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}

    databus.rx_field("version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    databus.rx_field("comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    --
    -- page handling
    --

    local plc_list = Div{parent=page_div,x=1,y=1}

    TextBox{parent=plc_list,x=2,y=2,text="v1.1.17 - PLC - UNIT 4 - :15004",alignment=TEXT_ALIGN.LEFT,height=1}

    local panes = { main_page, plc_list, main_page, main_page, main_page }

    local page_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}

    local tabs = {
        { name = "Main", color = cpair(colors.black, colors.ivory) },
        { name = "PLCs", color = cpair(colors.black, colors.ivory) },
        { name = "RTUs", color = cpair(colors.black, colors.ivory) },
        { name = "CRDs", color = cpair(colors.black, colors.ivory) },
        { name = "PKTs", color = cpair(colors.black, colors.ivory) },
    }

    TabBar{parent=panel,y=2,tabs=tabs,min_width=10,callback=page_pane.set_value,fg_bg=cpair(colors.black,colors.white)}
end

return init
