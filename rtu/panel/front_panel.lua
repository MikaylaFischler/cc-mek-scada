--
-- Main SCADA Coordinator GUI
--

local util       = require("scada-common.util")

local databus    = require("rtu.databus")

local style      = require("rtu.panel.style")

local core       = require("graphics.core")

local Div        = require("graphics.elements.div")
local TextBox    = require("graphics.elements.textbox")

local LED        = require("graphics.elements.indicators.led")
local RGBLED     = require("graphics.elements.indicators.ledrgb")

local TEXT_ALIGN = core.TEXT_ALIGN

local cpair = core.cpair

local UNIT_TYPE_LABELS = {
    "UNKNOWN",
    "REDSTONE",
    "BOILER",
    "TURBINE",
    "IND MATRIX",
    "SPS",
    "SNA",
    "ENV DETECTOR"
}


-- create new main view
---@param panel graphics_element main displaybox
---@param units table unit list
local function init(panel, units)
    TextBox{parent=panel,y=1,text="RTU GATEWAY",alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    --
    -- system indicators
    --

    local system = Div{parent=panel,width=14,height=18,x=2,y=3}

    local on = LED{parent=system,label="POWER",colors=cpair(colors.green,colors.red)}
    local heartbeat = LED{parent=system,label="HEARTBEAT",colors=cpair(colors.green,colors.green_off)}
    on.update(true)
    system.line_break()

    databus.rx_field("heartbeat", heartbeat.update)

    local modem = LED{parent=system,label="MODEM",colors=cpair(colors.green,colors.green_off)}
    local network = RGBLED{parent=system,label="NETWORK",colors={colors.green,colors.red,colors.orange,colors.yellow,colors.gray}}
    network.update(5)
    system.line_break()

    databus.rx_field("has_modem", modem.update)
    databus.rx_field("link_state", network.update)

    local rt_main = LED{parent=system,label="RT MAIN",colors=cpair(colors.green,colors.green_off)}
    local rt_comm = LED{parent=system,label="RT COMMS",colors=cpair(colors.green,colors.green_off)}
    system.line_break()

    databus.rx_field("routine__main", rt_main.update)
    databus.rx_field("routine__comms", rt_comm.update)

    --
    -- about label
    --

    local about   = Div{parent=panel,width=15,height=3,x=1,y=18,fg_bg=cpair(colors.lightGray,colors.ivory)}
    local fw_v    = TextBox{parent=about,x=1,y=1,text="FW: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}
    local comms_v = TextBox{parent=about,x=1,y=2,text="NT: v00.00.00",alignment=TEXT_ALIGN.LEFT,height=1}

    databus.rx_field("version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    databus.rx_field("comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    --
    -- unit status list
    --

    local threads = Div{parent=panel,width=8,height=18,x=17,y=3}

    -- display up to 16 units
    local list_length = math.min(#units, 16)

    -- show routine statuses
    for i = 1, list_length do
        TextBox{parent=threads,x=1,y=i,text=util.sprintf("%02d",i),height=1}
        local rt_unit = LED{parent=threads,x=4,y=i,label="RT",colors=cpair(colors.green,colors.green_off)}
        databus.rx_field("routine__unit_" .. i, rt_unit.update)
    end

    local unit_hw_statuses = Div{parent=panel,height=18,x=25,y=3}

    -- show hardware statuses
    for i = 1, list_length do
        local unit = units[i]   ---@type rtu_unit_registry_entry

        -- hardware status
        local unit_hw = RGBLED{parent=unit_hw_statuses,y=i,label="",colors={colors.red,colors.orange,colors.yellow,colors.green}}

        databus.rx_field("unit_hw_" .. i, unit_hw.update)

        -- unit name identifier (type + index)
        local name = util.c(UNIT_TYPE_LABELS[unit.type + 1], " ", unit.index)
        local name_box = TextBox{parent=unit_hw_statuses,y=i,x=3,text=name,height=1}

        databus.rx_field("unit_type_" .. i, function (t)
            name_box.set_value(util.c(UNIT_TYPE_LABELS[t + 1], " ", unit.index))
        end)

        -- assignment (unit # or facility)
        local for_unit = util.trinary(unit.reactor == 0, "\x1a FACIL ", "\x1a UNIT " .. unit.reactor)
        TextBox{parent=unit_hw_statuses,y=i,x=19,text=for_unit,height=1,fg_bg=cpair(colors.lightGray,colors.ivory)}
    end
end

return init
