--
-- Graphics Events and Event Handlers
--

local util = require("scada-common.util")

local DOUBLE_CLICK_MS = 500

local events = {}

---@enum CLICK_BUTTON
local CLICK_BUTTON = {
    GENERIC = 0,
    LEFT_BUTTON = 1,
    RIGHT_BUTTON = 2,
    MID_BUTTON = 3
}

events.CLICK_BUTTON = CLICK_BUTTON

---@enum MOUSE_CLICK
local MOUSE_CLICK = {
    TAP = 1,            -- screen tap (complete click)
    DOWN = 2,           -- button down
    UP = 3,             -- button up (completed a click)
    DRAG = 4,           -- mouse dragged
    SCROLL_DOWN = 5,    -- scroll down
    SCROLL_UP = 6,      -- scroll up
    DOUBLE_CLICK = 7    -- double left click
}

events.MOUSE_CLICK = MOUSE_CLICK

---@enum KEY_CLICK
local KEY_CLICK = {
    DOWN = 1,
    HELD = 2,
    UP = 3,
    CHAR = 4
}

events.KEY_CLICK = KEY_CLICK

-- create a new 2D coordinate
---@param x integer
---@param y integer
---@return coordinate_2d
local function _coord2d(x, y) return { x = x, y = y } end

events.new_coord_2d = _coord2d

---@class mouse_interaction
---@field monitor string
---@field button CLICK_BUTTON
---@field type MOUSE_CLICK
---@field initial coordinate_2d
---@field current coordinate_2d

---@class key_interaction
---@field type KEY_CLICK
---@field key number key code
---@field name string key character name
---@field shift boolean shift held
---@field ctrl boolean ctrl held
---@field alt boolean alt held

local handler = {
    -- left, right, middle button down tracking
    button_down = { _coord2d(0, 0), _coord2d(0, 0), _coord2d(0, 0) },
    -- keyboard modifiers
    shift = false,
    alt = false,
    ctrl = false,
    -- double click tracking
    dc_start = 0,
    dc_step = 1,
    dc_coord = _coord2d(0, 0)
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
        button = CLICK_BUTTON.GENERIC,
        type = MOUSE_CLICK.TAP,
        initial = _coord2d(x, y),
        current = _coord2d(x, y)
    }
end

-- create a new mouse button mouse interaction event
---@nodiscard
---@param button CLICK_BUTTON mouse button
---@param type MOUSE_CLICK click type
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
---@param type MOUSE_CLICK
---@param x integer
---@param y integer
---@return mouse_interaction
function events.mouse_generic(type, x, y)
    return {
        monitor = "",
        button = CLICK_BUTTON.GENERIC,
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
---@param t MOUSE_CLICK
function events.was_clicked(t) return t == MOUSE_CLICK.TAP or t == MOUSE_CLICK.UP end

-- create a new mouse event to pass onto graphics renderer<br>
-- supports: mouse_click, mouse_up, mouse_drag, mouse_scroll, and monitor_touch
---@param event_type os_event OS event to handle
---@param opt integer|string button, scroll direction, or monitor for monitor touch
---@param x integer x coordinate
---@param y integer y coordinate
---@return mouse_interaction|nil
function events.new_mouse_event(event_type, opt, x, y)
    local h = handler

    if event_type == "mouse_click" then
        ---@cast opt 1|2|3

        local init = true

        if opt == 1 and (h.dc_step % 2) == 1 then
            if h.dc_step ~= 1 and h.dc_coord.x == x and h.dc_coord.y == y and (util.time_ms() - h.dc_start) < DOUBLE_CLICK_MS then
                init = false
                h.dc_step = h.dc_step + 1
            end
        end

        if init then
            h.dc_start = util.time_ms()
            h.dc_coord = _coord2d(x, y)
            h.dc_step = 2
        end

        h.button_down[opt] = _coord2d(x, y)
        return _mouse_event(opt, MOUSE_CLICK.DOWN, x, y, x, y)
    elseif event_type == "mouse_up" then
        ---@cast opt 1|2|3

        if opt == 1 and (h.dc_step % 2) == 0 and h.dc_coord.x == x and h.dc_coord.y == y and
                (util.time_ms() - h.dc_start) < DOUBLE_CLICK_MS then
            if h.dc_step == 4 then
                util.push_event("double_click", 1, x, y)
                h.dc_step = 1
            else h.dc_step = h.dc_step + 1 end
        else h.dc_step = 1 end

        local initial = h.button_down[opt]    ---@type coordinate_2d
        return _mouse_event(opt, MOUSE_CLICK.UP, initial.x, initial.y, x, y)
    elseif event_type == "monitor_touch" then
        ---@cast opt string
        return _monitor_touch(opt, x, y)
    elseif event_type == "mouse_drag" then
        ---@cast opt 1|2|3
        local initial = h.button_down[opt]    ---@type coordinate_2d
        return _mouse_event(opt, MOUSE_CLICK.DRAG, initial.x, initial.y, x, y)
    elseif event_type == "mouse_scroll" then
        ---@cast opt 1|-1
        local scroll_direction = util.trinary(opt == 1, MOUSE_CLICK.SCROLL_DOWN, MOUSE_CLICK.SCROLL_UP)
        return _mouse_event(CLICK_BUTTON.GENERIC, scroll_direction, x, y, x, y)
    elseif event_type == "double_click" then
        return _mouse_event(CLICK_BUTTON.LEFT_BUTTON, MOUSE_CLICK.DOUBLE_CLICK, x, y, x, y)
    end
end

-- create a new keyboard interaction event
---@nodiscard
---@param click_type KEY_CLICK key click type
---@param key integer|string keyboard key code or character for 'char' event
---@return key_interaction
local function _key_event(click_type, key)
    local name = key
    if type(key) == "number" then name = keys.getName(key) end
    return { type = click_type, key = key, name = name, shift = handler.shift, ctrl = handler.ctrl, alt = handler.alt }
end

-- create a new keyboard event to pass onto graphics renderer<br>
-- supports: char, key, and key_up
---@param event_type os_event OS event to handle
---@param key integer keyboard key code
---@param held boolean? if the key is being held (for 'key' event)
---@return key_interaction|nil
function events.new_key_event(event_type, key, held)
    if event_type == "char" then
        return _key_event(KEY_CLICK.CHAR, key)
    elseif event_type == "key" then
        if key == keys.leftShift or key == keys.rightShift then
            handler.shift = true
        elseif key == keys.leftCtrl or key == keys.rightCtrl then
            handler.ctrl = true
        elseif key == keys.leftAlt or key == keys.rightAlt then
            handler.alt = true
        else
            return _key_event(util.trinary(held, KEY_CLICK.HELD, KEY_CLICK.DOWN), key)
        end
    elseif event_type == "key_up" then
        if key == keys.leftShift or key == keys.rightShift then
            handler.shift = false
        elseif key == keys.leftCtrl or key == keys.rightCtrl then
            handler.ctrl = false
        elseif key == keys.leftAlt or key == keys.rightAlt then
            handler.alt = false
        else
            return _key_event(KEY_CLICK.UP, key)
        end
    end
end

return events
