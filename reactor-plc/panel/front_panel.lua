--
-- Main SCADA Coordinator GUI
--

local util          = require("scada-common.util")

local databus       = require("reactor-plc.databus")

local style         = require("reactor-plc.panel.style")

local core          = require("graphics.core")
local flasher       = require("graphics.flasher")

local DisplayBox    = require("graphics.elements.displaybox")
local Div           = require("graphics.elements.div")
local Rectangle     = require("graphics.elements.rectangle")
local TextBox       = require("graphics.elements.textbox")

local PushButton    = require("graphics.elements.controls.push_button")

local LED           = require("graphics.elements.indicators.led")
local LEDPair       = require("graphics.elements.indicators.ledpair")
local RGBLED        = require("graphics.elements.indicators.ledrgb")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border

-- create new main view
---@param monitor table main viewscreen
local function init(monitor)
    local panel = DisplayBox{window=monitor,fg_bg=style.root}

    local header = TextBox{parent=panel,y=1,text="REACTOR PLC - UNIT ?",alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}
    databus.rx_field("unit_id", function (id) header.set_value(util.c("REACTOR PLC - UNIT ", id)) end)

    local system = Div{parent=panel,width=14,height=18,x=2,y=3}

    local init_ok = LED{parent=system,label="STATUS",colors=cpair(colors.green,colors.red)}
    local heartbeat = LED{parent=system,label="HEARTBEAT",colors=cpair(colors.green,colors.green_off)}
    system.line_break()

    databus.rx_field("init_ok", init_ok.update)
    databus.rx_field("heartbeat", heartbeat.update)

    local reactor = LEDPair{parent=system,label="REACTOR",off=colors.red,c1=colors.yellow,c2=colors.green}
    local modem = LED{parent=system,label="MODEM",colors=cpair(colors.green,colors.green_off)}
    local network = RGBLED{parent=system,label="NETWORK",colors={colors.green,colors.red,colors.orange,colors.yellow,colors.gray}}
    network.update(5)
    system.line_break()

    databus.rx_field("reactor_dev_state", reactor.update)
    databus.rx_field("has_modem", modem.update)
    databus.rx_field("link_state", network.update)

    local rt_main = LED{parent=system,label="RT MAIN",colors=cpair(colors.green,colors.green_off)}
    local rt_rps  = LED{parent=system,label="RT RPS",colors=cpair(colors.green,colors.green_off)}
    local rt_cmtx = LED{parent=system,label="RT COMMS TX",colors=cpair(colors.green,colors.green_off)}
    local rt_cmrx = LED{parent=system,label="RT COMMS RX",colors=cpair(colors.green,colors.green_off)}
    local rt_sctl = LED{parent=system,label="RT SPCTL",colors=cpair(colors.green,colors.green_off)}
    system.line_break()

    databus.rx_field("routine__main", rt_main.update)
    databus.rx_field("routine__rps", rt_rps.update)
    databus.rx_field("routine__comms_tx", rt_cmtx.update)
    databus.rx_field("routine__comms_rx", rt_cmrx.update)
    databus.rx_field("routine__spctl", rt_sctl.update)

    local status = Div{parent=panel,width=19,height=18,x=17,y=3}

    local active = LED{parent=status,x=2,width=12,label="RCT ACTIVE",colors=cpair(colors.green,colors.green_off)}

    local status_trip_rct = Rectangle{parent=status,width=20,height=3,x=1,y=2,border=border(1,colors.lightGray,true),even_inner=true,fg_bg=cpair(colors.black,colors.ivory)}
    local status_trip = Div{parent=status_trip_rct,width=18,height=1,fg_bg=cpair(colors.black,colors.lightGray)}
    local scram = LED{parent=status_trip,width=10,label="RPS TRIP",colors=cpair(colors.red,colors.red_off),flash=true,period=flasher.PERIOD.BLINK_250_MS}

    local controls_rct = Rectangle{parent=status,width=17,height=3,x=1,y=5,border=border(1,colors.white,true),even_inner=true,fg_bg=cpair(colors.black,colors.ivory)}
    local controls = Div{parent=controls_rct,width=15,height=1,fg_bg=cpair(colors.black,colors.white)}
    PushButton{parent=controls,x=1,y=1,min_width=7,text="SCRAM",callback=databus.rps_scram,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.black,colors.red_off)}
    PushButton{parent=controls,x=9,y=1,min_width=7,text="RESET",callback=databus.rps_reset,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=cpair(colors.black,colors.yellow_off)}

    databus.rx_field("reactor_active", active.update)
    databus.rx_field("rps_scram", scram.update)

    local about   = Rectangle{parent=panel,width=32,height=3,x=2,y=16,border=border(1,colors.ivory),thin=true,fg_bg=cpair(colors.black,colors.white)}
    local fw_v    = TextBox{parent=about,x=2,y=1,text="FW: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}
    local comms_v = TextBox{parent=about,x=17,y=1,text="NT: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}

    databus.rx_field("version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    databus.rx_field("comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    local rps = Rectangle{parent=panel,width=16,height=16,x=36,y=3,border=border(1,colors.lightGray),thin=true,fg_bg=cpair(colors.black,colors.lightGray)}
    local rps_man  = LED{parent=rps,label="MANUAL",colors=cpair(colors.red,colors.red_off)}
    local rps_auto = LED{parent=rps,label="AUTOMATIC",colors=cpair(colors.red,colors.red_off)}
    local rps_tmo  = LED{parent=rps,label="TIMEOUT",colors=cpair(colors.red,colors.red_off)}
    local rps_flt  = LED{parent=rps,label="PLC FAULT",colors=cpair(colors.red,colors.red_off)}
    local rps_fail = LED{parent=rps,label="RCT FAULT",colors=cpair(colors.red,colors.red_off)}
    rps.line_break()
    local rps_dmg  = LED{parent=rps,label="HI DAMAGE",colors=cpair(colors.red,colors.red_off)}
    local rps_tmp  = LED{parent=rps,label="HI TEMP",colors=cpair(colors.red,colors.red_off)}
    rps.line_break()
    local rps_nof  = LED{parent=rps,label="LO FUEL",colors=cpair(colors.red,colors.red_off)}
    local rps_wst  = LED{parent=rps,label="HI WASTE",colors=cpair(colors.red,colors.red_off)}
    rps.line_break()
    local rps_ccl  = LED{parent=rps,label="LO CCOOLANT",colors=cpair(colors.red,colors.red_off)}
    local rps_hcl  = LED{parent=rps,label="HI HCOOLANT",colors=cpair(colors.red,colors.red_off)}

    databus.rx_field("rps_manual", rps_man.update)
    databus.rx_field("rps_automatic", rps_auto.update)
    databus.rx_field("rps_timeout", rps_tmo.update)
    databus.rx_field("rps_fault", rps_flt.update)
    databus.rx_field("rps_sysfail", rps_fail.update)
    databus.rx_field("rps_damage", rps_dmg.update)
    databus.rx_field("rps_high_temp", rps_tmp.update)
    databus.rx_field("rps_no_fuel", rps_nof.update)
    databus.rx_field("rps_high_waste", rps_wst.update)
    databus.rx_field("rps_low_ccool", rps_ccl.update)
    databus.rx_field("rps_high_hcool", rps_hcl.update)

    return panel
end

return init
