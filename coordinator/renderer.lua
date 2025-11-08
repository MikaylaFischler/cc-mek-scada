--
-- Graphics Rendering Control
--

local log         = require("scada-common.log")
local util        = require("scada-common.util")

local coordinator = require("coordinator.coordinator")
local iocontrol   = require("coordinator.iocontrol")

local style       = require("coordinator.ui.style")
local pgi         = require("coordinator.ui.pgi")

local flow_view   = require("coordinator.ui.layout.flow_view")
local panel_view  = require("coordinator.ui.layout.front_panel")
local main_view   = require("coordinator.ui.layout.main_view")
local unit_view   = require("coordinator.ui.layout.unit_view")

local core        = require("graphics.core")
local flasher     = require("graphics.flasher")

local DisplayBox  = require("graphics.elements.DisplayBox")

local log_render = coordinator.log_render

---@class coord_renderer
local renderer = {}

-- render engine
local engine = {
    color_mode = 1,         ---@type COLOR_MODE
    monitors = nil,         ---@type crd_displays|nil
    dmesg_window = nil,     ---@type Window|nil
    ui_ready = false,
    fp_ready = false,
    ui = {
        front_panel = nil,  ---@type DisplayBox|nil
        main_display = nil, ---@type DisplayBox|nil
        flow_display = nil, ---@type DisplayBox|nil
        unit_displays = {}  ---@type (DisplayBox|nil)[]
    },
    disable_flow_view = false
}

-- init a display to the "default", but set text scale to 0.5
---@param monitor Monitor monitor
local function _init_display(monitor)
    monitor.setTextScale(0.5)
    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setCursorPos(1, 1)

    -- set overridden colors
    for i = 1, #style.theme.colors do
        monitor.setPaletteColor(style.theme.colors[i].c, style.theme.colors[i].hex)
    end

    -- apply color mode
    local c_mode_overrides = style.theme.color_modes[engine.color_mode]
    for i = 1, #c_mode_overrides do
        monitor.setPaletteColor(c_mode_overrides[i].c, c_mode_overrides[i].hex)
    end
end

-- print out that the monitor is too small
---@param monitor Monitor monitor
local function _print_too_small(monitor)
    monitor.setCursorPos(1, 1)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.red)
    monitor.clear()
    monitor.write("monitor too small")
end

-- apply renderer configurations
---@param config crd_config
function renderer.configure(config)
    style.set_themes(config.MainTheme, config.FrontPanelTheme, config.ColorMode)

    engine.color_mode = config.ColorMode
    engine.disable_flow_view = config.DisableFlowView
end

-- init all displays in use by the renderer
---@param monitors crd_displays
function renderer.init_displays(monitors)
    engine.monitors = monitors

    -- init main and flow monitors
    _init_display(engine.monitors.main)
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
    for i = 1, #style.fp_theme.colors do
        term.setPaletteColor(style.fp_theme.colors[i].c, style.fp_theme.colors[i].hex)
    end

    -- apply color mode
    local c_mode_overrides = style.fp_theme.color_modes[engine.color_mode]
    for i = 1, #c_mode_overrides do
        term.setPaletteColor(c_mode_overrides[i].c, c_mode_overrides[i].hex)
    end
end

-- initialize the dmesg output window
function renderer.init_dmesg()
    local disp_w, disp_h = engine.monitors.main.getSize()
    engine.dmesg_window = window.create(engine.monitors.main, 1, 1, disp_w, disp_h)
    log.direct_dmesg(engine.dmesg_window)
end

