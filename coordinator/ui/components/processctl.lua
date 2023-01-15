local util              = require("scada-common.util")

local iocontrol         = require("coordinator.iocontrol")

local style             = require("coordinator.ui.style")

local core              = require("graphics.core")

local Div               = require("graphics.elements.div")
local Rectangle         = require("graphics.elements.rectangle")
local TextBox           = require("graphics.elements.textbox")

local AlarmLight        = require("graphics.elements.indicators.alight")
local CoreMap           = require("graphics.elements.indicators.coremap")
local DataIndicator     = require("graphics.elements.indicators.data")
local IndicatorLight    = require("graphics.elements.indicators.light")
local TriIndicatorLight = require("graphics.elements.indicators.trilight")
local VerticalBar       = require("graphics.elements.indicators.vbar")

local HazardButton      = require("graphics.elements.controls.hazard_button")
local MultiButton       = require("graphics.elements.controls.multi_button")
local PushButton        = require("graphics.elements.controls.push_button")
local RadioButton       = require("graphics.elements.controls.radio_button")
local SpinboxNumeric    = require("graphics.elements.controls.spinbox_numeric")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border

-- new process control view
---@param root graphics_element parent
---@param x integer top left x
---@param y integer top left y
local function new_view(root, x, y)
    local facility = iocontrol.get_db().facility
    local units = iocontrol.get_db().units

    local bw_fg_bg = cpair(colors.black, colors.white)

    local proc = Div{parent=root,width=60,height=24,x=x,y=y}

    local limits = Div{parent=proc,width=40,height=24,x=30,y=1}

    for i = 1, facility.num_units do
        local unit = units[i]   ---@type ioctl_entry

        local _y = ((i - 1) * 4) + 1

        TextBox{parent=limits,x=1,y=_y+1,text="Unit "..i}

        local lim_ctl = Div{parent=limits,x=8,y=_y,width=20,height=3,fg_bg=cpair(colors.gray,colors.white)}
        local burn_rate = SpinboxNumeric{parent=lim_ctl,x=2,y=1,whole_num_precision=4,fractional_precision=1,min=0.1,max=0.1,arrow_fg_bg=cpair(colors.gray,colors.white),fg_bg=bw_fg_bg}

        unit.reactor_ps.subscribe("max_burn", burn_rate.set_max)
        unit.reactor_ps.subscribe("burn_limit", burn_rate.set_value)

        TextBox{parent=lim_ctl,x=9,y=2,text="mB/t"}

        local set_burn = function () unit.set_limit(burn_rate.get_value()) end
        PushButton{parent=lim_ctl,x=14,y=2,text="SAVE",min_width=6,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=cpair(colors.white,colors.gray),callback=set_burn}
    end
end

return new_view
