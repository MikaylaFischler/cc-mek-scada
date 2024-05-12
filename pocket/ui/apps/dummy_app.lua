--
-- Placeholder App
--

local iocontrol = require("pocket.iocontrol")

local core      = require("graphics.core")

local Div       = require("graphics.elements.div")
local TextBox   = require("graphics.elements.textbox")

-- create placeholder app page
---@param root graphics_element parent
local function create_pages(root)
    local db = iocontrol.get_db()

    local main = Div{parent=root,x=1,y=1}

    db.nav.register_app(iocontrol.APP_ID.DUMMY, main).new_page(nil, function () end)

    TextBox{parent=main,text="This app is not implemented yet.",x=1,y=2,alignment=core.ALIGN.CENTER}

    TextBox{parent=main,text=" pretend something  cool is here \x03",x=1,y=10,alignment=core.ALIGN.CENTER,fg_bg=core.cpair(colors.gray,colors.black)}
end

return create_pages
