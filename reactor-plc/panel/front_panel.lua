--
-- Main SCADA Coordinator GUI
--

local util          = require("scada-common.util")

local style         = require("reactor-plc.panel.style")

local core          = require("graphics.core")

local DisplayBox    = require("graphics.elements.displaybox")
local Div           = require("graphics.elements.div")
local Rectangle     = require("graphics.elements.rectangle")
local TextBox       = require("graphics.elements.textbox")
local ColorMap      = require("graphics.elements.colormap")

local PushButton    = require("graphics.elements.controls.push_button")

local DataIndicator = require("graphics.elements.indicators.data")
local LED           = require("graphics.elements.indicators.led")
local LEDPair       = require("graphics.elements.indicators.ledpair")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border

-- create new main view
---@param monitor table main viewscreen
---@param fp_ps psil front panel PSIL
local function init(monitor, fp_ps)
    local panel = DisplayBox{window=monitor,fg_bg=style.root}

    local _ = TextBox{parent=panel,y=1,text="REACTOR PLC",alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    local system = Div{parent=panel,width=14,height=18,x=2,y=3}

    local init_ok = LED{parent=system,label="STATUS",colors=cpair(colors.green,colors.red)}
    local heartbeat = LED{parent=system,label="HEARTBEAT",colors=cpair(colors.green,colors.green_off)}
    system.line_break()

    fp_ps.subscribe("init_ok", init_ok.update)
    fp_ps.subscribe("heartbeat", heartbeat.update)

    local reactor = LEDPair{parent=system,label="REACTOR",off=colors.red,c1=colors.yellow,c2=colors.green}
    local modem = LED{parent=system,label="MODEM",colors=cpair(colors.green,colors.green_off)}
    local network = LEDPair{parent=system,label="NETWORK",off=colors.gray,c1=colors.yellow,c2=colors.green}
    system.line_break()

    fp_ps.subscribe("reactor_dev_state", reactor.update)
    fp_ps.subscribe("has_modem", modem.update)
    fp_ps.subscribe("link_state", network.update)

    local rt_main = LED{parent=system,label="RT MAIN",colors=cpair(colors.green,colors.green_off)}
    local rt_rps  = LED{parent=system,label="RT RPS",colors=cpair(colors.green,colors.green_off)}
    local rt_cmtx = LED{parent=system,label="RT COMMS TX",colors=cpair(colors.green,colors.green_off)}
    local rt_cmrx = LED{parent=system,label="RT COMMS RX",colors=cpair(colors.green,colors.green_off)}
    local rt_sctl = LED{parent=system,label="RT SPCTL",colors=cpair(colors.green,colors.green_off)}
    system.line_break()

    fp_ps.subscribe("routine__main", rt_main.update)
    fp_ps.subscribe("routine__rps", rt_rps.update)
    fp_ps.subscribe("routine__comms_tx", rt_cmtx.update)
    fp_ps.subscribe("routine__comms_rx", rt_cmrx.update)
    fp_ps.subscribe("routine__spctl", rt_sctl.update)

    local active = LED{parent=system,label="RCT ACTIVE",colors=cpair(colors.green,colors.green_off)}
    local scram = LED{parent=system,label="RPS TRIP",colors=cpair(colors.red,colors.red_off)}
    system.line_break()

    fp_ps.subscribe("reactor_active", active.update)
    fp_ps.subscribe("rps_scram", scram.update)

    local about = Rectangle{parent=panel,width=16,height=4,x=18,y=15,border=border(1,colors.white),thin=true,fg_bg=cpair(colors.black,colors.white)}
    local _ = TextBox{parent=about,text="FW: v1.0.0",alignment=TEXT_ALIGN.LEFT,height=1}
    local _ = TextBox{parent=about,text="NT: v1.4.0",alignment=TEXT_ALIGN.LEFT,height=1}
    -- about.line_break()
    -- local _ = TextBox{parent=about,text="SVTT: 10ms",alignment=TEXT_ALIGN.LEFT,height=1}

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

    fp_ps.subscribe("rps_manual", rps_man.update)
    fp_ps.subscribe("rps_automatic", rps_auto.update)
    fp_ps.subscribe("rps_timeout", rps_tmo.update)
    fp_ps.subscribe("rps_fault", rps_flt.update)
    fp_ps.subscribe("rps_sysfail", rps_fail.update)
    fp_ps.subscribe("rps_damage", rps_dmg.update)
    fp_ps.subscribe("rps_high_temp", rps_tmp.update)
    fp_ps.subscribe("rps_no_fuel", rps_nof.update)
    fp_ps.subscribe("rps_high_waste", rps_wst.update)
    fp_ps.subscribe("rps_low_ccool", rps_ccl.update)
    fp_ps.subscribe("rps_high_hcool", rps_hcl.update)

    ColorMap{parent=panel,x=1,y=19}
    -- facility.ps.subscribe("sv_ping", ping.update)

    return panel
end

return init
