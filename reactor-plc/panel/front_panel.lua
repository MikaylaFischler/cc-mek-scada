--
-- Main SCADA Coordinator GUI
--

local util          = require("scada-common.util")

local style         = require("reactor-plc.panel.style")

local core          = require("graphics.core")

local DisplayBox    = require("graphics.elements.displaybox")
local Div           = require("graphics.elements.div")
local Rectangle           = require("graphics.elements.rectangle")
local TextBox       = require("graphics.elements.textbox")
local ColorMap       = require("graphics.elements.colormap")

local PushButton    = require("graphics.elements.controls.push_button")
local SwitchButton  = require("graphics.elements.controls.switch_button")

local DataIndicator = require("graphics.elements.indicators.data")
local LED           = require("graphics.elements.indicators.led")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border

-- create new main view
---@param monitor table main viewscreen
local function init(monitor)
    local panel = DisplayBox{window=monitor,fg_bg=style.root}

    -- window header message
    local header = TextBox{parent=panel,y=1,text="REACTOR PLC",alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    local system = Div{parent=panel,width=14,height=18,x=2,y=3}

    local init_ok = LED{parent=system,label="STATUS",colors=cpair(colors.green,colors.red)}
    local heartbeat = LED{parent=system,label="HEARTBEAT",colors=cpair(colors.green,colors.green_off)}
    system.line_break()
    local reactor = LED{parent=system,label="REACTOR",colors=cpair(colors.green,colors.red)}
    local modem = LED{parent=system,label="MODEM",colors=cpair(colors.green,colors.gray)}
    local network = LED{parent=system,label="NETWORK",colors=cpair(colors.green,colors.gray)}
    system.line_break()
    local _ = LED{parent=system,label="RT MAIN",colors=cpair(colors.green,colors.gray)}
    local _ = LED{parent=system,label="RT RPS",colors=cpair(colors.green,colors.gray)}
    local _ = LED{parent=system,label="RT COMMS TX",colors=cpair(colors.green,colors.gray)}
    local _ = LED{parent=system,label="RT COMMS RX",colors=cpair(colors.green,colors.gray)}
    local _ = LED{parent=system,label="RT SPCTL",colors=cpair(colors.green,colors.gray)}
    system.line_break()
    local active = LED{parent=system,label="RCT ACTIVE",colors=cpair(colors.green,colors.green_off)}
    local scram = LED{parent=system,label="RPS TRIP",colors=cpair(colors.red,colors.red_off)}
    system.line_break()

    local about = Rectangle{parent=panel,width=16,height=4,x=18,y=15,border=border(1,colors.white),thin=true,fg_bg=cpair(colors.black,colors.white)}
    local _ = TextBox{parent=about,text="FW: v1.0.0",alignment=TEXT_ALIGN.LEFT,height=1}
    local _ = TextBox{parent=about,text="NT: v1.4.0",alignment=TEXT_ALIGN.LEFT,height=1}
    -- about.line_break()
    -- local _ = TextBox{parent=about,text="SVTT: 10ms",alignment=TEXT_ALIGN.LEFT,height=1}

    local rps = Rectangle{parent=panel,width=16,height=16,x=36,y=3,border=border(1,colors.lightGray),thin=true,fg_bg=cpair(colors.black,colors.lightGray)}
    local _ = LED{parent=rps,label="MANUAL",colors=cpair(colors.red,colors.red_off)}
    local _ = LED{parent=rps,label="AUTOMATIC",colors=cpair(colors.red,colors.red_off)}
    local _ = LED{parent=rps,label="TIMEOUT",colors=cpair(colors.red,colors.red_off)}
    local _ = LED{parent=rps,label="PLC FAULT",colors=cpair(colors.red,colors.red_off)}
    local _ = LED{parent=rps,label="RCT FAULT",colors=cpair(colors.red,colors.red_off)}
    rps.line_break()
    local _ = LED{parent=rps,label="HI DAMAGE",colors=cpair(colors.red,colors.red_off)}
    local _ = LED{parent=rps,label="HI TEMP",colors=cpair(colors.red,colors.red_off)}
    rps.line_break()
    local _ = LED{parent=rps,label="LO FUEL",colors=cpair(colors.red,colors.red_off)}
    local _ = LED{parent=rps,label="HI WASTE",colors=cpair(colors.red,colors.red_off)}
    rps.line_break()
    local _ = LED{parent=rps,label="LO CCOOLANT",colors=cpair(colors.red,colors.red_off)}
    local _ = LED{parent=rps,label="HI HCOOLANT",colors=cpair(colors.red,colors.red_off)}


    ColorMap{parent=panel,x=1,y=19}
    -- facility.ps.subscribe("sv_ping", ping.update)
    -- facility.ps.subscribe("date_time", datetime.set_value)

    return panel
end

return init
