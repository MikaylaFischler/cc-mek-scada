-- Sidebar Graphics Element

local tcd     = require("scada-common.tcd")
local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

local MOUSE_CLICK = core.events.MOUSE_CLICK

---@class sidebar_tab
---@field char string character identifier
---@field color cpair tab colors (fg/bg)

---@class sidebar_args
---@field tabs table sidebar tab options
---@field callback function function to call on tab change
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field height? integer parent height if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new sidebar tab selector
---@param args sidebar_args
---@return graphics_element element, element_id id
local function sidebar(args)
    element.assert(type(args.tabs) == "table", "tabs is a required field")
    element.assert(#args.tabs > 0, "at least one tab is required")
    element.assert(type(args.callback) == "function", "callback is a required field")

    args.width = 3

    -- create new graphics element base object
    local e = element.new(args)

    element.assert(e.frame.h >= (#args.tabs * 3), "height insufficent to display all tabs")

    -- default to 1st tab
    e.value = 1

    local was_pressed = false

    -- show the button state
    ---@param pressed? boolean if the currently selected tab should appear as actively pressed
    ---@param pressed_idx? integer optional index to show as held (that is not yet selected)
    local function draw(pressed, pressed_idx)
        pressed = util.trinary(pressed == nil, was_pressed, pressed)
        was_pressed = pressed
        pressed_idx = pressed_idx or e.value

        for i = 1, #args.tabs do
            local tab = args.tabs[i] ---@type sidebar_tab

            local y = ((i - 1) * 3) + 1

            e.w_set_cur(1, y)

            if pressed and i == pressed_idx then
                e.w_set_fgd(e.fg_bg.fgd)
                e.w_set_bkg(e.fg_bg.bkg)
            else
                e.w_set_fgd(tab.color.fgd)
                e.w_set_bkg(tab.color.bkg)
            end

            e.w_write("   ")
            e.w_set_cur(1, y + 1)
            if e.value == i then
                e.w_write(" " .. tab.char .. "\x10")
            else e.w_write(" " .. tab.char .. " ") end
            e.w_set_cur(1, y + 2)
            e.w_write("   ")
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        -- determine what was pressed
        if e.enabled then
            local cur_idx = math.ceil(event.current.y / 3)
            local ini_idx = math.ceil(event.initial.y / 3)

            if args.tabs[cur_idx] ~= nil then
                if event.type == MOUSE_CLICK.TAP then
                    e.value = cur_idx
                    draw(true)
                    -- show as unpressed in 0.25 seconds
                    tcd.dispatch(0.25, function () draw(false) end)
                    args.callback(e.value)
                elseif event.type == MOUSE_CLICK.DOWN then
                    draw(true, cur_idx)
                elseif event.type == MOUSE_CLICK.UP then
                    if cur_idx == ini_idx and e.in_frame_bounds(event.current.x, event.current.y) then
                        e.value = cur_idx
                        draw(false)
                        args.callback(e.value)
                    else draw(false) end
                end
            elseif event.type == MOUSE_CLICK.UP then
                draw(false)
            end
        end
    end

    -- set the value
    ---@param val integer new value
    function e.set_value(val)
        e.value = val
        draw(false)
    end

    -- element redraw
    e.redraw = draw

    e.redraw()

    return e.complete()
end

return sidebar
