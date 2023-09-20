-- Text Value Entry Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

local KEY_CLICK = core.events.KEY_CLICK
local MOUSE_CLICK = core.events.MOUSE_CLICK

---@class text_field_args
---@field value? string initial value
---@field max_len? integer maximum string length
---@field dis_fg_bg? cpair foreground/background colors when disabled
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width? integer parent width if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new text entry field
---@param args text_field_args
---@return graphics_element element, element_id id
local function text_field(args)
    args.height = 1
    args.can_focus = true

    -- create new graphics element base object
    local e = element.new(args)

    -- set initial value
    e.value = args.value or ""

    local max_len = 1000 -- temporary

    local frame_start = 1
    local visible_text = e.value
    local cursor_pos = string.len(visible_text) + 1

    local function frame__update_visible()
        visible_text = string.sub(e.value, frame_start, frame_start + math.min(string.len(e.value), args.width) - 1)
    end

    -- draw input
    local function show()
        frame__update_visible()

        if e.enabled then
            e.w_set_bkg(args.fg_bg.bkg)
            e.w_set_fgd(args.fg_bg.fgd)
        else
            e.w_set_bkg(args.dis_fg_bg.bkg)
            e.w_set_fgd(args.dis_fg_bg.fgd)
        end

        -- clear and print
        e.w_set_cur(1, 1)
        e.w_write(string.rep(" ", e.frame.w))
        e.w_set_cur(1, 1)

        if e.is_focused() and e.enabled then
            -- write text with cursor
            if cursor_pos == (string.len(visible_text) + 1) then
                -- write text with cursor at the end, no need to blit
                e.w_write(visible_text)
                e.w_set_fgd(colors.lightGray)
                e.w_write("_")
            else
                local a, b = "", ""

                if cursor_pos <= string.len(visible_text) then
                    a = args.fg_bg.blit_bkg
                    b = args.fg_bg.blit_fgd
                end

                local b_fgd = string.rep(args.fg_bg.blit_fgd, cursor_pos - 1) .. a .. string.rep(args.fg_bg.blit_fgd, string.len(visible_text) - cursor_pos)
                local b_bkg = string.rep(args.fg_bg.blit_bkg, cursor_pos - 1) .. b .. string.rep(args.fg_bg.blit_bkg, string.len(visible_text) - cursor_pos)

                e.w_blit(visible_text, b_fgd, b_bkg)
            end
        else
            -- write text without cursor
            e.w_write(visible_text)
        end
    end

    local function frame__try_lshift()
        if frame_start > 1 then
            frame_start = frame_start - 1
            show()
        end
    end

    local function frame__try_rshift()
        if (frame_start + args.width - 1) < string.len(e.value) then
            frame_start = frame_start + 1
            show()
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        -- only handle if on an increment or decrement arrow
        if e.enabled and core.events.was_clicked(event.type) then
            e.req_focus()

            if event.type == MOUSE_CLICK.UP then
                cursor_pos = math.min(event.current.x, string.len(visible_text) + 1)
                show()
            end
        end
    end

    -- handle keyboard interaction
    ---@param event key_interaction key event
    function e.handle_key(event)
        if event.type == KEY_CLICK.CHAR and string.len(e.value) < max_len then
            e.value = string.sub(e.value, 1, frame_start + cursor_pos - 2) .. event.name .. string.sub(e.value, frame_start + cursor_pos - 1, string.len(e.value))
            frame__update_visible()
            if cursor_pos <= string.len(visible_text) then
                cursor_pos = cursor_pos + 1
                show()
            else frame__try_rshift() end
        elseif event.type == KEY_CLICK.DOWN or event.type == KEY_CLICK.HELD then
            if (event.key == keys.backspace or event.key == keys.delete) then
                -- remove charcter at cursor
                e.value = string.sub(e.value, 1, frame_start + cursor_pos - 3) .. string.sub(e.value, frame_start + cursor_pos - 1, string.len(e.value))
                if cursor_pos > 1 then
                    cursor_pos = cursor_pos - 1
                    show()
                else frame__try_lshift() end
            elseif event.key == keys.left then
                if cursor_pos > 1 then
                    cursor_pos = cursor_pos - 1
                    show()
                else frame__try_lshift() end
            elseif event.key == keys.right then
                if cursor_pos <= string.len(visible_text) then
                    cursor_pos = cursor_pos + 1
                    show()
                else frame__try_rshift() end
            end
        end
    end

    -- set the value
    ---@param val string string to show
    function e.set_value(val)
        e.value = val
        frame_start = 1 + math.max(0, string.len(val) - args.width)
        frame__update_visible()
        cursor_pos = string.len(visible_text) + 1
        show()
    end

    function e.handle_paste(text)
        e.set_value(text)
    end

    -- handle focus
    e.on_focused = show
    e.on_unfocused = show

    -- on enable/disable
    e.enable = show
    e.disable = show

    -- initial draw
    show()

    return e.complete()
end

return text_field
