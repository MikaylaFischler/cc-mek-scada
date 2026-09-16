--
-- Flow Monitor Boilers Detail View
--

local ioctl       = require("coordinator.ioctl")

local boiler      = require("coordinator.ui.components.flow.boiler")
local make_window = require("coordinator.ui.components.flow.window")

local Div         = require("graphics.elements.Div")

-- make a new boilers detail window
---@param parent Container parent
---@param unit_id integer unit index
---@param close_cb function window close callback
local function make(parent, unit_id, close_cb)
    local db   = ioctl.get_db()
    local unit = db.units[unit_id]

    if unit.num_boilers > 0 then
        local height = 3 + (28 * unit.num_boilers)

        local window = make_window(parent, 141, height, "Thermoelectric Sodium Boiler Details - Unit "..unit_id, close_cb)

        for b = 1, unit.num_boilers do
            local frame = Div{parent=window,x=1,y=1+((b-1)*28),height=28}
            boiler(frame, unit, b)
        end
    end
end

return make
