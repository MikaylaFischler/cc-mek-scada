--
-- Graphics Rendering Control
--

local main_view = require("pocket.ui.main")
local style     = require("pocket.ui.style")

local flasher   = require("graphics.flasher")

local renderer = {}

local ui = {
    view = nil
}

-- start the coordinator GUI
function renderer.start_ui()
    if ui.view == nil then
        -- reset screen
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
        ui.view = main_view(term.current())
    end
end

-- close out the UI
function renderer.close_ui()
    -- stop blinking indicators
    flasher.clear()

    if ui.view ~= nil then
        -- hide to stop animation callbacks
        ui.view.hide()
    end

    -- clear root UI elements
    ui.view = nil

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

-- is the UI ready?
---@nodiscard
---@return boolean ready
function renderer.ui_ready() return ui.view ~= nil end

-- handle a mouse event
---@param event mouse_interaction
function renderer.handle_mouse(event)
    ui.view.handle_mouse(event)
end

return renderer
