--
-- Unit Overview Page
--

local iocontrol = require("pocket.iocontrol")

local core      = require("graphics.core")

local Div       = require("graphics.elements.div")
local TextBox   = require("graphics.elements.textbox")

local ALIGN = core.ALIGN

-- new unit page view
---@param root graphics_element parent
local function new_view(root)
    local db = iocontrol.get_db()

    local main = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(iocontrol.APP_ID.UNITS, main)
    app.new_page(nil, function () end)

    TextBox{parent=main,text="UNITS",x=1,y=1,height=1,alignment=ALIGN.CENTER}

    return main
end

return new_view
