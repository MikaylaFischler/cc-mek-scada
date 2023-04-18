--
-- Connection Waiting Spinner
--

local style       = require("pocket.ui.style")

local core        = require("graphics.core")

local Div         = require("graphics.elements.div")
local TextBox     = require("graphics.elements.textbox")

local WaitingAnim = require("graphics.elements.animations.waiting")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair

-- create a waiting view
---@param parent graphics_element parent
---@param y integer y offset
local function init(parent, y, is_api)
    -- bounding box div
    local root = Div{parent=parent,x=1,y=y,height=5}

    local waiting_x = math.floor(parent.width() / 2) - 1

    if is_api then
        WaitingAnim{parent=root,x=waiting_x,y=1,fg_bg=cpair(colors.blue,style.root.bkg)}
        TextBox{parent=root,text="Connecting to API",alignment=TEXT_ALIGN.CENTER,y=5,height=1,fg_bg=cpair(colors.white,style.root.bkg)}
    else
        WaitingAnim{parent=root,x=waiting_x,y=1,fg_bg=cpair(colors.green,style.root.bkg)}
        TextBox{parent=root,text="Connecting to Supervisor",alignment=TEXT_ALIGN.CENTER,y=5,height=1,fg_bg=cpair(colors.white,style.root.bkg)}
    end

    return root
end

return init
