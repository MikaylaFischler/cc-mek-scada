--
-- Flow Monitor Turbines Detail View
--

local ioctl       = require("coordinator.ioctl")

local turbine     = require("coordinator.ui.components.flow.turbine")
local make_window = require("coordinator.ui.components.flow.window")

local Div         = require("graphics.elements.Div")

-- make a new turbines detail window
---@param parent Container parent
---@param unit_id integer unit index
---@param close_cb function window close callback
local function make(parent, unit_id, close_cb)
    local unit = ioctl.get_db().units[unit_id]

    local height = 3 + (25 * unit.num_turbines)

    local window = make_window(parent, 141, height, "Steam Turbine Generator Details - Unit "..unit_id, close_cb)

    for t = 1, unit.num_turbines do
        local frame = Div{parent=window,x=1,y=1+((t-1)*25),height=25}
        turbine(frame, unit, t)
    end
end

return make
