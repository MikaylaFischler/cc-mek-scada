--
-- Main Display Splash Screen
--

local ioctl   = require("coordinator.ioctl")

local style   = require("coordinator.ui.style")

local core    = require("graphics.core")

local Image   = require("graphics.elements.Image")
local TextBox = require("graphics.elements.TextBox")

local Waiting = require("graphics.elements.animations.Waiting")

local ALIGN = core.ALIGN

-- create new main splash screen
---@param main DisplayBox main displaybox
local function init(main)
    local ps = ioctl.get_db().os_ps

    local mid_x, mid_y = math.floor(main.get_width() / 2), math.floor(main.get_height() / 2)

    local variant = (style.theme.text == colors.black) and "light.nfp" or "dark.nfp"

    Image{parent=main,x=mid_x-14,y=mid_y-20,nfp="/coordinator/ui/imgs/cc-mek-scada_"..variant}

    local anim = Waiting{parent=main,x=mid_x-2,y=mid_y+10}

    anim.register(ps, "splash_anim_clear", function () anim.delete() end)

    local status_1 = TextBox{parent=main,y=mid_y+15,text="Starting up the SCADA System",alignment=ALIGN.CENTER}
    local status_2 = TextBox{parent=main,y=mid_y+17,text="Initializing...",alignment=ALIGN.CENTER}

    status_1.register(ps, "splash_status_1", status_1.set_value)
    status_2.register(ps, "splash_status_2", status_2.set_value)
end

return init
