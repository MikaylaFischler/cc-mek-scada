--
-- Main Display Splash Screen
--

local ioctl   = require("coordinator.ioctl")

local core    = require("graphics.core")

local Image   = require("graphics.elements.Image")
local TextBox = require("graphics.elements.TextBox")

local Waiting = require("graphics.elements.animations.Waiting")

local ALIGN = core.ALIGN

local cpair = core.cpair

-- create new main splash screen
---@param main DisplayBox main displaybox
local function init(main)
    local ps = ioctl.get_db().os_ps

    local mid_x, mid_y = math.floor(main.get_width() / 2), math.floor(main.get_height() / 2)

    Image{parent=main,x=mid_x-14,y=mid_y-20,nfp="/coordinator/ui/imgs/cc-mek-scada.nfp"}

    Waiting{parent=main,x=mid_x-2,y=mid_y+10,fg_bg=cpair(colors.white,colors._INHERIT)}

    local status_1 = TextBox{parent=main,x=mid_x-15,y=mid_y+15,width=30,text="Starting up SCADA System",alignment=ALIGN.CENTER}
    local status_2 = TextBox{parent=main,x=mid_x-15,y=mid_y+17,width=30,text="initializing core...",alignment=ALIGN.CENTER}

    status_1.register(ps, "splash_status_1", status_1.set_value)
    status_2.register(ps, "splash_status_2", status_2.set_value)
end

return init
