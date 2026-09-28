--
-- Flow Display Splash Screen
--

local ioctl   = require("coordinator.ioctl")

local style   = require("coordinator.ui.style")

local core    = require("graphics.core")

local Image   = require("graphics.elements.Image")
local TextBox = require("graphics.elements.TextBox")

local Waiting = require("graphics.elements.animations.Waiting")

local ALIGN = core.ALIGN

-- create new flow splash screen
---@param main DisplayBox flow displaybox
local function init(main)
    local ps = ioctl.get_db().os_ps

    local mid_x, mid_y = math.floor(main.get_width() / 2), math.floor(main.get_height() / 2)

    local variant = (style.theme.text == colors.black) and "light.nfp" or "dark.nfp"

    Image{parent=main,x=mid_x-14,y=mid_y-20,nfp="/coordinator/ui/imgs/cc-mek-scada_"..variant}

    Waiting{parent=main,x=mid_x-2,y=mid_y+10}

    local status = TextBox{parent=main,x=mid_x-15,y=mid_y+15,width=30,text="Waiting...",alignment=ALIGN.CENTER}

    status.register(ps, "splash_status_flow", status.set_value)
end

return init
