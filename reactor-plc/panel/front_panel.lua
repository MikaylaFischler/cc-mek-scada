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

local Div        = require("graphics.elements.Div")
local Rectangle  = require("graphics.elements.Rectangle")
local TextBox    = require("graphics.elements.TextBox")

local PushButton = require("graphics.elements.controls.PushButton")

local LED        = require("graphics.elements.indicators.LED")
local LEDPair    = require("graphics.elements.indicators.LEDPair")
local RGBLED     = require("graphics.elements.indicators.RGBLED")

local LINK_STATE = types.PANEL_LINK_STATE

local ALIGN = core.ALIGN

local cpair = core.cpair
local border = core.border

local ind_grn = style.ind_grn
local ind_red = style.ind_red

-- create new front panel view
---@param panel DisplayBox main displaybox
local function init(panel)
    local s_hi_box = style.theme.highlight_box

    local disabled_fg = style.fp.disabled_fg

    local term_w, term_h = term.getSize()

    local header = TextBox{parent=panel,y=1,text="FISSION REACTOR PLC - UNIT ?",alignment=ALIGN.CENTER,fg_bg=style.theme.header}
    header.register(databus.ps, "unit_id", function (id) header.set_value(util.c("FISSION REACTOR PLC - UNIT ", id)) end)

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

    if not style.colorblind then
        local network = RGBLED{parent=system,label="NETWORK",colors={colors.green,colors.red,colors.yellow,colors.orange,style.ind_bkg}}
        network.update(types.PANEL_LINK_STATE.DISCONNECTED)
        network.register(databus.ps, "link_state", network.update)
    else
        local nt_lnk = LEDPair{parent=system,label="NT LINKED",off=style.ind_bkg,c1=colors.red,c2=colors.green}
        local nt_ver = LEDPair{parent=system,label="NT VERSION",off=style.ind_bkg,c1=colors.red,c2=colors.green}
        local nt_col = LED{parent=system,label="NT COLLISION",colors=ind_red}

        nt_lnk.register(databus.ps, "link_state", function (state)
            local value = 2

            if state == LINK_STATE.DISCONNECTED then
                value = 1
            elseif state == LINK_STATE.LINKED then
                value = 3
            end

            nt_lnk.update(value)
        end)

        nt_ver.register(databus.ps, "link_state", function (state)
            local value = 3

            if state == LINK_STATE.BAD_VERSION then
                value = 2
            elseif state == LINK_STATE.DISCONNECTED then
                value = 1
            end

            nt_ver.update(value)
        end)

        nt_col.register(databus.ps, "link_state", function (state) nt_col.update(state == LINK_STATE.COLLISION) end)
    end

    system.line_break()

    reactor.register(databus.ps, "reactor_dev_state", reactor.update)
    modem.register(databus.ps, "has_modem", modem.update)

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
    TextBox{parent=system,x=9,y=5,width=6,text=comp_id,fg_bg=disabled_fg}

    --
    -- status & controls
    --

    local status = Div{parent=panel,width=term_w-32,height=18,x=17,y=3}

    local active = LED{parent=status,x=2,width=12,label="RCT ACTIVE",colors=ind_grn}

    -- only show emergency coolant LED if emergency coolant is configured for this device
    if plc.config.EmerCoolEnable then
        local emer_cool = LED{parent=status,x=2,width=14,label="EMER COOLANT",colors=cpair(colors.yellow,colors.yellow_off)}
        emer_cool.register(databus.ps, "emer_cool", emer_cool.update)
    end

    local status_trip_rct = Rectangle{parent=status,height=3,x=1,border=border(1,s_hi_box.bkg,true),even_inner=true}
    local status_trip = Div{parent=status_trip_rct,height=1,fg_bg=s_hi_box}
    local scram = LED{parent=status_trip,width=10,label="RPS TRIP",colors=ind_red,flash=true,period=flasher.PERIOD.BLINK_250_MS}

    local controls_rct = Rectangle{parent=status,width=status.get_width()-2,height=3,x=1,border=border(1,s_hi_box.bkg,true),even_inner=true}
    local controls = Div{parent=controls_rct,width=controls_rct.get_width()-2,height=1,fg_bg=s_hi_box}
    local button_padding = math.floor((controls.get_width() - 14) / 3)
    PushButton{parent=controls,x=button_padding+1,y=1,min_width=7,text="SCRAM",callback=databus.rps_scram,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.black,colors.red_off)}
    PushButton{parent=controls,x=(2*button_padding)+9,y=1,min_width=7,text="RESET",callback=databus.rps_reset,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=cpair(colors.black,colors.yellow_off)}

    active.register(databus.ps, "reactor_active", active.update)
    scram.register(databus.ps, "rps_scram", scram.update)

    --
    -- about footer
    --

    local about   = Div{parent=panel,width=15,height=2,y=term_h-1,fg_bg=disabled_fg}
    local fw_v    = TextBox{parent=about,text="FW: v00.00.00"}
    local comms_v = TextBox{parent=about,text="NT: v00.00.00"}

    fw_v.register(databus.ps, "version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    comms_v.register(databus.ps, "comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    --
    -- rps list
    --

    local rps = Rectangle{parent=panel,width=16,height=16,x=term_w-15,y=3,border=border(1,s_hi_box.bkg),thin=true,fg_bg=s_hi_box}
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
