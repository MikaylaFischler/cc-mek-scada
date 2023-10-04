--
-- Reactor PLC Front Panel GUI
--

local types      = require("scada-common.types")
local util       = require("scada-common.util")

local databus    = require("reactor-plc.databus")
local plc        = require("reactor-plc.plc")

local style      = require("reactor-plc.panel.style")

local core       = require("graphics.core")
local flasher    = require("graphics.flasher")

local Div        = require("graphics.elements.div")
local Rectangle  = require("graphics.elements.rectangle")
local TextBox    = require("graphics.elements.textbox")

local PushButton = require("graphics.elements.controls.push_button")

local LED        = require("graphics.elements.indicators.led")
local LEDPair    = require("graphics.elements.indicators.ledpair")
local RGBLED     = require("graphics.elements.indicators.ledrgb")

local ALIGN = core.ALIGN

local cpair = core.cpair
local border = core.border

local ind_grn = style.ind_grn
local ind_red = style.ind_red

-- create new front panel view
---@param panel graphics_element main displaybox
local function init(panel)
    local header = TextBox{parent=panel,y=1,text="REACTOR PLC - UNIT ?",alignment=ALIGN.CENTER,height=1,fg_bg=style.header}
    header.register(databus.ps, "unit_id", function (id) header.set_value(util.c("REACTOR PLC - UNIT ", id)) end)

    --
    -- system indicators
    --

    local system = Div{parent=panel,width=14,height=18,x=2,y=3}

    local init_ok = LED{parent=system,label="STATUS",colors=cpair(colors.green,colors.red)}
    local heartbeat = LED{parent=system,label="HEARTBEAT",colors=ind_grn}
    system.line_break()

    init_ok.register(databus.ps, "init_ok", init_ok.update)
    heartbeat.register(databus.ps, "heartbeat", heartbeat.update)

    local reactor = LEDPair{parent=system,label="REACTOR",off=colors.red,c1=colors.yellow,c2=colors.green}
    local modem = LED{parent=system,label="MODEM",colors=ind_grn}
    local network = RGBLED{parent=system,label="NETWORK",colors={colors.green,colors.red,colors.orange,colors.yellow,colors.gray}}
    network.update(types.PANEL_LINK_STATE.DISCONNECTED)
    system.line_break()

    reactor.register(databus.ps, "reactor_dev_state", reactor.update)
    modem.register(databus.ps, "has_modem", modem.update)
    network.register(databus.ps, "link_state", network.update)

    local rt_main = LED{parent=system,label="RT MAIN",colors=ind_grn}
    local rt_rps  = LED{parent=system,label="RT RPS",colors=ind_grn}
    local rt_cmtx = LED{parent=system,label="RT COMMS TX",colors=ind_grn}
    local rt_cmrx = LED{parent=system,label="RT COMMS RX",colors=ind_grn}
    local rt_sctl = LED{parent=system,label="RT SPCTL",colors=ind_grn}
    system.line_break()

    rt_main.register(databus.ps, "routine__main", rt_main.update)
    rt_rps.register(databus.ps, "routine__rps", rt_rps.update)
    rt_cmtx.register(databus.ps, "routine__comms_tx", rt_cmtx.update)
    rt_cmrx.register(databus.ps, "routine__comms_rx", rt_cmrx.update)
    rt_sctl.register(databus.ps, "routine__spctl", rt_sctl.update)

