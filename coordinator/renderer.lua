local log  = require("scada-common.log")
local util = require("scada-common.util")

local core = require("graphics.core")

local main_layout = require("coordinator.ui.main_layout")
local unit_layout = require("coordinator.ui.unit_layout")

local renderer = {}

-- render engine
local engine = {
    monitors = nil,
    dmesg_window = nil
}

-- UI layouts
local ui = {
    main_layout = nil,
    unit_layouts = {}
}

-- reset a display to the "default", but set text scale to 0.5
local function _reset_display(monitor)
    monitor.setTextScale(0.5)
    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setCursorPos(1, 1)
end

-- link to the monitor peripherals
---@param monitors monitors_struct
function renderer.set_displays(monitors)
    engine.monitors = monitors
end

-- reset all displays in use by the renderer
function renderer.reset()
    -- reset primary monitor
    _reset_display(engine.monitors.primary)

    -- reset unit displays
    for _, monitor in pairs(engine.monitors.unit_displays) do
        _reset_display(monitor)
    end
end

-- initialize the dmesg output window
function renderer.init_dmesg()
    local disp_x, disp_y = engine.monitors.primary.getSize()
    engine.dmesg_window = window.create(engine.monitors.primary, 1, 1, disp_x, disp_y)

    log.direct_dmesg(engine.dmesg_window)
end

-- start the coordinator GUI
function renderer.start_ui()
    ui.main_layout = main_layout(engine.monitors.primary)

    for id, monitor in pairs(engine.monitors.unit_displays) do
        table.insert(ui.unit_layouts, unit_layout(monitor, id))
    end
end

-- close out the UI
function renderer.close_ui()
    -- clear root UI elements
    ui.main_layout = nil
    ui.unit_layouts = {}

    -- reset displays
    renderer.reset()

    -- re-draw dmesg
    engine.dmesg_window.redraw()
end

return renderer
