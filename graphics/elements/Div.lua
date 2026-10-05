-- Div (Division, like in HTML) Graphics Element

local core    = require("graphics.core")
local element = require("graphics.element")

local KEY_CLICK = core.events.KEY_CLICK
local MOUSE_CLICK = core.events.MOUSE_CLICK

---@class div_args
---@field callback? function function to call on touch
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- Create a new div container element.
---@nodiscard
---@param args div_args
---@return Div element, element_id id
return function (args)
    element.assert((args.callback == nil) or (type(args.callback) == "function"), "callback must be a function if provided")

    -- create new graphics element base object
    local e = element.new(args --[[@as graphics_args]])

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if args.callback and e.enabled then
            if event.type == MOUSE_CLICK.TAP then
                args.callback()
            elseif event.type == MOUSE_CLICK.UP then
                if e.in_frame_bounds(event.current.x, event.current.y) then
                    args.callback()
                end
            end
        end
    end

    -- handle keyboard interaction
    ---@param event key_interaction key event
    function e.handle_key(event)
        if args.callback and e.enabled and event.type == KEY_CLICK.DOWN then
            if event.key == keys.space or event.key == keys.enter or event.key == keys.numPadEnter then
                args.callback()
            end
        end
    end

    ---@class Div:graphics_element
    local Div, id = e.complete()

    return Div, id
end
