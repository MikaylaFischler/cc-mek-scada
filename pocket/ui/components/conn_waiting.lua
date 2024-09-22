--
-- Connection Waiting Spinner
--

local iocontrol   = require("pocket.iocontrol")

local style       = require("pocket.ui.style")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local TextBox     = require("graphics.elements.TextBox")

local WaitingAnim = require("graphics.elements.animations.Waiting")

local ALIGN = core.ALIGN

local cpair = core.cpair

-- create a waiting view
---@param parent graphics_element parent
---@param y integer y offset
local function init(parent, y, is_api)
    -- root div
    local root = Div{parent=parent,x=1,y=1}

    -- bounding box div
    local box = Div{parent=root,x=1,y=y,height=12}

    local waiting_x = math.floor(parent.get_width() / 2) - 1

    local msg = TextBox{parent=box,x=3,y=11,width=box.get_width()-4,height=2,text="",alignment=ALIGN.CENTER,fg_bg=cpair(colors.red,style.root.bkg)}

    if is_api then
        WaitingAnim{parent=box,x=waiting_x,y=1,fg_bg=cpair(colors.blue,style.root.bkg)}
        TextBox{parent=box,y=5,text="Connecting to API",alignment=ALIGN.CENTER,fg_bg=cpair(colors.white,style.root.bkg)}
        msg.register(iocontrol.get_db().ps, "api_link_msg", msg.set_value)
    else
        WaitingAnim{parent=box,x=waiting_x,y=1,fg_bg=cpair(colors.green,style.root.bkg)}
        TextBox{parent=box,y=5,text="Connecting to Supervisor",alignment=ALIGN.CENTER,fg_bg=cpair(colors.white,style.root.bkg)}
        msg.register(iocontrol.get_db().ps, "svr_link_msg", msg.set_value)
    end

    return root
end

return init
