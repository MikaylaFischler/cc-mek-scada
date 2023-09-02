--
-- RTU Front Panel GUI
--

local types         = require("scada-common.types")
local util          = require("scada-common.util")

local databus       = require("rtu.databus")

local style         = require("rtu.panel.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.div")
local TextBox       = require("graphics.elements.textbox")

local DataIndicator = require("graphics.elements.indicators.data")
local LED           = require("graphics.elements.indicators.led")
local RGBLED        = require("graphics.elements.indicators.ledrgb")

local TEXT_ALIGN = core.TEXT_ALIGN

local cpair = core.cpair

local fp_label = style.fp_label

local ind_grn = style.ind_grn

local UNIT_TYPE_LABELS = { "UNKNOWN", "REDSTONE", "BOILER", "TURBINE", "DYNAMIC TANK", "IND MATRIX", "SPS", "SNA", "ENV DETECTOR" }

-- create new front panel view
---@param panel graphics_element main displaybox
---@param units table unit list
local function init(panel, units)
    TextBox{parent=panel,y=1,text="RTU GATEWAY",alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    --
    -- system indicators
    --

    local system = Div{parent=panel,width=14,height=18,x=2,y=3}

    local on = LED{parent=system,label="STATUS",colors=cpair(colors.green,colors.red)}
    local heartbeat = LED{parent=system,label="HEARTBEAT",colors=ind_grn}
    on.update(true)
    system.line_break()

    heartbeat.register(databus.ps, "heartbeat", heartbeat.update)

    local modem = LED{parent=system,label="MODEM",colors=ind_grn}
    local network = RGBLED{parent=system,label="NETWORK",colors={colors.green,colors.red,colors.orange,colors.yellow,colors.gray}}
    network.update(types.PANEL_LINK_STATE.DISCONNECTED)
    system.line_break()

    modem.register(databus.ps, "has_modem", modem.update)
    network.register(databus.ps, "link_state", network.update)

    local rt_main = LED{parent=system,label="RT MAIN",colors=ind_grn}
    local rt_comm = LED{parent=system,label="RT COMMS",colors=ind_grn}
    system.line_break()

    rt_main.register(databus.ps, "routine__main", rt_main.update)
    rt_comm.register(databus.ps, "routine__comms", rt_comm.update)

---@diagnostic disable-next-line: undefined-field
    local comp_id = util.sprintf("(%d)", os.getComputerID())
    TextBox{parent=system,x=9,y=4,width=6,height=1,text=comp_id,fg_bg=fp_label}

    TextBox{parent=system,x=1,y=14,text="SPEAKERS",height=1,width=8,fg_bg=style.label}
    local speaker_count = DataIndicator{parent=system,x=10,y=14,label="",format="%3d",value=0,width=3,fg_bg=cpair(colors.gray,colors.white)}
    speaker_count.register(databus.ps, "speaker_count", speaker_count.update)

    --
    -- about label
    --

    local about   = Div{parent=panel,width=15,height=3,x=1,y=18,fg_bg=fp_label}
    local fw_v    = TextBox{parent=about,x=1,y=1,text="FW: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}
    local comms_v = TextBox{parent=about,x=1,y=2,text="NT: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}

    fw_v.register(databus.ps, "version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    comms_v.register(databus.ps, "comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    --
    -- unit status list
    --

    local threads = Div{parent=panel,width=8,height=18,x=17,y=3}

    -- display up to 16 units
    local list_length = math.min(#units, 16)

    -- show routine statuses
    for i = 1, list_length do
        TextBox{parent=threads,x=1,y=i,text=util.sprintf("%02d",i),height=1}
        local rt_unit = LED{parent=threads,x=4,y=i,label="RT",colors=ind_grn}
        rt_unit.register(databus.ps, "routine__unit_" .. i, rt_unit.update)
    end

    local unit_hw_statuses = Div{parent=panel,height=18,x=25,y=3}

    -- show hardware statuses
    for i = 1, list_length do
        local unit = units[i]   ---@type rtu_unit_registry_entry

        -- hardware status
        local unit_hw = RGBLED{parent=unit_hw_statuses,y=i,label="",colors={colors.red,colors.orange,colors.yellow,colors.green}}

        unit_hw.register(databus.ps, "unit_hw_" .. i, unit_hw.update)

        -- unit name identifier (type + index)
        local name = util.c(UNIT_TYPE_LABELS[unit.type + 1], " ", unit.index)
        local name_box = TextBox{parent=unit_hw_statuses,y=i,x=3,text=name,height=1}

        name_box.register(databus.ps, "unit_type_" .. i, function (t)
            name_box.set_value(util.c(UNIT_TYPE_LABELS[t + 1], " ", unit.index))
        end)

        -- assignment (unit # or facility)
        local for_unit = util.trinary(unit.reactor == 0, "\x1a FACIL ", "\x1a UNIT " .. unit.reactor)
        TextBox{parent=unit_hw_statuses,y=i,x=19,text=for_unit,height=1,fg_bg=fp_label}
    end
end

return init
