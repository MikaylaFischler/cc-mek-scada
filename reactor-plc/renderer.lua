--
-- Graphics Rendering Control
--

local style      = require("reactor-plc.panel.style")
local panel_view = require("reactor-plc.panel.front_panel")

local renderer = {}

local ui = {
    view = nil
}

-- start the UI
function renderer.start_ui()
    if ui.view == nil then
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)

        -- set overridden colors
        for i = 1, #style.colors do
            term.setPaletteColor(style.colors[i].c, style.colors[i].hex)
        end

        -- init front panel view
        ui.view = panel_view(term.current())
    end
end

-- close out the UI
function renderer.close_ui()
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

    term.clear()
end

-- is the UI ready?
---@nodiscard
---@return boolean ready
function renderer.ui_ready() return ui.view ~= nil end

-- handle a touch event
---@param event monitor_touch
function renderer.handle_touch(event)
    ui.view.handle_touch(event)
end

return renderer
