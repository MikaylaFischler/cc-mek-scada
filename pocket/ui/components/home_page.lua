-- local style   = require("pocket.ui.style")

local core    = require("graphics.core")

local Div     = require("graphics.elements.div")
local TextBox = require("graphics.elements.textbox")

-- local cpair = core.cpair

local TEXT_ALIGN = core.TEXT_ALIGN

-- new home page view
---@param root graphics_element parent
local function new_view(root)
    local main = Div{parent=root,x=1,y=1}

    TextBox{parent=main,text="HOME",x=1,y=1,height=1,alignment=TEXT_ALIGN.CENTER}

    return main
end

return new_view
