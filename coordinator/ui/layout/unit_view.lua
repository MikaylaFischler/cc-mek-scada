--
-- Reactor Unit SCADA Coordinator GUI
--

local core   = require("graphics.core")

local style = require("coordinator.ui.style")

local DisplayBox = require("graphics.elements.displaybox")
local Div        = require("graphics.elements.div")
local TextBox    = require("graphics.elements.textbox")
local Tiling     = require("graphics.elements.tiling")

local DataIndicator  = require("graphics.elements.indicators.data")
local HorizontalBar  = require("graphics.elements.indicators.hbar")
local IndicatorLight = require("graphics.elements.indicators.light")
local StateIndicator = require("graphics.elements.indicators.state")

local PushButton     = require("graphics.elements.controls.push_button")
local SCRAMButton    = require("graphics.elements.controls.scram_button")
local SpinboxNumeric = require("graphics.elements.controls.spinbox_numeric")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border

local function init(monitor, id)
    local main = DisplayBox{window=monitor,fg_bg=style.root}

    TextBox{parent=main,text="Reactor Unit #" .. id,alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    local reactor_width = 18
    local core_width = ((reactor_width - 2) * 2) + 4
    local core_height = reactor_width

    local scram_fg_bg = core.graphics.cpair(colors.white, colors.gray)

    local reactor_top_view = Tiling{parent=main,x=2,y=3,width=core_width,height=core_height,fill_c=cpair(colors.lightGray,colors.lightBlue),even=true,border_c=colors.gray}

    local f = function () print("scram!") end
    local scram = SCRAMButton{parent=main,x=2,y=core_height+4,callback=f,fg_bg=scram_fg_bg}

    local burn_control = Div{parent=main,x=13,y=core_height+4,width=19,height=3,fg_bg=cpair(colors.gray,colors.white)}

    main(scram, burn_control)

    local burn_rate = SpinboxNumeric{parent=burn_control,x=2,y=1,whole_num_precision=4,fractional_precision=1,arrow_fg_bg=cpair(colors.gray,colors.white),fg_bg=cpair(colors.black,colors.white)}
    local set_burn = function () print("set burn to " .. burn_rate.get_value()) end

    burn_control(burn_rate)

    TextBox{parent=burn_control,x=9,y=2,text="mB/t"}
    burn_control(PushButton{parent=burn_control,x=14,y=2,text="SET",min_width=5,fg_bg=cpair(colors.black,colors.yellow),callback=set_burn})

    local annunciator = Div{parent=main,x=34,y=core_height+4}

    -- annunciator colors per IAEA-TECDOC-812 recommendations

    -- connectivity/basic state
    local plc_online = IndicatorLight{parent=annunciator,x=1,y=1,label="PLC Online",colors=cpair(colors.green,colors.red)}
    local r_active   = IndicatorLight{parent=annunciator,x=1,y=2,label="Active",colors=cpair(colors.green,colors.gray)}
    local r_auto     = IndicatorLight{parent=annunciator,x=1,y=3,label="Auto Control",colors=cpair(colors.blue,colors.gray)}

    -- annunciator fields
    local r_trip = IndicatorLight{parent=annunciator,x=1,y=5,label="Reactor Trip",colors=cpair(colors.red,colors.gray)}
    local r_mtrp = IndicatorLight{parent=annunciator,x=1,y=6,label="Manual Reactor Trip",colors=cpair(colors.red,colors.gray)}
    local r_rtrp = IndicatorLight{parent=annunciator,x=1,y=7,label="RCP Trip",colors=cpair(colors.red,colors.gray)}
    local r_cflo = IndicatorLight{parent=annunciator,x=1,y=8,label="RCS Flow Low",colors=cpair(colors.yellow,colors.gray)}
    local r_temp = IndicatorLight{parent=annunciator,x=1,y=9,label="Reactor Temp. High",colors=cpair(colors.red,colors.gray)}
    local r_rhdt = IndicatorLight{parent=annunciator,x=1,y=10,label="Reactor High Delta T",colors=cpair(colors.yellow,colors.gray)}
    local r_firl = IndicatorLight{parent=annunciator,x=1,y=11,label="Fuel Input Rate Low",colors=cpair(colors.yellow,colors.gray)}
    local r_wloc = IndicatorLight{parent=annunciator,x=1,y=12,label="Waste Line Occlusion",colors=cpair(colors.yellow,colors.gray)}
    local r_hsrt = IndicatorLight{parent=annunciator,x=1,y=13,label="High Startup Rate",colors=cpair(colors.yellow,colors.gray)}

    -- RPS
    local rps_trp = IndicatorLight{parent=annunciator,x=1,y=15,label="RPS Trip",colors=cpair(colors.red,colors.gray)}
    local rps_dmg = IndicatorLight{parent=annunciator,x=1,y=16,label="Damage Critical",colors=cpair(colors.yellow,colors.gray)}
    local rps_exh = IndicatorLight{parent=annunciator,x=1,y=17,label="Excess Heated Coolant",colors=cpair(colors.yellow,colors.gray)}
    local rps_exc = IndicatorLight{parent=annunciator,x=1,y=18,label="Excess Waste",colors=cpair(colors.yellow,colors.gray)}
    local rps_tmp = IndicatorLight{parent=annunciator,x=1,y=19,label="High Core Temp",colors=cpair(colors.yellow,colors.gray)}
    local rps_nof = IndicatorLight{parent=annunciator,x=1,y=20,label="No Fuel",colors=cpair(colors.yellow,colors.gray)}
    local rps_noc = IndicatorLight{parent=annunciator,x=1,y=21,label="No Coolant",colors=cpair(colors.yellow,colors.gray)}
    local rps_flt = IndicatorLight{parent=annunciator,x=1,y=22,label="PPM Fault",colors=cpair(colors.yellow,colors.gray)}
    local rps_tmo = IndicatorLight{parent=annunciator,x=1,y=23,label="Timeout",colors=cpair(colors.yellow,colors.gray)}

    r_auto.update(true)
    r_trip.update(true)
    r_mtrp.update(true)
    rps_trp.update(true)

    return main
end

return init
