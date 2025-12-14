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
local Rectangle = require("graphics.elements.Rectangle")
local TextBox   = require("graphics.elements.TextBox")

local TabBar    = require("graphics.elements.controls.TabBar")

local LED       = require("graphics.elements.indicators.LED")
local LEDPair   = require("graphics.elements.indicators.LEDPair")
local RGBLED    = require("graphics.elements.indicators.RGBLED")

local LINK_STATE = types.PANEL_LINK_STATE

local ALIGN = core.ALIGN

local cpair = core.cpair
local border = core.border

local led_grn = style.led_grn

-- create new front panel view
---@param panel DisplayBox main displaybox
---@param config crd_config configuration
local function init(panel, config)
    local s_hi_box = style.fp_theme.highlight_box

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
    system.line_break()

    status.register(ps, "status", status.update)
    heartbeat.register(ps, "heartbeat", heartbeat.update)

    if config.WirelessModem and config.WiredModem then
        local wd_modem = LEDPair{parent=system,label="WD MODEM",off=colors.green_off,c1=colors.yellow,c2=colors.green}
        local wl_modem = LEDPair{parent=system,label="WL MODEM",off=colors.green_off,c1=colors.yellow,c2=colors.green}

        local function wd_modem_update()
            if ps.get("has_wd_modem") then
                if ps.get("has_wd_net") then
                    wd_modem.update(3)
                else wd_modem.update(2) end
            else wd_modem.update(1) end
        end

        local function wl_modem_update()
            if ps.get("has_wl_modem") then
                if ps.get("has_wl_net") then
                    wl_modem.update(3)
                else wl_modem.update(2) end
            else wl_modem.update(1) end
        end

        wd_modem.register(ps, "has_wd_modem", wd_modem_update)
        wd_modem.register(ps, "has_wd_net", wd_modem_update)
        wl_modem.register(ps, "has_wl_modem", wl_modem_update)
        wl_modem.register(ps, "has_wl_net", wl_modem_update)
    else
        local modem = LEDPair{parent=system,label="MODEM",off=colors.green_off,c1=colors.yellow,c2=colors.green}

        local pfx = util.trinary(config.WirelessModem, "has_wl_", "has_wd_")

        local function modem_update()
            if ps.get(pfx .. "modem") then
                if ps.get(pfx .. "net") then
                    modem.update(3)
                else modem.update(2) end
            else modem.update(1) end
        end

        modem.register(ps, pfx .. "modem", modem_update)
        modem.register(ps, pfx .. "net", modem_update)
    end

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

    local rt_main = LED{parent=system,label="RT MAIN",colors=led_grn}
    local rt_render = LED{parent=system,label="RT RENDER",colors=led_grn}

    rt_main.register(ps, "routine__main", rt_main.update)
    rt_render.register(ps, "routine__render", rt_render.update)

    local hmi_devs = Div{parent=main_page,width=16,height=17,x=18,y=2}

    local speaker = LED{parent=hmi_devs,label="SPEAKER",colors=led_grn}
    speaker.register(ps, "has_speaker", speaker.update)

    hmi_devs.line_break()

    local main_disp = LEDPair{parent=hmi_devs,label="MAIN DISPLAY",off=style.fp_ind_bkg,c1=colors.red,c2=colors.green}
    main_disp.register(ps, "main_monitor", main_disp.update)

    local flow_disp = LEDPair{parent=hmi_devs,label="FLOW DISPLAY",off=style.fp_ind_bkg,c1=colors.red,c2=colors.green}
    flow_disp.register(ps, "flow_monitor", flow_disp.update)

    hmi_devs.line_break()

    for i = 1, config.UnitCount do
        local unit_disp = LEDPair{parent=hmi_devs,label="UNIT "..i.." DISPLAY",off=style.fp_ind_bkg,c1=colors.red,c2=colors.green}
        unit_disp.register(ps, "unit_monitor_" .. i, unit_disp.update)
    end

    --
    -- hardware labeling
    --

    local hw_labels = Rectangle{parent=main_page,x=2,y=term_h-7,width=14,height=5,border=border(1,s_hi_box.bkg,true),even_inner=true}

---@diagnostic disable-next-line: undefined-field
    local comp_id = util.sprintf("%03d", os.getComputerID())

    TextBox{parent=hw_labels,text="FW "..ps.get("version"),fg_bg=s_hi_box}
    TextBox{parent=hw_labels,text="NT v"..ps.get("comms_version"),fg_bg=s_hi_box}
    TextBox{parent=hw_labels,text="SN "..comp_id.."-CRD",fg_bg=s_hi_box}

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
