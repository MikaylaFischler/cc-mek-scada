

local flasher = require("graphics.flasher")
local core    = require("graphics.core")

local graphics = {}

graphics.flasher = flasher

-- pass mouse events to graphics engine
-- supports: mouse_click, mouse_up, mouse_drag, mouse_scroll, and monitor_touch
---@param event_type os_event
function graphics.handle_mouse(event_type)
    if event_type == "mouse_click" then
    elseif event_type == "mouse_up" or event_type == "monitor_touch" then
    elseif event_type == "mouse_drag" then
    elseif event_type == "mouse_scroll" then
    end
end

-- pass char, key, or key_up event to graphics engine
---@param event_type os_event
function graphics.handle_key(event_type)
    if event_type == "char" then
    elseif event_type == "key" then
    elseif event_type == "key_up" then
    end
end

return graphics