---@diagnostic disable-next-line: undefined-field
    local comp_id = util.sprintf("(%d)", os.getComputerID())
    TextBox{parent=system,x=9,y=5,width=6,height=1,text=comp_id,fg_bg=cpair(colors.lightGray,colors.ivory)}

    --
    -- status & controls
    --

    local status = Div{parent=panel,width=19,height=18,x=17,y=3}

    local active = LED{parent=status,x=2,width=12,label="RCT ACTIVE",colors=ind_grn}

    -- only show emergency coolant LED if emergency coolant is configured for this device
    if plc.config.EmerCoolEnable then
        local emer_cool = LED{parent=status,x=2,width=14,label="EMER COOLANT",colors=cpair(colors.yellow,colors.yellow_off)}
        emer_cool.register(databus.ps, "emer_cool", emer_cool.update)
    end

    local status_trip_rct = Rectangle{parent=status,width=20,height=3,x=1,border=border(1,colors.lightGray,true),even_inner=true,fg_bg=cpair(colors.black,colors.ivory)}
    local status_trip = Div{parent=status_trip_rct,width=18,height=1,fg_bg=cpair(colors.black,colors.lightGray)}
    local scram = LED{parent=status_trip,width=10,label="RPS TRIP",colors=ind_red,flash=true,period=flasher.PERIOD.BLINK_250_MS}

    local controls_rct = Rectangle{parent=status,width=17,height=3,x=1,border=border(1,colors.white,true),even_inner=true,fg_bg=cpair(colors.black,colors.ivory)}
    local controls = Div{parent=controls_rct,width=15,height=1,fg_bg=cpair(colors.black,colors.white)}
    PushButton{parent=controls,x=1,y=1,min_width=7,text="SCRAM",callback=databus.rps_scram,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.black,colors.red_off)}
    PushButton{parent=controls,x=9,y=1,min_width=7,text="RESET",callback=databus.rps_reset,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=cpair(colors.black,colors.yellow_off)}

    active.register(databus.ps, "reactor_active", active.update)
    scram.register(databus.ps, "rps_scram", scram.update)

    --
    -- about footer
    --

    local about   = Rectangle{parent=panel,width=32,height=3,x=2,y=16,border=border(1,colors.ivory),thin=true,fg_bg=cpair(colors.black,colors.white)}
    local fw_v    = TextBox{parent=about,x=2,y=1,text="FW: v00.00.00",alignment=ALIGN.LEFT,height=1}
    local comms_v = TextBox{parent=about,x=17,y=1,text="NT: v00.00.00",alignment=ALIGN.LEFT,height=1}

    fw_v.register(databus.ps, "version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    comms_v.register(databus.ps, "comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    --
    -- rps list
    --

    local rps = Rectangle{parent=panel,width=16,height=16,x=36,y=3,border=border(1,colors.lightGray),thin=true,fg_bg=cpair(colors.black,colors.lightGray)}
    local rps_man  = LED{parent=rps,label="MANUAL",colors=ind_red}
    local rps_auto = LED{parent=rps,label="AUTOMATIC",colors=ind_red}
    local rps_tmo  = LED{parent=rps,label="TIMEOUT",colors=ind_red}
    local rps_flt  = LED{parent=rps,label="PLC FAULT",colors=ind_red}
    local rps_fail = LED{parent=rps,label="RCT FAULT",colors=ind_red}
    rps.line_break()
    local rps_dmg  = LED{parent=rps,label="HI DAMAGE",colors=ind_red}
    local rps_tmp  = LED{parent=rps,label="HI TEMP",colors=ind_red}
    rps.line_break()
    local rps_nof  = LED{parent=rps,label="LO FUEL",colors=ind_red}
    local rps_wst  = LED{parent=rps,label="HI WASTE",colors=ind_red}
    rps.line_break()
    local rps_ccl  = LED{parent=rps,label="LO CCOOLANT",colors=ind_red}
    local rps_hcl  = LED{parent=rps,label="HI HCOOLANT",colors=ind_red}

    rps_man.register(databus.ps, "rps_manual", rps_man.update)
    rps_auto.register(databus.ps, "rps_automatic", rps_auto.update)
    rps_tmo.register(databus.ps, "rps_timeout", rps_tmo.update)
    rps_flt.register(databus.ps, "rps_fault", rps_flt.update)
    rps_fail.register(databus.ps, "rps_sysfail", rps_fail.update)
    rps_dmg.register(databus.ps, "rps_damage", rps_dmg.update)
    rps_tmp.register(databus.ps, "rps_high_temp", rps_tmp.update)
    rps_nof.register(databus.ps, "rps_no_fuel", rps_nof.update)
    rps_wst.register(databus.ps, "rps_high_waste", rps_wst.update)
    rps_ccl.register(databus.ps, "rps_low_ccool", rps_ccl.update)
    rps_hcl.register(databus.ps, "rps_high_hcool", rps_hcl.update)
end

return init
