--
-- Graphics Rendering Control
--

local main_view  = require("pocket.ui.main")
local style      = require("pocket.ui.style")

local core       = require("graphics.core")
local flasher    = require("graphics.flasher")

local DisplayBox = require("graphics.elements.displaybox")

---@class pocket_renderer
local renderer = {}

local ui = {
    display = nil
}

-- try to start the pocket GUI
---@return boolean success, any error_msg
function renderer.try_start_ui()
    local status, msg = true, nil

    if ui.display == nil then
        -- reset screen
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)

        -- set overridden colors
        for i = 1, #style.colors do
            term.setPaletteColor(style.colors[i].c, style.colors[i].hex)
        end

        -- init front panel view
        status, msg = pcall(function ()
            ui.display = DisplayBox{window=term.current(),fg_bg=style.root}
            main_view(ui.display)
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
