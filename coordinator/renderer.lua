--
-- Graphics Rendering Control
--

local log       = require("scada-common.log")
local util      = require("scada-common.util")

local style     = require("coordinator.ui.style")

local main_view = require("coordinator.ui.layout.main_view")
local unit_view = require("coordinator.ui.layout.unit_view")

local flasher   = require("graphics.flasher")

local renderer = {}

-- render engine
local engine = {
    monitors = nil,
    dmesg_window = nil,
    ui_ready = false
}

-- UI layouts
local ui = {
    main_layout = nil,
    unit_layouts = {}
}

-- reset a display to the "default", but set text scale to 0.5
---@param monitor table monitor
---@param recolor? boolean override default color palette
local function _reset_display(monitor, recolor)
    monitor.setTextScale(0.5)
    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setCursorPos(1, 1)

    if recolor then
        -- set overridden colors
        for i = 1, #style.colors do
            monitor.setPaletteColor(style.colors[i].c, style.colors[i].hex)
        end
    else
        -- reset all colors
        for _, val in pairs(colors) do
            -- colors api has constants and functions, just get color constants
            if type(val) == "number" then
                monitor.setPaletteColor(val, term.nativePaletteColor(val))
            end
        end
    end
end

-- link to the monitor peripherals
---@param monitors monitors_struct
function renderer.set_displays(monitors)
    engine.monitors = monitors
end

-- check if the renderer is configured to use a given monitor peripheral
---@nodiscard
---@param periph table peripheral
---@return boolean is_used
function renderer.is_monitor_used(periph)
    if engine.monitors ~= nil then
        if engine.monitors.primary == periph then
            return true
        else
            for i = 1, #engine.monitors.unit_displays do
                if engine.monitors.unit_displays[i] == periph then
                    return true
                end
            end
        end
    end

    return false
end

-- reset all displays in use by the renderer
---@param recolor? boolean true to use color palette from style
function renderer.reset(recolor)
    -- reset primary monitor
    _reset_display(engine.monitors.primary, recolor)

    -- reset unit displays
    for _, monitor in pairs(engine.monitors.unit_displays) do
        _reset_display(monitor, recolor)
    end
end

-- check main display width
---@nodiscard
---@return boolean width_okay
function renderer.validate_main_display_width()
    local w, _ = engine.monitors.primary.getSize()
    return w == 164
end

-- check display sizes
---@nodiscard
---@return boolean valid all unit display dimensions OK
function renderer.validate_unit_display_sizes()
    local valid = true

    for id, monitor in pairs(engine.monitors.unit_displays) do
        local w, h = monitor.getSize()
        if w ~= 79 or h ~= 52 then
            log.warning(util.c("RENDERER: unit ", id, " display resolution not 79 wide by 52 tall: ", w, ", ", h))
            valid = false
        end
    end

    return valid
end

-- initialize the dmesg output window
function renderer.init_dmesg()
    local disp_x, disp_y = engine.monitors.primary.getSize()
    engine.dmesg_window = window.create(engine.monitors.primary, 1, 1, disp_x, disp_y)

    log.direct_dmesg(engine.dmesg_window)
end

-- start the coordinator GUI
function renderer.start_ui()
    if not engine.ui_ready then
        -- hide dmesg
        engine.dmesg_window.setVisible(false)

        -- show main view on main monitor
        ui.main_layout = main_view(engine.monitors.primary)

        -- show unit views on unit displays
        for id, monitor in pairs(engine.monitors.unit_displays) do
            table.insert(ui.unit_layouts, unit_view(monitor, id))
        end

        -- start flasher callback task
        flasher.run()

        -- report ui as ready
        engine.ui_ready = true
    end
end

-- close out the UI
function renderer.close_ui()
    -- report ui as not ready
    engine.ui_ready = false

    -- stop blinking indicators
    flasher.clear()

    if engine.ui_ready then
        -- hide to stop animation callbacks
        ui.main_layout.hide()
        for i = 1, #ui.unit_layouts do
            ui.unit_layouts[i].hide()
            engine.monitors.unit_displays[i].clear()
        end
    else
        -- clear unit displays
        for i = 1, #ui.unit_layouts do
            engine.monitors.unit_displays[i].clear()
        end
    end

    -- clear root UI elements
    ui.main_layout = nil
    ui.unit_layouts = {}

    -- re-draw dmesg
    engine.dmesg_window.setVisible(true)
    engine.dmesg_window.redraw()
end

-- is the UI ready?
---@nodiscard
---@return boolean ready
function renderer.ui_ready() return engine.ui_ready end

-- handle a touch event
---@param event monitor_touch
function renderer.handle_touch(event)
    if event.monitor == engine.monitors.primary_name then
        ui.main_layout.handle_touch(event)
    else
        for id, monitor in pairs(engine.monitors.unit_name_map) do
            if event.monitor == monitor then
                local layout = ui.unit_layouts[id]  ---@type graphics_element
                layout.handle_touch(event)
            end
        end
    end
end

return renderer
