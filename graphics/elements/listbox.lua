-- Scroll-able List Box Display Graphics Element

-- local log     = require("scada-common.log")

local core    = require("graphics.core")
local element = require("graphics.element")

local CLICK_TYPE = core.events.CLICK_TYPE

---@class listbox_args
---@field scroll_height integer height of internal scrolling container (must fit all elements vertically tiled)
---@field item_pad? integer spacing (lines) between items in the list (default 0)
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

---@class listbox_item
---@field id string|integer element ID
---@field e graphics_element element
---@field y integer y position
---@field h integer element height

-- new listbox element
---@nodiscard
---@param args listbox_args
---@return graphics_element element, element_id id
local function listbox(args)
    -- create new graphics element base object
    local e = element.new(args)

    -- create content window for child elements
    local scroll_frame = window.create(e.window, 1, 1, e.frame.w - 1, args.scroll_height, false)
    e.content_window = scroll_frame

    -- item list and scroll management
    local list = {}
    local item_pad = args.item_pad or 0
    local scroll_offset = 0
    local content_height = 0
    local max_down_scroll = 0

    -- bar control/tracking variables
    local bar_height = 0            -- full height of bar
    local bar_bounds = { 0, 0 }     -- top and bottom of bar
    local holding_bar = false       -- bar is being held by mouse
    local bar_grip_pos = 0          -- where the bar was gripped by mouse down
    local mouse_last_y = 0          -- last reported y coordinate of drag

    -- draw up/down arrows
    e.window.setCursorPos(e.frame.w, 1)
    e.window.write("\x1e")
    e.window.setCursorPos(e.frame.w, e.frame.h)
    e.window.write("\x1f")

    -- render the scroll bar and re-cacluate height & bounds
    local function draw_bar()
        local offset = 2 + math.abs(scroll_offset)

        bar_height = math.max(math.min(e.frame.h - 2 + max_down_scroll, e.frame.h - 2), 1)
        bar_bounds = { offset, (bar_height + offset) - 1 }

        for i = 2, e.frame.h - 1 do
            if i >= offset and i < (bar_height + offset) then
                e.window.setBackgroundColor(e.fg_bg.fgd)
            else
                e.window.setBackgroundColor(e.fg_bg.bkg)
            end

            e.window.setCursorPos(e.frame.w, i)
            e.window.write(" ")
        end

        e.window.setBackgroundColor(e.fg_bg.bkg)
    end

    -- update item y positions and move elements
    local function update_positions()
        local next_y = 1

        scroll_frame.setVisible(false)
        scroll_frame.setBackgroundColor(e.fg_bg.bkg)
        scroll_frame.setTextColor(e.fg_bg.fgd)
        scroll_frame.clear()

        for i = 1, #list do
            local item = list[i]    ---@type listbox_item
            item.y = next_y
            next_y = next_y + item.h + item_pad
            item.e.reposition(1, item.y)
            item.e.show()
        end

        content_height = next_y
        max_down_scroll = math.min(-1 * (content_height - (e.frame.h + 1 + item_pad)), 0)
        if scroll_offset < max_down_scroll then scroll_offset = max_down_scroll end

        scroll_frame.reposition(1, 1 + scroll_offset)
        scroll_frame.setVisible(true)

        draw_bar()

        -- log.info("content_height[" .. content_height .. "] max_down_scroll[" .. max_down_scroll .. "] scroll_offset[" .. scroll_offset .. "] bar_height[" .. bar_height .. "]")
    end

    -- scroll down the list
    local function scroll_down()
        if scroll_offset > max_down_scroll then
            scroll_offset = scroll_offset - 1
            update_positions()
        end
    end

    -- scroll up the list
    local function scroll_up()
        if scroll_offset < 0 then
            scroll_offset = scroll_offset + 1
            update_positions()
        end
    end

    -- handle a child element having been added to the list
    ---@param id string|integer element identifier
    ---@param child graphics_element child element
    function e.on_added(id, child)
        table.insert(list, { id = id, e = child, y = 0, h = child.get_height() })
        update_positions()
    end

    -- handle a child element having been removed from the list
    ---@param id string|integer element identifier
    function e.on_removed(id)
        for idx, elem in ipairs(list) do
            if elem.id == id then
                table.remove(list, idx)
                update_positions()
                return
            end
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if e.enabled then
            if event.type == CLICK_TYPE.TAP or event.type == CLICK_TYPE.DOWN then
                if event.current.x == e.frame.w then
                    if event.current.y == 1 or event.current.y < bar_bounds[1] then
                        scroll_up()
                    elseif event.current.y == e.frame.h or event.current.y > bar_bounds[2] then
                        scroll_down()
                    else
                        -- clicked on bar
                        holding_bar = true
                        bar_grip_pos = event.current.y - bar_bounds[1]
                        mouse_last_y = event.current.y
                    end
                end
            elseif event.type == CLICK_TYPE.UP then
                holding_bar = false
            elseif event.type == CLICK_TYPE.DRAG then
                if holding_bar then
                    -- if mouse is within vertical frame, including the grip point
                    if event.current.y > (1 + bar_grip_pos) and event.current.y <= ((e.frame.h - bar_height) + bar_grip_pos) then
                        if event.current.y < mouse_last_y then
                            scroll_up()
                        elseif event.current.y > mouse_last_y then
                            scroll_down()
                        end

                        mouse_last_y = event.current.y
                    end
                end
            elseif event.type == CLICK_TYPE.SCROLL_DOWN then
                scroll_down()
            elseif event.type == CLICK_TYPE.SCROLL_UP then
                scroll_up()
            end
        end
    end

    return e.complete()
end

return listbox
