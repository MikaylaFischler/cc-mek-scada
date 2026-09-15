local core       = require("graphics.core")

local Div        = require("graphics.elements.Div")
local TextBox    = require("graphics.elements.TextBox")

local Rectangle  = require("graphics.elements.Rectangle")

local PushButton = require("graphics.elements.controls.PushButton")

local border = core.border
local cpair = core.cpair

-- create a desktop style window
---@param parent Container
---@param width integer
---@param height integer
---@param title string
---@param close_cb function
---@return Div root, Rectangle window
return function (parent, width, height, title, close_cb)
    local root = Div{parent=parent,x=math.floor((parent.get_width()-width)/2),y=math.ceil((parent.get_height()-height)/2),width=width,height=height}

    TextBox{parent=root,x=1,y=1,height=1,text=string.rep("\x8f",width-3),fg_bg=cpair(parent.get_fg_bg().bkg,colors.gray)}
    TextBox{parent=root,x=1,y=2,text=" "..title,fg_bg=cpair(colors.white,colors.gray)}

    PushButton{parent=root,x=width-2,y=1,min_width=3,text="\x8f\x8f\x8f",fg_bg=cpair(parent.get_fg_bg().bkg,colors.red),callback=close_cb}
    PushButton{parent=root,x=width-2,y=2,min_width=3,text="\xd7",fg_bg=cpair(colors.white,colors.red),callback=close_cb}

    local window = Rectangle{parent=root,x=1,y=3,border=border(1,colors.gray,true)}

    return root, window
end
