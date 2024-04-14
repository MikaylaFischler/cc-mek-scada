-- App Page Multi-Pane Display Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")
local events  = require("graphics.events")

local MOUSE_CLICK = core.events.MOUSE_CLICK

---@class app_multipane_args
---@field panes table panes to swap between
---@field nav_colors cpair on/off colors (a/b respectively) for page navigator
---@field scroll_nav boolean? true to allow scrolling to change the active pane
---@field drag_nav boolean? true to allow mouse dragging to change the active pane (on mouse up)
---@field callback function? function to call when pane is changed by mouse interaction
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new app multipane element
---@nodiscard
---@param args app_multipane_args
---@return graphics_element element, element_id id
local function multipane(args)
    element.assert(type(args.panes) == "table", "panes is a required field")

    -- create new graphics element base object
    local e = element.new(args)

    e.value = 1

    local nav_x_start = math.floor((e.frame.w / 2) - (#args.panes / 2)) + 1
    local nav_x_end   = math.floor((e.frame.w / 2) - (#args.panes / 2)) + #args.panes

    -- show the selected pane
    function e.redraw()
        for i = 1, #args.panes do args.panes[i].hide() end
        args.panes[e.value].show()

        -- draw page indicator dots
        for i = 1, #args.panes do
            e.w_set_cur(nav_x_start + (i - 1), e.frame.h)
            e.w_set_fgd(util.trinary(i == e.value, args.nav_colors.color_a, args.nav_colors.color_b))
            e.w_write("\x07")
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        local initial = e.value

        if e.enabled then
            if event.current.y == e.frame.h and event.current.x >= nav_x_start and event.current.x <= nav_x_end then
                local id = event.current.x - nav_x_start + 1

                if event.type == MOUSE_CLICK.TAP then
                    e.set_value(id)
                elseif event.type == MOUSE_CLICK.UP then
                    e.set_value(id)
                end
            end
        end

        if args.scroll_nav then
            if event.type == events.MOUSE_CLICK.SCROLL_DOWN then
                e.set_value(e.value + 1)
            elseif event.type == events.MOUSE_CLICK.SCROLL_UP then
                e.set_value(e.value - 1)
            end
        end

        if args.drag_nav then
            local x1, x2 = event.initial.x, event.current.x
            if event.type == events.MOUSE_CLICK.UP and e.in_frame_bounds(x1, event.initial.y) and e.in_frame_bounds(x1, event.current.y) then
                if x2 > x1 then
                    e.set_value(e.value - 1)
                elseif x2 < x1 then
                    e.set_value(e.value + 1)
                end
            end
        end

        if e.value ~= initial and type(args.callback) == "function" then args.callback(e.value) end
    end

    -- select which pane is shown
    ---@param value integer pane to show
    function e.set_value(value)
        if (e.value ~= value) and (value > 0) and (value <= #args.panes) then
            e.value = value
            e.redraw()
        end
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return multipane
