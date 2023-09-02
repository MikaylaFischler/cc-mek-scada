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

local Div       = require("graphics.elements.div")
local ListBox   = require("graphics.elements.listbox")
local MultiPane = require("graphics.elements.multipane")
local TextBox   = require("graphics.elements.textbox")

local TabBar    = require("graphics.elements.controls.tabbar")

local LED       = require("graphics.elements.indicators.led")
local RGBLED    = require("graphics.elements.indicators.ledrgb")

local TEXT_ALIGN = core.TEXT_ALIGN

local cpair = core.cpair

local led_grn = style.led_grn

-- create new front panel view
---@param panel graphics_element main displaybox
---@param num_units integer number of units (number of unit monitors)
local function init(panel, num_units)
    local ps = iocontrol.get_db().fp.ps

    TextBox{parent=panel,y=1,text="SCADA COORDINATOR",alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.fp.header}

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
    local network = RGBLED{parent=system,label="NETWORK",colors={colors.green,colors.red,colors.orange,colors.yellow,colors.gray}}
    network.update(types.PANEL_LINK_STATE.DISCONNECTED)
    system.line_break()

    modem.register(ps, "has_modem", modem.update)
    network.register(ps, "link_state", network.update)

    local speaker = LED{parent=system,label="SPEAKER",colors=led_grn}
    speaker.register(ps, "has_speaker", speaker.update)

---@diagnostic disable-next-line: undefined-field
    local comp_id = util.sprintf("(%d)", os.getComputerID())
    TextBox{parent=system,x=9,y=4,width=6,height=1,text=comp_id,fg_bg=style.fp_label}

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

    local about   = Div{parent=main_page,width=15,height=3,x=1,y=16,fg_bg=style.fp_label}
    local fw_v    = TextBox{parent=about,x=1,y=1,text="FW: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}
    local comms_v = TextBox{parent=about,x=1,y=2,text="NT: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}

    fw_v.register(ps, "version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    comms_v.register(ps, "comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    --
    -- page handling
    --

    -- API page

    local api_page = Div{parent=page_div,x=1,y=1,hidden=true}
    local api_list = ListBox{parent=api_page,x=1,y=1,height=17,width=51,scroll_height=1000,fg_bg=style.fp_text,nav_fg_bg=cpair(colors.gray,colors.lightGray),nav_active=cpair(colors.black,colors.gray)}
    local _ = Div{parent=api_list,height=1,hidden=true} -- padding

    -- assemble page panes

    local panes = { main_page, api_page }

    local page_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}

    local tabs = {
        { name = "CRD", color = style.fp_text },
        { name = "API", color = style.fp_text },
    }

    TabBar{parent=panel,y=2,tabs=tabs,min_width=9,callback=page_pane.set_value,fg_bg=style.bw_fg_bg}

    -- link pocket API list management to PGI
    pgi.link_elements(api_list, pkt_entry)
end

return init
