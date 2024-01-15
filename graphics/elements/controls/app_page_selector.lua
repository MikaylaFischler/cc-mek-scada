-- App Page Selector Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

local MOUSE_CLICK = core.events.MOUSE_CLICK

---@class app_page_selector_args
---@field page_count integer number of pages (will become this element's width)
---@field active_color color on/off colors (a/b respectively)
---@field callback function function to call on touch
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new app page selector
---@param args app_page_selector_args
---@return graphics_element element, element_id id
local function app_page_selector(args)
    element.assert(util.is_int(args.page_count), "page_count is a required field")
    element.assert(util.is_int(args.active_color), "active_color is a required field")
    element.assert(type(args.callback) == "function", "callback is a required field")

    args.height = 1
    args.width = args.page_count

    -- create new graphics element base object
    local e = element.new(args)

    e.value = 1

    -- draw dot selectors
    function e.redraw()
        for i = 1, args.page_count do
            e.w_set_cur(i, 1)
            e.w_set_fgd(util.trinary(i == e.value, args.active_color, e.fg_bg.fgd))
            e.w_write("\x07")
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if e.enabled then
            if event.type == MOUSE_CLICK.TAP then
                e.set_value(event.current.x)
                args.callback(e.value)
            elseif event.type == MOUSE_CLICK.UP then
                if e.in_frame_bounds(event.current.x, event.current.y) then
                    e.set_value(event.current.x)
                    args.callback(e.value)
                end
            end
        end
    end

    -- set the value (does not call the callback)
    ---@param val integer new value
    function e.set_value(val)
        e.value = val
        e.redraw()
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return app_page_selector
