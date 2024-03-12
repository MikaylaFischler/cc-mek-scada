--
-- Supervisor Front Panel GUI
--

local util          = require("scada-common.util")

local databus       = require("supervisor.databus")
local supervisor    = require("supervisor.supervisor")

local pgi           = require("supervisor.panel.pgi")
local style         = require("supervisor.panel.style")

local pdg_entry     = require("supervisor.panel.components.pdg_entry")
local rtu_entry     = require("supervisor.panel.components.rtu_entry")

local core          = require("graphics.core")

local Div           = require("graphics.elements.div")
local ListBox       = require("graphics.elements.listbox")
local MultiPane     = require("graphics.elements.multipane")
local TextBox       = require("graphics.elements.textbox")

local TabBar        = require("graphics.elements.controls.tabbar")

local LED           = require("graphics.elements.indicators.led")
local DataIndicator = require("graphics.elements.indicators.data")

local ALIGN = core.ALIGN

local cpair = core.cpair

local ind_grn = style.ind_grn

-- create new front panel view
---@param panel graphics_element main displaybox
local function init(panel)
    local s_hi_box = style.theme.highlight_box
    local s_hi_bright = style.theme.highlight_box_bright

    local label_fg = style.fp.label_fg
    local label_d_fg = style.fp.label_d_fg

    TextBox{parent=panel,y=1,text="SCADA SUPERVISOR",alignment=ALIGN.CENTER,height=1,fg_bg=style.theme.header}

    local page_div = Div{parent=panel,x=1,y=3}

    --
    -- system indicators
    --

    local main_page = Div{parent=page_div,x=1,y=1}

    local system = Div{parent=main_page,width=14,height=17,x=2,y=2}

    local on = LED{parent=system,label="STATUS",colors=cpair(colors.green,colors.red)}
    local heartbeat = LED{parent=system,label="HEARTBEAT",colors=ind_grn}
    on.update(true)
    system.line_break()

    heartbeat.register(databus.ps, "heartbeat", heartbeat.update)

    local modem = LED{parent=system,label="MODEM",colors=ind_grn}
    system.line_break()

    modem.register(databus.ps, "has_modem", modem.update)

