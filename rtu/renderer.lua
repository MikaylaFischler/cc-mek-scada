--
-- Graphics Rendering Control
--

local panel_view = require("rtu.panel.front_panel")
local style      = require("rtu.panel.style")

local flasher    = require("graphics.flasher")

local DisplayBox = require("graphics.elements.displaybox")

local renderer = {}

local ui = {
    display = nil
}

-- start the UI
---@param units table RTU units
function renderer.start_ui(units)
    if ui.display == nil then
        -- reset terminal
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)

        -- set overridden colors
        for i = 1, #style.colors do
            term.setPaletteColor(style.colors[i].c, style.colors[i].hex)
        end

        -- start flasher callback task
        flasher.run()

        -- init front panel view
        ui.display = DisplayBox{window=term.current(),fg_bg=style.root}
        panel_view(ui.display, units)
    end
end

-- close out the UI
function renderer.close_ui()
    if ui.display ~= nil then
        -- stop blinking indicators
        flasher.clear()

        -- hide to stop animation callbacks
        ui.display.hide()

        -- clear root UI elements
        ui.display = nil

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
