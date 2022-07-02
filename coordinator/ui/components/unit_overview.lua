local core = require("graphics.core")

local style = require("coordinator.ui.style")

local reactor_view = require("coordinator.ui.components.reactor")
local boiler_view  = require("coordinator.ui.components.boiler")

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
    local root = Div{parent=parent,x=x,y=y,width=75,height=50}

    -- unit header message
    TextBox{parent=root,text="Unit #" .. unit_id,alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    -------------
    -- REACTOR --
    -------------

    reactor_view(root, 1, 3)

    local pipes = {
        pipe(0, 0, 13, 12, colors.lightBlue),
        pipe(0, 0, 13, 3, colors.lightBlue),
        pipe(2, 0, 11, 2, colors.orange),
        pipe(2, 0, 11, 11, colors.orange)
    }

    PipeNetwork{parent=root,x=12,y=10,pipes=pipes,bg=colors.lightGray}

    -------------
    -- BOILERS --
    -------------

    boiler_view(root, 23, 11)
    boiler_view(root, 23, 20)

end

return make
