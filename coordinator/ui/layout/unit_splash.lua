--
-- Unit Display Splash Screen
--

local ioctl   = require("coordinator.ioctl")

local core    = require("graphics.core")

local TextBox = require("graphics.elements.TextBox")

local Waiting = require("graphics.elements.animations.Waiting")

local ALIGN = core.ALIGN

local cpair = core.cpair

-- create new unit splash screen
---@param main DisplayBox unit displaybox
local function init(main)
    local ps = ioctl.get_db().os_ps

    local mid_x, mid_y = math.floor(main.get_width() / 2), math.floor(main.get_height() / 2)

    Waiting{parent=main,x=mid_x-2,y=mid_y-4,fg_bg=cpair(colors.white,colors._INHERIT)}

    local status = TextBox{parent=main,x=mid_x-15,y=mid_y+2,width=30,text="Waiting...",alignment=ALIGN.CENTER}

    status.register(ps, "splash_status_flow", status.set_value)
end

return init