-- try to start the front panel
---@return boolean success, any error_msg
function renderer.try_start_fp()
    local status, msg = true, nil

    if not engine.fp_ready then
        -- show front panel view on terminal
        status, msg = pcall(function ()
            engine.ui.front_panel = DisplayBox{window=term.current(),fg_bg=style.fp.root}
            panel_view(engine.ui.front_panel, #engine.monitors.unit_displays)
        end)

        if status then
            -- start flasher callback task and report ready
            flasher.run()
            engine.fp_ready = true
        else
            -- report fail and close front panel
            msg = core.extract_assert_msg(msg)
            renderer.close_fp()
        end
    end

    return status, msg
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
        for i = 1, #style.fp_theme.colors do
            local r, g, b = term.nativePaletteColor(style.fp_theme.colors[i].c)
            term.setPaletteColor(style.fp_theme.colors[i].c, r, g, b)
        end

        -- reset terminal
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
    end
end

-- try to start the main GUI
---@return boolean success, any error_msg
function renderer.try_start_ui()
    local status, msg = true, nil

    if not engine.ui_ready then
        -- hide dmesg
        engine.dmesg_window.setVisible(false)

        status, msg = pcall(function ()
            -- show main view on main monitor
            if engine.monitors.main ~= nil then
                engine.ui.main_display = DisplayBox{window=engine.monitors.main,fg_bg=style.root}
                main_view(engine.ui.main_display)
                iocontrol.fp_monitor_state("main", 3)
                util.nop()
            end

            -- show flow view on flow monitor
            if engine.monitors.flow ~= nil then
                engine.ui.flow_display = DisplayBox{window=engine.monitors.flow,fg_bg=style.root}
                flow_view(engine.ui.flow_display)
                iocontrol.fp_monitor_state("flow", 3)
                util.nop()
            end

            -- show unit views on unit displays
            for idx, display in pairs(engine.monitors.unit_displays) do
                engine.ui.unit_displays[idx] = DisplayBox{window=display,fg_bg=style.root}
                unit_view(engine.ui.unit_displays[idx], idx)
                iocontrol.fp_monitor_state(idx, 3)
                util.nop()
            end
        end)

        if status then
            -- start flasher callback task and report ready
            flasher.run()
            engine.ui_ready = true
        else
            -- report fail and close ui
            msg = core.extract_assert_msg(msg)
            renderer.close_ui()
        end
    end

    return status, msg
end

-- close out the UI
function renderer.close_ui()
    if not engine.fp_ready then
        -- stop blinking indicators
        flasher.clear()
    end

    -- delete element trees

    if engine.ui.main_display ~= nil then
        engine.ui.main_display.delete()
        iocontrol.fp_monitor_state("main", 2)
    end

    if engine.ui.flow_display ~= nil then
        engine.ui.flow_display.delete()
        iocontrol.fp_monitor_state("flow", 2)
    end

    for idx, display in pairs(engine.ui.unit_displays) do
        display.delete()
        iocontrol.fp_monitor_state(idx, 2)
    end

    -- report ui as not ready
    engine.ui_ready = false

    -- clear root UI elements
    engine.ui.main_display = nil
    engine.ui.flow_display = nil
    engine.ui.unit_displays = {}

    -- clear unit monitors
    for _, monitor in ipairs(engine.monitors.unit_displays) do monitor.clear() end

    if not engine.disable_flow_view then
        -- clear flow monitor
        engine.monitors.flow.clear()
    end

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
---@param iface string monitor interface
function renderer.handle_disconnect(iface)
    if not engine.monitors then return false end

    if engine.monitors.main_iface == iface then
        if engine.ui.main_display ~= nil then
            -- delete element tree and clear root UI elements
            engine.ui.main_display.delete()
            log_render("closed main view due to monitor disconnect")
        end

        engine.monitors.main = nil
        engine.ui.main_display = nil
    elseif engine.monitors.flow_iface == iface then
        if engine.ui.flow_display ~= nil then
            -- delete element tree and clear root UI elements
            engine.ui.flow_display.delete()
            log_render("closed flow view due to monitor disconnect")
        end

        engine.monitors.flow = nil
        engine.ui.flow_display = nil
    else
        for idx, u_iface in pairs(engine.monitors.unit_ifaces) do
            if u_iface == iface then
                if engine.ui.unit_displays[idx] ~= nil then
                    -- delete element tree and clear root UI elements
                    engine.ui.unit_displays[idx].delete()
                    log_render("closed unit" .. idx .. "view due to monitor disconnect")
                end

                engine.monitors.unit_displays[idx] = nil
                engine.ui.unit_displays[idx] = nil
                break
            end
        end
    end
end

-- handle a monitor peripheral being reconnected
---@param name string monitor name
function renderer.handle_reconnect(name)
    -- note: handle_resize is a more adaptive way of re-initializing a connected monitor
    --       since it can handle a monitor being reconnected that isn't the right size
    renderer.handle_resize(name)
end

-- handle a monitor being resized<br>
-- returns if this monitor is assigned + if the assigned screen still fits
---@param name string monitor name
---@return boolean is_used, boolean is_ok
function renderer.handle_resize(name)
    local is_used = false
    local is_ok = true
    local ui = engine.ui

    if not engine.monitors then return false, false end

    if engine.monitors.main_iface == name and engine.monitors.main then
        local device = engine.monitors.main  ---@type Monitor

        -- this is necessary if the bottom left block was broken and on reconnect
        _init_display(device)

        is_used = true

        -- resize dmesg window if needed, but don't make it thinner
        local disp_w, disp_h = engine.monitors.main.getSize()
        local dmsg_w, _ = engine.dmesg_window.getSize()
        engine.dmesg_window.reposition(1, 1, math.max(disp_w, dmsg_w), disp_h, engine.monitors.main)

        if ui.main_display then
            ui.main_display.delete()
            ui.main_display = nil
        end

        iocontrol.fp_monitor_state("main", 2)

        engine.dmesg_window.setVisible(not engine.ui_ready)

        if engine.ui_ready then
            local draw_start = util.time_ms()
            local ok = pcall(function ()
                ui.main_display = DisplayBox{window=device,fg_bg=style.root}
                main_view(ui.main_display)
            end)

            if ok then
                iocontrol.fp_monitor_state("main", 3)

                log_render("main view re-draw completed in " .. (util.time_ms() - draw_start) .. "ms")
            else
                if ui.main_display then
                    ui.main_display.delete()
                    ui.main_display = nil
                end

                _print_too_small(device)

                is_ok = false
            end
        else engine.dmesg_window.redraw() end
    elseif engine.monitors.flow_iface == name and engine.monitors.flow then
        local device = engine.monitors.flow ---@type Monitor

        -- this is necessary if the bottom left block was broken and on reconnect
        _init_display(device)

        is_used = true

        if ui.flow_display then
            ui.flow_display.delete()
            ui.flow_display = nil
        end

        iocontrol.fp_monitor_state("flow", 2)

        if engine.ui_ready then
            local draw_start = util.time_ms()
            local ok = pcall(function ()
                ui.flow_display = DisplayBox{window=device,fg_bg=style.root}
                flow_view(ui.flow_display)
            end)

            if ok then
                iocontrol.fp_monitor_state("flow", 3)

                log_render("flow view re-draw completed in " .. (util.time_ms() - draw_start) .. "ms")
            else
                if ui.flow_display then
                    ui.flow_display.delete()
                    ui.flow_display = nil
                end

                _print_too_small(device)

                is_ok = false
            end
        end
    else
        for idx, monitor in ipairs(engine.monitors.unit_ifaces) do
            local device = engine.monitors.unit_displays[idx]

            if monitor == name and device then
                -- this is necessary if the bottom left block was broken and on reconnect
                _init_display(device)

                is_used = true

                if ui.unit_displays[idx] then
                    ui.unit_displays[idx].delete()
                    ui.unit_displays[idx] = nil
                end

                iocontrol.fp_monitor_state(idx, 2)

                if engine.ui_ready then
                    local draw_start = util.time_ms()
                    local ok = pcall(function ()
                        ui.unit_displays[idx] = DisplayBox{window=device,fg_bg=style.root}
                        unit_view(ui.unit_displays[idx], idx)
                    end)

                    if ok then
                        iocontrol.fp_monitor_state(idx, 3)

                        log_render("unit " .. idx .. " view re-draw completed in " .. (util.time_ms() - draw_start) .. "ms")
                    else
                        if ui.unit_displays[idx] then
                            ui.unit_displays[idx].delete()
                            ui.unit_displays[idx] = nil
                        end

                        _print_too_small(device)

                        is_ok = false
                    end
                end

                break
            end
        end
    end

    return is_used, is_ok
end

-- handle a touch event
---@param event mouse_interaction|nil
function renderer.handle_mouse(event)
    if event ~= nil then
        if engine.fp_ready and event.monitor == "terminal" then
            engine.ui.front_panel.handle_mouse(event)
        elseif engine.ui_ready then
            if event.monitor == engine.monitors.main_iface then
                if engine.ui.main_display then engine.ui.main_display.handle_mouse(event) end
            elseif event.monitor == engine.monitors.flow_iface then
                if engine.ui.flow_display then engine.ui.flow_display.handle_mouse(event) end
            else
                for id, monitor in ipairs(engine.monitors.unit_ifaces) do
                    local display = engine.ui.unit_displays[id]
                    if event.monitor == monitor and display then
                        if display then display.handle_mouse(event) end
                    end
                end
            end
        end
    end
end

return renderer
