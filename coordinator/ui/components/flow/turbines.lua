--
-- Flow Monitor Turbines Detail View
--

local ioctl      = require("coordinator.ioctl")

local turbine    = require("coordinator.ui.components.flow.turbine")

local core       = require("graphics.core")

local Div        = require("graphics.elements.Div")
local TextBox    = require("graphics.elements.TextBox")

local Rectangle  = require("graphics.elements.Rectangle")

local PushButton = require("graphics.elements.controls.PushButton")

local border = core.border
local cpair = core.cpair

local gray = colors.gray

-- make a new reactor detail window
---@param parent Container parent
---@param unit_id integer unit index
---@param close_cb function window close callback
local function make(parent, unit_id, close_cb)
    local db   = ioctl.get_db()
    local unit = db.units[unit_id]

    -- bounding box div
    local root = Div{parent=parent,x=math.floor((parent.get_width()-141)/2),y=1,width=141,height=3+(25*unit.num_turbines)}

    local s = (unit.num_turbines > 1) and "s" or ""

    TextBox{parent=root,x=1,y=1,height=1,text=string.rep("\x8f",138),fg_bg=cpair(parent.get_fg_bg().bkg,gray)}
    TextBox{parent=root,x=1,y=2,text=" Steam Turbine Generator"..s.." Details - Unit "..unit_id,fg_bg=cpair(colors.white,gray)}

    PushButton{parent=root,x=139,y=1,min_width=3,text="\x8f\x8f\x8f",fg_bg=cpair(parent.get_fg_bg().bkg,colors.red),callback=close_cb}
    PushButton{parent=root,x=139,y=2,min_width=3,text="\xd7",fg_bg=cpair(colors.white,colors.red),callback=close_cb}

    local window = Rectangle{parent=root,x=1,y=3,border=border(1,gray,true),fg_bg=parent.get_fg_bg()}

    for t = 1, unit.num_turbines do
        local frame = Div{parent=window,x=1,y=1+((t-1)*25),height=24}
        turbine(frame, unit, t)
    end

    return root
end

return make
