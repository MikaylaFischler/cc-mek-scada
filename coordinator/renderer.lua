local log = require("scada-common.log")
local util = require("scada-common.util")

local renderer = {}

local engine = {
    monitors = nil,
    dmesg_window = nil
}

---@param monitors monitors_struct
function renderer.set_displays(monitors)
    engine.monitors = monitors
end

function renderer.reset()
    -- reset primary monitor
    engine.monitors.primary.setTextScale(0.5)
    engine.monitors.primary.setTextColor(colors.white)
    engine.monitors.primary.setBackgroundColor(colors.black)
    engine.monitors.primary.clear()
    engine.monitors.primary.setCursorPos(1, 1)

    -- reset unit displays
    for _, monitor in pairs(engine.monitors.unit_displays) do
        monitor.setTextScale(0.5)
        monitor.setTextColor(colors.white)
        monitor.setBackgroundColor(colors.black)
        monitor.clear()
        monitor.setCursorPos(1, 1)
    end
end

function renderer.init_dmesg()
    local disp_x, disp_y = engine.monitors.primary.getSize()
    engine.dmesg_window = window.create(engine.monitors.primary, 1, 1, disp_x, disp_y)

    log.direct_dmesg(engine.dmesg_window)
end

return renderer
