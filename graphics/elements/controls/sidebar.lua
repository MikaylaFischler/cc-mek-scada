-- Sidebar Graphics Element

local tcd     = require("scada-common.tcd")
local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

local MOUSE_CLICK = core.events.MOUSE_CLICK

---@class sidebar_args
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
    args.width = 3

    -- create new graphics element base object
    local e = element.new(args)

    -- default to 1st tab
    e.value = 1

    local was_pressed = false
    local tabs = {}

    -- show the button state
    ---@param pressed? boolean if the currently selected tab should appear as actively pressed
    ---@param pressed_idx? integer optional index to show as held (that is not yet selected)
    local function draw(pressed, pressed_idx)
        pressed = util.trinary(pressed == nil, was_pressed, pressed)
        was_pressed = pressed
        pressed_idx = pressed_idx or e.value

        -- clear
        e.w_set_fgd(e.fg_bg.fgd)
        e.w_set_bkg(e.fg_bg.bkg)
        for y = 1, e.frame.h do
            e.w_set_cur(1, y)
            e.w_write("   ")
        end

        -- draw tabs
        for i = 1, #tabs do
            local tab = tabs[i] ---@type sidebar_tab
            local y = tab.y_start

            e.w_set_cur(1, y)

            if pressed and i == pressed_idx then
                e.w_set_fgd(e.fg_bg.fgd)
                e.w_set_bkg(e.fg_bg.bkg)
            else
                e.w_set_fgd(tab.color.fgd)
                e.w_set_bkg(tab.color.bkg)
            end

            if tab.tall then
                e.w_write("   ")
                e.w_set_cur(1, y + 1)
            end

            e.w_write(tab.label)

            if tab.tall then
                e.w_set_cur(1, y + 2)
                e.w_write("   ")
            end
        end
    end

    -- determine which tab was pressed
    ---@param y integer y coordinate
    local function find_tab(y)
        for i = 1, #tabs do
            local tab = tabs[i] ---@type sidebar_tab

            if y >= tab.y_start and y <= tab.y_end then
                return i
            end
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        -- determine what was pressed
        if e.enabled then
            local cur_idx = find_tab(event.current.y)
            local ini_idx = find_tab(event.initial.y)
            local tab = tabs[cur_idx]

            -- handle press if a callback was provided
            if tab ~= nil and type(tab.callback) == "function" then
                if event.type == MOUSE_CLICK.TAP then
                    e.value = cur_idx
                    draw(true)
                    -- show as unpressed in 0.25 seconds
                    tcd.dispatch(0.25, function () draw(false) end)
                    tab.callback()
                elseif event.type == MOUSE_CLICK.DOWN then
                    draw(true, cur_idx)
                elseif event.type == MOUSE_CLICK.UP then
                    if cur_idx == ini_idx and e.in_frame_bounds(event.current.x, event.current.y) then
                        e.value = cur_idx
                        draw(false)
                        tab.callback()
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

    -- update the sidebar navigation options
    ---@param items table sidebar entries
    function e.on_update(items)
        local next_y = 1

        tabs = {}

        for i = 1, #items do
            local item = items[i]
            local height = util.trinary(item.tall, 3, 1)

            ---@class sidebar_tab
            local entry = {
                y_start = next_y,            ---@type integer
                y_end = next_y + height - 1, ---@type integer
                tall = item.tall,            ---@type boolean
                label = item.label,          ---@type string
                color = item.color,          ---@type cpair
                callback = item.callback     ---@type function|nil
            }

            next_y = next_y + height

            tabs[i] = entry
        end

        draw()
    end

    -- element redraw
    e.redraw = draw

    e.redraw()

    return e.complete()
end

return sidebar
