--
-- Boiler Detail Page
--

local iocontrol = require("pocket.iocontrol")

local core      = require("graphics.core")

local Div       = require("graphics.elements.div")
local TextBox   = require("graphics.elements.textbox")

local ALIGN = core.ALIGN

-- new boiler page view
---@param root graphics_element parent
local function new_view(root)
    local db = iocontrol.get_db()

    db.nav.new_page(nil, 4)

    local main = Div{parent=root,x=1,y=1}

    TextBox{parent=main,text="BOILERS",x=1,y=1,height=1,alignment=ALIGN.CENTER}

    return main
end

return new_view
