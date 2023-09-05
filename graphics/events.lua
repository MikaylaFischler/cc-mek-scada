--
-- Graphics Events and Event Handlers
--

local util = require("scada-common.util")

local events = {}

---@enum CLICK_BUTTON
events.CLICK_BUTTON = {
    GENERIC = 0,
    LEFT_BUTTON = 1,
    RIGHT_BUTTON = 2,
    MID_BUTTON = 3
}

---@enum CLICK_TYPE
events.CLICK_TYPE = {
    TAP = 1,            -- screen tap (complete click)
    DOWN = 2,           -- button down
    UP = 3,             -- button up (completed a click)
    DRAG = 4,           -- mouse dragged
    SCROLL_DOWN = 5,    -- scroll down
    SCROLL_UP = 6       -- scroll up
}

-- create a new 2D coordinate
---@param x integer
---@param y integer
---@return coordinate_2d
local function _coord2d(x, y) return { x = x, y = y } end

events.new_coord_2d = _coord2d

---@class mouse_interaction
---@field monitor string
---@field button CLICK_BUTTON
---@field type CLICK_TYPE
---@field initial coordinate_2d
---@field current coordinate_2d

local handler = {
    -- left, right, middle button down tracking
    button_down = { _coord2d(0, 0), _coord2d(0, 0), _coord2d(0, 0) }
}

-- create a new monitor touch mouse interaction event
---@nodiscard
---@param monitor string
---@param x integer
---@param y integer
---@return mouse_interaction
local function _monitor_touch(monitor, x, y)
    return {
        monitor = monitor,
        button = events.CLICK_BUTTON.GENERIC,
        type = events.CLICK_TYPE.TAP,
        initial = _coord2d(x, y),
        current = _coord2d(x, y)
    }
end

-- create a new mouse button mouse interaction event
---@nodiscard
---@param button CLICK_BUTTON mouse button
---@param type CLICK_TYPE click type
---@param x1 integer initial x
---@param y1 integer initial y
---@param x2 integer current x
---@param y2 integer current y
---@return mouse_interaction
local function _mouse_event(button, type, x1, y1, x2, y2)
    return {
        monitor = "terminal",
        button = button,
        type = type,
        initial = _coord2d(x1, y1),
        current = _coord2d(x2, y2)
    }
end

-- create a new generic mouse interaction event
---@nodiscard
---@param type CLICK_TYPE
---@param x integer
---@param y integer
---@return mouse_interaction
function events.mouse_generic(type, x, y)
    return {
        monitor = "",
        button = events.CLICK_BUTTON.GENERIC,
        type = type,
        initial = _coord2d(x, y),
        current = _coord2d(x, y)
    }
end

-- create a new transposed mouse interaction event using the event's monitor/button fields
---@nodiscard
---@param event mouse_interaction
---@param elem_pos_x integer element's x position: new x = (event x - element x) + 1
---@param elem_pos_y integer element's y position: new y = (event y - element y) + 1
---@return mouse_interaction
function events.mouse_transposed(event, elem_pos_x, elem_pos_y)
    return {
        monitor = event.monitor,
        button = event.button,
        type = event.type,
        initial = _coord2d((event.initial.x - elem_pos_x) + 1, (event.initial.y - elem_pos_y) + 1),
        current = _coord2d((event.current.x - elem_pos_x) + 1, (event.current.y - elem_pos_y) + 1)
    }
end

-- check if an event qualifies as a click (tap or up)
---@nodiscard
---@param t CLICK_TYPE
function events.was_clicked(t) return t == events.CLICK_TYPE.TAP or t == events.CLICK_TYPE.UP end

-- create a new mouse event to pass onto graphics renderer<br>
-- supports: mouse_click, mouse_up, mouse_drag, mouse_scroll, and monitor_touch
---@param event_type os_event OS event to handle
---@param opt integer|string button, scroll direction, or monitor for monitor touch
---@param x integer x coordinate
---@param y integer y coordinate
---@return mouse_interaction|nil
function events.new_mouse_event(event_type, opt, x, y)
    if event_type == "mouse_click" then
        ---@cast opt 1|2|3
        handler.button_down[opt] = _coord2d(x, y)
        return _mouse_event(opt, events.CLICK_TYPE.DOWN, x, y, x, y)
    elseif event_type == "mouse_up" then
        ---@cast opt 1|2|3
        local initial = handler.button_down[opt]    ---@type coordinate_2d
        return _mouse_event(opt, events.CLICK_TYPE.UP, initial.x, initial.y, x, y)
    elseif event_type == "monitor_touch" then
        ---@cast opt string
        return _monitor_touch(opt, x, y)
    elseif event_type == "mouse_drag" then
        ---@cast opt 1|2|3
        local initial = handler.button_down[opt]    ---@type coordinate_2d
        return _mouse_event(opt, events.CLICK_TYPE.DRAG, initial.x, initial.y, x, y)
    elseif event_type == "mouse_scroll" then
        ---@cast opt 1|-1
        local scroll_direction = util.trinary(opt == 1, events.CLICK_TYPE.SCROLL_DOWN, events.CLICK_TYPE.SCROLL_UP)
        return _mouse_event(events.CLICK_BUTTON.GENERIC, scroll_direction, x, y, x, y)
    end
end

-- create a new key event to pass onto graphics renderer<br>
-- supports: char, key, and key_up
---@param event_type os_event
function events.new_key_event(event_type)
    if event_type == "char" then
    elseif event_type == "key" then
    elseif event_type == "key_up" then
    end
end

return events
