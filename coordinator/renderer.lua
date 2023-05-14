--
-- Graphics Rendering Control
--

local log        = require("scada-common.log")
local util       = require("scada-common.util")

local style      = require("coordinator.ui.style")

local main_view  = require("coordinator.ui.layout.main_view")
local unit_view  = require("coordinator.ui.layout.unit_view")

local flasher    = require("graphics.flasher")

local DisplayBox = require("graphics.elements.displaybox")

local renderer = {}

-- render engine
local engine = {
    monitors = nil,         ---@type monitors_struct|nil
    dmesg_window = nil,     ---@type table|nil
    ui_ready = false,
    ui = {
        main_display = nil, ---@type graphics_element|nil
        unit_displays = {}
    }
}

-- init a display to the "default", but set text scale to 0.5
---@param monitor table monitor
local function _init_display(monitor)
    monitor.setTextScale(0.5)
    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setCursorPos(1, 1)

    -- set overridden colors
    for i = 1, #style.colors do
        monitor.setPaletteColor(style.colors[i].c, style.colors[i].hex)
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
            for _, monitor in ipairs(engine.monitors.unit_displays) do
                if monitor == periph then return true end
            end
        end
    end

    return false
end

-- init all displays in use by the renderer
function renderer.init_displays()
    -- init primary monitor
    _init_display(engine.monitors.primary)

    -- init unit displays
    for _, monitor in ipairs(engine.monitors.unit_displays) do
        _init_display(monitor)
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

    for id, monitor in ipairs(engine.monitors.unit_displays) do
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
        engine.ui.main_display = DisplayBox{window=engine.monitors.primary,fg_bg=style.root}
        main_view(engine.ui.main_display)

        -- show unit views on unit displays
        for i = 1, #engine.monitors.unit_displays do
            engine.ui.unit_displays[i] = DisplayBox{window=engine.monitors.unit_displays[i],fg_bg=style.root}
            unit_view(engine.ui.unit_displays[i], i)
        end

        -- start flasher callback task
        flasher.run()

        -- report ui as ready
        engine.ui_ready = true
    end
end

-- close out the UI
function renderer.close_ui()
    -- stop blinking indicators
    flasher.clear()

    -- delete element trees
    if engine.ui.main_display ~= nil then engine.ui.main_display.delete() end
    for _, display in ipairs(engine.ui.unit_displays) do display.delete() end

    -- report ui as not ready
    engine.ui_ready = false

    -- clear root UI elements
    engine.ui.main_display = nil
    engine.ui.unit_displays = {}

    -- clear unit monitors
    for _, monitor in ipairs(engine.monitors.unit_displays) do monitor.clear() end

    -- re-draw dmesg
    engine.dmesg_window.setVisible(true)
    engine.dmesg_window.redraw()
end

-- is the UI ready?
---@nodiscard
---@return boolean ready
function renderer.ui_ready() return engine.ui_ready end

-- handle a touch event
---@param event mouse_interaction|nil
function renderer.handle_mouse(event)
    if engine.ui_ready and event ~= nil then
        if event.monitor == engine.monitors.primary_name then
            engine.ui.main_display.handle_mouse(event)
        else
            for id, monitor in ipairs(engine.monitors.unit_name_map) do
                if event.monitor == monitor then
                    local layout = engine.ui.unit_displays[id]  ---@type graphics_element
                    layout.handle_mouse(event)
                end
            end
        end
    end
end

return renderer
