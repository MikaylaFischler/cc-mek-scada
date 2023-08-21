--
-- Graphics Rendering Control
--

local log        = require("scada-common.log")
local util       = require("scada-common.util")

local iocontrol  = require("coordinator.iocontrol")

local style      = require("coordinator.ui.style")
local pgi        = require("coordinator.ui.pgi")

local flow_view  = require("coordinator.ui.layout.flow_view")
local panel_view = require("coordinator.ui.layout.front_panel")
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
    fp_ready = false,
    ui = {
        front_panel = nil,  ---@type graphics_element|nil
        main_display = nil, ---@type graphics_element|nil
        flow_display = nil, ---@type graphics_element|nil
        unit_displays = {}
    },
    disable_flow_view = false
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

-- disable the flow view
---@param disable boolean
function renderer.legacy_disable_flow_view(disable)
    engine.disable_flow_view = disable
end

-- link to the monitor peripherals
---@param monitors monitors_struct
function renderer.set_displays(monitors)
    engine.monitors = monitors

    -- report to front panel as connected
    iocontrol.fp_monitor_state("main", engine.monitors.primary ~= nil)
    iocontrol.fp_monitor_state("flow", engine.monitors.flow ~= nil)
    for i = 1, #engine.monitors.unit_displays do iocontrol.fp_monitor_state(i, true) end
end

-- init all displays in use by the renderer
function renderer.init_displays()
    -- init primary and flow monitors
    _init_display(engine.monitors.primary)
    if not engine.disable_flow_view then _init_display(engine.monitors.flow) end

    -- init unit displays
    for _, monitor in ipairs(engine.monitors.unit_displays) do
        _init_display(monitor)
    end

    -- init terminal
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)

    -- set overridden colors
    for i = 1, #style.fp.colors do
        term.setPaletteColor(style.fp.colors[i].c, style.fp.colors[i].hex)
    end
end

-- check main display width
---@nodiscard
---@return boolean width_okay
function renderer.validate_main_display_width()
    local w, _ = engine.monitors.primary.getSize()
    return w == 164
end

-- check flow display width
---@nodiscard
---@return boolean width_okay
function renderer.validate_flow_display_width()
    local w, _ = engine.monitors.flow.getSize()
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

