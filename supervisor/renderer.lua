--
-- Graphics Rendering Control
--

local panel_view = require("supervisor.panel.front_panel")
local pgi        = require("supervisor.panel.pgi")
local style      = require("supervisor.panel.style")

local core       = require("graphics.core")
local flasher    = require("graphics.flasher")

local DisplayBox = require("graphics.elements.displaybox")

---@class supervisor_renderer
local renderer = {}

local ui = {
    display = nil
}

-- try to start the UI
---@return boolean success, any error_msg
function renderer.try_start_ui()
    local status, msg = true, nil

    if ui.display == nil then
        -- reset terminal
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)

        -- set overridden colors
        for i = 1, #style.theme.colors do
            term.setPaletteColor(style.theme.colors[i].c, style.theme.colors[i].hex)
        end

        -- init front panel view
        status, msg = pcall(function ()
            ui.display = DisplayBox{window=term.current(),fg_bg=style.fp.root}
            panel_view(ui.display)
        end)

        if status then
            -- start flasher callback task
            flasher.run()
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
    if ui.display ~= nil then
        -- stop blinking indicators
        flasher.clear()

        -- disable PGI
        pgi.unlink()

        -- hide to stop animation callbacks
        ui.display.hide()

        -- clear root UI elements
        ui.display = nil

        -- restore colors
        for i = 1, #style.theme.colors do
            local r, g, b = term.nativePaletteColor(style.theme.colors[i].c)
            term.setPaletteColor(style.theme.colors[i].c, r, g, b)
        end

        -- reset terminal
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
    end
end

-- is the UI ready?
---@nodiscard
---@return boolean ready
function renderer.ui_ready() return ui.display ~= nil end

-- handle a mouse event
---@param event mouse_interaction|nil
function renderer.handle_mouse(event)
    if ui.display ~= nil and event ~= nil then
        ui.display.handle_mouse(event)
    end
end

return renderer
