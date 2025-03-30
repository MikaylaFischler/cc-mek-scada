--
-- RTU Front Panel GUI
--

local types         = require("scada-common.types")
local util          = require("scada-common.util")

local databus       = require("rtu.databus")

local style         = require("rtu.panel.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local TextBox       = require("graphics.elements.TextBox")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")
local LED           = require("graphics.elements.indicators.LED")
local LEDPair       = require("graphics.elements.indicators.LEDPair")
local RGBLED        = require("graphics.elements.indicators.RGBLED")

local LINK_STATE = types.PANEL_LINK_STATE

local ALIGN = core.ALIGN

local cpair = core.cpair

local ind_grn = style.ind_grn

local UNIT_TYPE_LABELS = { "UNKNOWN", "REDSTONE", "BOILER", "TURBINE", "DYNAMIC TANK", "IND MATRIX", "SPS", "SNA", "ENV DETECTOR" }

-- create new front panel view
---@param panel DisplayBox main displaybox
---@param units rtu_registry_entry[] unit list
local function init(panel, units)
    local disabled_fg = style.fp.disabled_fg

    local term_w, term_h = term.getSize()

    TextBox{parent=panel,y=1,text="RTU GATEWAY",alignment=ALIGN.CENTER,fg_bg=style.theme.header}

    --
    -- system indicators
    --

    local system = Div{parent=panel,width=14,height=term_h-5,x=2,y=3}

    local on = LED{parent=system,label="STATUS",colors=cpair(colors.green,colors.red)}
    local heartbeat = LED{parent=system,label="HEARTBEAT",colors=ind_grn}
    on.update(true)
    system.line_break()

    heartbeat.register(databus.ps, "heartbeat", heartbeat.update)

    local modem = LED{parent=system,label="MODEM",colors=ind_grn}

    if not style.colorblind then
        local network = RGBLED{parent=system,label="NETWORK",colors={colors.green,colors.red,colors.yellow,colors.orange,style.ind_bkg}}
        network.update(types.PANEL_LINK_STATE.DISCONNECTED)
        network.register(databus.ps, "link_state", network.update)
    else
        local nt_lnk = LEDPair{parent=system,label="NT LINKED",off=style.ind_bkg,c1=colors.red,c2=colors.green}
        local nt_ver = LEDPair{parent=system,label="NT VERSION",off=style.ind_bkg,c1=colors.red,c2=colors.green}

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
    end

    system.line_break()

    modem.register(databus.ps, "has_modem", modem.update)

    local rt_main = LED{parent=system,label="RT MAIN",colors=ind_grn}
    local rt_comm = LED{parent=system,label="RT COMMS",colors=ind_grn}
    system.line_break()

    rt_main.register(databus.ps, "routine__main", rt_main.update)
    rt_comm.register(databus.ps, "routine__comms", rt_comm.update)

---@diagnostic disable-next-line: undefined-field
    local comp_id = util.sprintf("(%d)", os.getComputerID())
    TextBox{parent=system,x=9,y=4,width=6,text=comp_id,fg_bg=disabled_fg}

    TextBox{parent=system,y=term_h-5,text="SPEAKERS",width=8,fg_bg=style.fp.text_fg}
    local speaker_count = DataIndicator{parent=system,x=10,y=term_h-5,label="",format="%3d",value=0,width=3,fg_bg=style.theme.field_box}
    speaker_count.register(databus.ps, "speaker_count", speaker_count.update)

    --
    -- about label
    --

    local about   = Div{parent=panel,width=15,height=2,y=term_h-1,fg_bg=disabled_fg}
    local fw_v    = TextBox{parent=about,text="FW: v00.00.00"}
    local comms_v = TextBox{parent=about,text="NT: v00.00.00"}

    fw_v.register(databus.ps, "version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    comms_v.register(databus.ps, "comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    --
    -- unit status list
    --

    local threads = Div{parent=panel,width=8,height=term_h-3,x=17,y=3}

    -- display as many units as we can with 1 line of padding above and below
    local list_length = math.min(#units, term_h - 3)

    -- show routine statuses
    for i = 1, list_length do
        TextBox{parent=threads,x=1,y=i,text=util.sprintf("%02d",i)}
        local rt_unit = LED{parent=threads,x=4,y=i,label="RT",colors=ind_grn}
        rt_unit.register(databus.ps, "routine__unit_" .. i, rt_unit.update)
    end

    local unit_hw_statuses = Div{parent=panel,height=term_h-3,x=25,y=3}

    -- show hardware statuses
    for i = 1, list_length do
        local unit = units[i]

        -- hardware status
        local unit_hw = RGBLED{parent=unit_hw_statuses,y=i,label="",colors={colors.red,colors.orange,colors.yellow,colors.green}}

        unit_hw.register(databus.ps, "unit_hw_" .. i, unit_hw.update)

        -- unit name identifier (type + index)
        local function get_name(t) return util.c(UNIT_TYPE_LABELS[t + 1], " ", util.trinary(util.is_int(unit.index), unit.index, "")) end
        local name_box = TextBox{parent=unit_hw_statuses,y=i,x=3,text=get_name(unit.type),width=15}

        name_box.register(databus.ps, "unit_type_" .. i, function (t) name_box.set_value(get_name(t)) end)

        -- assignment (unit # or facility)
        local for_unit = util.trinary(unit.reactor == 0, "\x1a FACIL ", "\x1a UNIT " .. unit.reactor)
        TextBox{parent=unit_hw_statuses,y=i,x=term_w-32,text=for_unit,fg_bg=disabled_fg}
    end
end

return init