-- start the coordinator front panel
function renderer.start_fp()
    if not engine.fp_ready then
        -- show front panel view on terminal
        engine.ui.front_panel = DisplayBox{window=term.native(),fg_bg=style.fp.root}
        panel_view(engine.ui.front_panel, #engine.monitors.unit_displays)

        -- start flasher callback task
        flasher.run()

        -- report front panel as ready
        engine.fp_ready = true
    end
end

-- close out the front panel
function renderer.close_fp()
    if engine.fp_ready then
        if not engine.ui_ready then
            -- stop blinking indicators
            flasher.clear()
        end

        -- disable PGI
        pgi.unlink()

        -- hide to stop animation callbacks and clear root UI elements
        engine.ui.front_panel.hide()
        engine.ui.front_panel = nil
        engine.fp_ready = false

        -- restore colors
        for i = 1, #style.colors do
            local r, g, b = term.nativePaletteColor(style.colors[i].c)
            term.setPaletteColor(style.colors[i].c, r, g, b)
        end

        -- reset terminal
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
    end
end

-- start the coordinator GUI
function renderer.start_ui()
    if not engine.ui_ready then
        -- hide dmesg
        engine.dmesg_window.setVisible(false)

        -- show main view on main monitor
        if engine.monitors.primary ~= nil then
            engine.ui.main_display = DisplayBox{window=engine.monitors.primary,fg_bg=style.root}
            main_view(engine.ui.main_display)
        end

        -- show flow view on flow monitor
        if engine.monitors.flow ~= nil then
            engine.ui.flow_display = DisplayBox{window=engine.monitors.flow,fg_bg=style.root}
            flow_view(engine.ui.flow_display)
        end

        -- show unit views on unit displays
        for idx, display in pairs(engine.monitors.unit_displays) do
            engine.ui.unit_displays[idx] = DisplayBox{window=display,fg_bg=style.root}
            unit_view(engine.ui.unit_displays[idx], idx)
        end

        -- start flasher callback task
        flasher.run()

        -- report ui as ready
        engine.ui_ready = true
    end
end

-- close out the UI
function renderer.close_ui()
    if not engine.fp_ready then
        -- stop blinking indicators
        flasher.clear()
    end

    -- delete element trees
    if engine.ui.main_display ~= nil then engine.ui.main_display.delete() end
    if engine.ui.flow_display ~= nil then engine.ui.flow_display.delete() end
    for _, display in pairs(engine.ui.unit_displays) do display.delete() end

    -- report ui as not ready
    engine.ui_ready = false

    -- clear root UI elements
    engine.ui.main_display = nil
    engine.ui.flow_display = nil
    engine.ui.unit_displays = {}

    -- clear unit monitors
    for _, monitor in ipairs(engine.monitors.unit_displays) do monitor.clear() end

    -- re-draw dmesg
    engine.dmesg_window.setVisible(true)
    engine.dmesg_window.redraw()
end

-- is the front panel ready?
---@nodiscard
---@return boolean ready
function renderer.fp_ready() return engine.fp_ready end

-- is the UI ready?
---@nodiscard
---@return boolean ready
function renderer.ui_ready() return engine.ui_ready end

-- handle a monitor peripheral being disconnected
---@param device table monitor
---@return boolean is_used if the monitor is one of the configured monitors
function renderer.handle_disconnect(device)
    local is_used = false

    if engine.monitors ~= nil then
        if engine.monitors.primary == device then
            if engine.ui.main_display ~= nil then
                -- delete element tree and clear root UI elements
                engine.ui.main_display.delete()
            end

            is_used = true
            engine.monitors.primary = nil
            engine.ui.main_display = nil

            iocontrol.fp_monitor_state("main", false)
        elseif engine.monitors.flow == device then
            if engine.ui.flow_display ~= nil then
                -- delete element tree and clear root UI elements
                engine.ui.flow_display.delete()
            end

            is_used = true
            engine.monitors.flow = nil
            engine.ui.flow_display = nil

            iocontrol.fp_monitor_state("flow", false)
        else
            for idx, monitor in pairs(engine.monitors.unit_displays) do
                if monitor == device then
                    if engine.ui.unit_displays[idx] ~= nil then
                        engine.ui.unit_displays[idx].delete()
                    end

                    is_used = true
                    engine.monitors.unit_displays[idx] = nil
                    engine.ui.unit_displays[idx] = nil

                    iocontrol.fp_monitor_state(idx, false)
                    break
                end
            end
        end
    end

    return is_used
end

-- handle a monitor peripheral being reconnected
---@param name string monitor name
---@param device table monitor
---@return boolean is_used if the monitor is one of the configured monitors
function renderer.handle_reconnect(name, device)
    local is_used = false

    if engine.monitors ~= nil then
        if engine.monitors.primary_name == name then
            is_used = true
            _init_display(device)
            engine.monitors.primary = device

            local disp_x, disp_y = engine.monitors.primary.getSize()
            engine.dmesg_window.reposition(1, 1, disp_x, disp_y, engine.monitors.primary)

            if engine.ui_ready and (engine.ui.main_display == nil) then
                engine.dmesg_window.setVisible(false)

                engine.ui.main_display = DisplayBox{window=device,fg_bg=style.root}
                main_view(engine.ui.main_display)
            else
                engine.dmesg_window.setVisible(true)
                engine.dmesg_window.redraw()
            end

            iocontrol.fp_monitor_state("main", true)
        elseif engine.monitors.flow_name == name then
            is_used = true
            _init_display(device)
            engine.monitors.flow = device

            if engine.ui_ready and (engine.ui.flow_display == nil) then
                engine.ui.flow_display = DisplayBox{window=device,fg_bg=style.root}
                flow_view(engine.ui.flow_display)
            end

            iocontrol.fp_monitor_state("flow", true)
        else
            for idx, monitor in ipairs(engine.monitors.unit_name_map) do
                if monitor == name then
                    is_used = true
                    _init_display(device)
                    engine.monitors.unit_displays[idx] = device

                    if engine.ui_ready and (engine.ui.unit_displays[idx] == nil) then
                        engine.ui.unit_displays[idx] = DisplayBox{window=device,fg_bg=style.root}
                        unit_view(engine.ui.unit_displays[idx], idx)
                    end

                    iocontrol.fp_monitor_state(idx, true)
                    break
                end
            end
        end
    end

    return is_used
end


-- handle a touch event
---@param event mouse_interaction|nil
function renderer.handle_mouse(event)
    if event ~= nil then
        if engine.fp_ready and event.monitor == "terminal" then
            engine.ui.front_panel.handle_mouse(event)
        elseif engine.ui_ready then
            if event.monitor == engine.monitors.primary_name then
                engine.ui.main_display.handle_mouse(event)
            elseif event.monitor == engine.monitors.flow_name then
                engine.ui.flow_display.handle_mouse(event)
            else
                for id, monitor in ipairs(engine.monitors.unit_name_map) do
                    if event.monitor == monitor then
                        local layout = engine.ui.unit_displays[id]  ---@type graphics_element
                        layout.handle_mouse(event)
                        break
                    end
                end
            end
        end
    end
end

return renderer
