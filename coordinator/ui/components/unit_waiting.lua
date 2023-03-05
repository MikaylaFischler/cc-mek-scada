--
-- Reactor Unit Waiting Spinner
--

local style       = require("coordinator.ui.style")

local core        = require("graphics.core")

local Div         = require("graphics.elements.div")
local TextBox     = require("graphics.elements.textbox")

local WaitingAnim = require("graphics.elements.animations.waiting")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair

-- create a unit waiting view
---@param parent graphics_element parent
---@param y integer y offset
local function init(parent, y)
    -- bounding box div
    local root = Div{parent=parent,x=1,y=y,height=5}

    local waiting_x = math.floor(parent.width() / 2) - 2

    TextBox{parent=root,text="Waiting for status...",alignment=TEXT_ALIGN.CENTER,y=1,height=1,fg_bg=cpair(colors.black,style.root.bkg)}
    WaitingAnim{parent=root,x=waiting_x,y=3,fg_bg=cpair(colors.blue,style.root.bkg)}

    return root
end

return init
