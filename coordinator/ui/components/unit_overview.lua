local core = require("graphics.core")

local style = require("coordinator.ui.style")

local reactor_view = require("coordinator.ui.components.reactor")
local boiler_view  = require("coordinator.ui.components.boiler")
local turbine_view = require("coordinator.ui.components.turbine")

local Div            = require("graphics.elements.div")
local PipeNetwork    = require("graphics.elements.pipenet")
local Rectangle      = require("graphics.elements.rectangle")
local TextBox        = require("graphics.elements.textbox")

local HorizontalBar  = require("graphics.elements.indicators.hbar")
local DataIndicator  = require("graphics.elements.indicators.data")
local StateIndicator = require("graphics.elements.indicators.state")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border
local pipe = core.graphics.pipe

---@param parent graphics_element
local function make(parent, x, y, unit_id)
    -- bounding box div
    local root = Div{parent=parent,x=x,y=y,width=80,height=27}--,fg_bg=cpair(colors.white,colors.black)}

    -- unit header message
    TextBox{parent=root,text="Unit #" .. unit_id,alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    -------------
    -- REACTOR --
    -------------

    reactor_view(root, 1, 3)

    local coolant_pipes = {
        pipe(0, 0, 12, 12, colors.lightBlue),
        pipe(0, 0, 12, 3, colors.lightBlue),
        pipe(2, 0, 11, 2, colors.orange),
        pipe(2, 0, 11, 11, colors.orange)
    }

    PipeNetwork{parent=root,x=4,y=10,pipes=coolant_pipes,bg=colors.lightGray}

    -------------
    -- BOILERS --
    -------------

    boiler_view(root, 16, 11)
    boiler_view(root, 16, 20)

    --------------
    -- TURBINES --
    --------------

    turbine_view(root, 58, 3)
    turbine_view(root, 58, 11)
    turbine_view(root, 58, 20)

    local steam_pipes_a = {
        -- boiler 1
        pipe(0, 1, 6, 1, colors.white, false, true),
        pipe(0, 2, 6, 2, colors.blue, false, true),
        -- boiler 2
        pipe(0, 10, 6, 10, colors.white, false, true),
        pipe(0, 11, 6, 11, colors.blue, false, true)
    }

    local steam_pipes_b = {
        -- turbines 1 & 2, pipes from boiler 1
        pipe(0, 9, 1, 2, colors.white, false, true),
        pipe(1, 1, 3, 1, colors.white, false, false),
        pipe(0, 9, 3, 9, colors.white, false, true),
        pipe(0, 10, 2, 3, colors.blue, false, true),
        pipe(2, 2, 3, 2, colors.blue, false, false),
        pipe(0, 10, 3, 10, colors.blue, false, true),
        -- turbine 3, pipes from boiler 2
        pipe(0, 18, 1, 9, colors.white, false, true),
        pipe(1, 1, 3, 1, colors.white, false, false),
        pipe(0, 18, 3, 18, colors.white, false, true),
        pipe(0, 19, 2, 10, colors.blue, false, true),
        pipe(0, 19, 3, 19, colors.blue, false, true),
    }

    PipeNetwork{parent=root,x=47,y=11,pipes=steam_pipes_a,bg=colors.lightGray}
    PipeNetwork{parent=root,x=54,y=3,pipes=steam_pipes_b,bg=colors.lightGray}

end

return make
