--
-- Coordinator Front Panel GUI
--

local types     = require("scada-common.types")
local util      = require("scada-common.util")

local iocontrol = require("coordinator.iocontrol")

local pgi       = require("coordinator.ui.pgi")
local style     = require("coordinator.ui.style")

local pkt_entry = require("coordinator.ui.components.pkt_entry")

local core      = require("graphics.core")

local Div       = require("graphics.elements.Div")
local ListBox   = require("graphics.elements.ListBox")
local MultiPane = require("graphics.elements.MultiPane")
local TextBox   = require("graphics.elements.TextBox")

local TabBar    = require("graphics.elements.controls.TabBar")

local LED       = require("graphics.elements.indicators.LED")
local LEDPair   = require("graphics.elements.indicators.LEDPair")
local RGBLED    = require("graphics.elements.indicators.RGBLED")

local LINK_STATE = types.PANEL_LINK_STATE

local ALIGN = core.ALIGN

local cpair = core.cpair

local led_grn = style.led_grn

-- create new front panel view
---@param panel DisplayBox main displaybox
---@param num_units integer number of units (number of unit monitors)
local function init(panel, num_units)
    local ps = iocontrol.get_db().fp.ps

    local term_w, term_h = term.getSize()

    TextBox{parent=panel,y=1,text="SCADA COORDINATOR",alignment=ALIGN.CENTER,fg_bg=style.fp_theme.header}

    local page_div = Div{parent=panel,x=1,y=3}

    --
    -- system indicators
    --

    local main_page = Div{parent=page_div,x=1,y=1}

    local system = Div{parent=main_page,width=14,height=17,x=2,y=2}

    local status = LED{parent=system,label="STATUS",colors=cpair(colors.green,colors.red)}
    local heartbeat = LED{parent=system,label="HEARTBEAT",colors=led_grn}
    status.update(true)
    system.line_break()

    heartbeat.register(ps, "heartbeat", heartbeat.update)

    local modem = LED{parent=system,label="MODEM",colors=led_grn}

    if not style.colorblind then
        local network = RGBLED{parent=system,label="NETWORK",colors={colors.green,colors.red,colors.yellow,colors.orange,style.fp_ind_bkg}}
        network.update(types.PANEL_LINK_STATE.DISCONNECTED)
        network.register(ps, "link_state", network.update)
    else
        local nt_lnk = LEDPair{parent=system,label="NT LINKED",off=style.fp_ind_bkg,c1=colors.red,c2=colors.green}
        local nt_ver = LEDPair{parent=system,label="NT VERSION",off=style.fp_ind_bkg,c1=colors.red,c2=colors.green}

        nt_lnk.register(ps, "link_state", function (state)
            local value = 2

            if state == LINK_STATE.DISCONNECTED then
                value = 1
            elseif state == LINK_STATE.LINKED then
                value = 3
            end

            nt_lnk.update(value)
        end)

        nt_ver.register(ps, "link_state", function (state)
            local value = 3

            if state == LINK_STATE.BAD_VERSION then
                value = 2
            elseif state == LINK_STATE.DISCONNECTED then
                value = 1
            end

            nt_ver.update(value)
        end)
    end

    system.line_break()

    modem.register(ps, "has_modem", modem.update)

    local speaker = LED{parent=system,label="SPEAKER",colors=led_grn}
    speaker.register(ps, "has_speaker", speaker.update)

    system.line_break()

    local rt_main = LED{parent=system,label="RT MAIN",colors=led_grn}
    local rt_render = LED{parent=system,label="RT RENDER",colors=led_grn}

    rt_main.register(ps, "routine__main", rt_main.update)
    rt_render.register(ps, "routine__render", rt_render.update)

---@diagnostic disable-next-line: undefined-field
    local comp_id = util.sprintf("(%d)", os.getComputerID())
    TextBox{parent=system,x=9,y=4,width=6,text=comp_id,fg_bg=style.fp.disabled_fg}

    local monitors = Div{parent=main_page,width=16,height=17,x=18,y=2}

    local main_monitor = LED{parent=monitors,label="MAIN MONITOR",colors=led_grn}
    main_monitor.register(ps, "main_monitor", main_monitor.update)

    local flow_monitor = LED{parent=monitors,label="FLOW MONITOR",colors=led_grn}
    flow_monitor.register(ps, "flow_monitor", flow_monitor.update)

    monitors.line_break()

    for i = 1, num_units do
        local unit_monitor = LED{parent=monitors,label="UNIT "..i.." MONITOR",colors=led_grn}
        unit_monitor.register(ps, "unit_monitor_" .. i, unit_monitor.update)
    end

    --
    -- about footer
    --

    local about   = Div{parent=main_page,width=15,height=2,y=term_h-3,fg_bg=style.fp.disabled_fg}
    local fw_v    = TextBox{parent=about,text="FW: v00.00.00"}
    local comms_v = TextBox{parent=about,text="NT: v00.00.00"}

    fw_v.register(ps, "version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    comms_v.register(ps, "comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    --
    -- page handling
    --

    -- API page

    local api_page = Div{parent=page_div,x=1,y=1,hidden=true}
    local api_list = ListBox{parent=api_page,y=1,height=term_h-2,width=term_w,scroll_height=1000,fg_bg=style.fp.text_fg,nav_fg_bg=cpair(colors.gray,colors.lightGray),nav_active=cpair(colors.black,colors.gray)}
    local _ = Div{parent=api_list,height=1} -- padding

    -- assemble page panes

    local panes = { main_page, api_page }

    local page_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}

    local tabs = {
        { name = "CRD", color = style.fp.text },
        { name = "API", color = style.fp.text },
    }

    TabBar{parent=panel,y=2,tabs=tabs,min_width=9,callback=page_pane.set_value,fg_bg=style.fp_theme.highlight_box_bright}

    -- link pocket API list management to PGI
    pgi.link_elements(api_list, pkt_entry)
end

return init