---@diagnostic disable-next-line: undefined-field
    local comp_id = util.sprintf("(%d)", os.getComputerID())
    TextBox{parent=system,x=9,y=4,width=6,height=1,text=comp_id,fg_bg=style.fp.disabled_fg}

    --
    -- about footer
    --

    local about   = Div{parent=main_page,width=15,height=3,x=1,y=16,fg_bg=style.fp.disabled_fg}
    local fw_v    = TextBox{parent=about,x=1,y=1,text="FW: v00.00.00",alignment=ALIGN.LEFT,height=1}
    local comms_v = TextBox{parent=about,x=1,y=2,text="NT: v00.00.00",alignment=ALIGN.LEFT,height=1}

    fw_v.register(databus.ps, "version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    comms_v.register(databus.ps, "comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    --
    -- page handling
    --

    -- plc page

    local plc_page = Div{parent=page_div,x=1,y=1,hidden=true}
    local plc_list = Div{parent=plc_page,x=2,y=2,width=49}

    for i = 1, supervisor.config.UnitCount do
        local ps_prefix = "plc_" .. i .. "_"
        local plc_entry = Div{parent=plc_list,height=3,fg_bg=s_hi_bright}

        TextBox{parent=plc_entry,x=1,y=1,text="",width=8,height=1,fg_bg=s_hi_box}
        TextBox{parent=plc_entry,x=1,y=2,text="UNIT "..i,alignment=ALIGN.CENTER,width=8,height=1,fg_bg=s_hi_box}
        TextBox{parent=plc_entry,x=1,y=3,text="",width=8,height=1,fg_bg=s_hi_box}

        local conn = LED{parent=plc_entry,x=10,y=2,label="LINK",colors=cpair(colors.green_hc,colors.green_off)}
        conn.register(databus.ps, ps_prefix .. "conn", conn.update)

        local plc_addr = TextBox{parent=plc_entry,x=17,y=2,text=" --- ",width=5,height=1,fg_bg=label_d_fg}
        plc_addr.register(databus.ps, ps_prefix .. "addr", plc_addr.set_value)

        TextBox{parent=plc_entry,x=23,y=2,text="FW:",width=3,height=1}
        local plc_fw_v = TextBox{parent=plc_entry,x=27,y=2,text=" ------- ",width=9,height=1,fg_bg=label_fg}
        plc_fw_v.register(databus.ps, ps_prefix .. "fw", plc_fw_v.set_value)

        TextBox{parent=plc_entry,x=37,y=2,text="RTT:",width=4,height=1}
        local plc_rtt = DataIndicator{parent=plc_entry,x=42,y=2,label="",unit="",format="%4d",value=0,width=4,fg_bg=label_fg}
        TextBox{parent=plc_entry,x=47,y=2,text="ms",width=4,height=1,fg_bg=label_fg}
        plc_rtt.register(databus.ps, ps_prefix .. "rtt", plc_rtt.update)
        plc_rtt.register(databus.ps, ps_prefix .. "rtt_color", plc_rtt.recolor)

        plc_list.line_break()
    end

    -- rtu page

    local rtu_page = Div{parent=page_div,x=1,y=1,hidden=true}
    local rtu_list = ListBox{parent=rtu_page,x=1,y=1,height=17,width=51,scroll_height=1000,fg_bg=cpair(colors.black,colors.ivory),nav_fg_bg=cpair(colors.gray,colors.lightGray),nav_active=cpair(colors.black,colors.gray)}
    local _ = Div{parent=rtu_list,height=1,hidden=true} -- padding

    -- coordinator page

    local crd_page = Div{parent=page_div,x=1,y=1,hidden=true}
    local crd_box = Div{parent=crd_page,x=2,y=2,width=49,height=4,fg_bg=s_hi_bright}

    local crd_conn = LED{parent=crd_box,x=2,y=2,label="CONNECTION",colors=cpair(colors.green_hc,colors.green_off)}
    crd_conn.register(databus.ps, "crd_conn", crd_conn.update)

    TextBox{parent=crd_box,x=4,y=3,text="COMPUTER",width=8,height=1,fg_bg=label_d_fg}
    local crd_addr = TextBox{parent=crd_box,x=13,y=3,text="---",width=5,height=1,fg_bg=label_d_fg}
    crd_addr.register(databus.ps, "crd_addr", crd_addr.set_value)

    TextBox{parent=crd_box,x=22,y=2,text="FW:",width=3,height=1}
    local crd_fw_v = TextBox{parent=crd_box,x=26,y=2,text=" ------- ",width=9,height=1,fg_bg=label_fg}
    crd_fw_v.register(databus.ps, "crd_fw", crd_fw_v.set_value)

    TextBox{parent=crd_box,x=36,y=2,text="RTT:",width=4,height=1}
    local crd_rtt = DataIndicator{parent=crd_box,x=41,y=2,label="",unit="",format="%5d",value=0,width=5,fg_bg=label_fg}
    TextBox{parent=crd_box,x=47,y=2,text="ms",width=4,height=1,fg_bg=label_fg}
    crd_rtt.register(databus.ps, "crd_rtt", crd_rtt.update)
    crd_rtt.register(databus.ps, "crd_rtt_color", crd_rtt.recolor)

    -- pocket diagnostics page

    local pkt_page = Div{parent=page_div,x=1,y=1,hidden=true}
    local pdg_list = ListBox{parent=pkt_page,x=1,y=1,height=17,width=51,scroll_height=1000,fg_bg=style.fp.text_fg,nav_fg_bg=cpair(colors.gray,colors.lightGray),nav_active=cpair(colors.black,colors.gray)}
    local _ = Div{parent=pdg_list,height=1,hidden=true} -- padding

    -- assemble page panes

    local panes = { main_page, plc_page, rtu_page, crd_page, pkt_page }

    local page_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}

    local tabs = {
        { name = "SVR", color = style.fp.text },
        { name = "PLC", color = style.fp.text },
        { name = "RTU", color = style.fp.text },
        { name = "CRD", color = style.fp.text },
        { name = "PKT", color = style.fp.text },
    }

    TabBar{parent=panel,y=2,tabs=tabs,min_width=9,callback=page_pane.set_value,fg_bg=style.theme.highlight_box_bright}

    -- link RTU/PDG list management to PGI
    pgi.link_elements(rtu_list, rtu_entry, pdg_list, pdg_entry)
end

return init
