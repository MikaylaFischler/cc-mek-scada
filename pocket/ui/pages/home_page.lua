--
-- Main Home Page
--

local iocontrol = require("pocket.iocontrol")

local core      = require("graphics.core")

local Div       = require("graphics.elements.div")

local App       = require("graphics.elements.controls.app")

local cpair = core.cpair

-- new home page view
---@param root graphics_element parent
local function new_view(root)
    local db = iocontrol.get_db()

    db.nav.new_page(nil, 1)

    local main = Div{parent=root,x=1,y=1}

    App{parent=main,x=3,y=2,text="\x17",title="PRC",callback=function()end,app_fg_bg=cpair(colors.black,colors.purple)}
    App{parent=main,x=10,y=2,text="\x15",title="CTL",callback=function()end,app_fg_bg=cpair(colors.black,colors.green)}
    App{parent=main,x=17,y=2,text="\x08",title="DEV",callback=function()end,app_fg_bg=cpair(colors.black,colors.lightGray)}
    App{parent=main,x=3,y=7,text="\x7f",title="Waste",callback=function()end,app_fg_bg=cpair(colors.black,colors.brown)}
    App{parent=main,x=10,y=7,text="\xb6",title="Guide",callback=function()end,app_fg_bg=cpair(colors.black,colors.cyan)}

    return main
end

return new_view
