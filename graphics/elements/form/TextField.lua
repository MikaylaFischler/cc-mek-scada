-- Text Value Entry Graphics Element

local core    = require("graphics.core")
local element = require("graphics.element")

local KEY_CLICK = core.events.KEY_CLICK
local MOUSE_CLICK = core.events.MOUSE_CLICK

---@class text_field_args
---@field value? string initial value
---@field max_len? integer maximum string length
---@field censor? string character to replace text with when printing to screen
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
---@return graphics_element element, element_id id, function censor_ctl
local function text_field(args)
    args.height = 1
    args.can_focus = true

    -- create new graphics element base object
    local e = element.new(args)

    -- set initial value
    e.value = args.value or ""

    -- make an interactive field manager
    local ifield = core.new_ifield(e, args.max_len or e.frame.w, args.fg_bg, args.dis_fg_bg)

    ifield.censor(args.censor)

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        -- only handle if on an increment or decrement arrow
        if e.enabled and e.in_frame_bounds(event.current.x, event.current.y) then
            if core.events.was_clicked(event.type) then
                e.take_focus()

                if event.type == MOUSE_CLICK.UP then
                    ifield.move_cursor(event.current.x)
                end
            elseif event.type == MOUSE_CLICK.DOUBLE_CLICK then
                ifield.select_all()
            end
        end
    end

    -- handle keyboard interaction
    ---@param event key_interaction key event
    function e.handle_key(event)
        if event.type == KEY_CLICK.CHAR then
            ifield.try_insert_char(event.name)
        elseif event.type == KEY_CLICK.DOWN or event.type == KEY_CLICK.HELD then
            if (event.key == keys.backspace or event.key == keys.delete) then
                ifield.backspace()
            elseif event.key == keys.left then
                ifield.nav_left()
            elseif event.key == keys.right then
                ifield.nav_right()
            elseif event.key == keys.a and event.ctrl then
                ifield.select_all()
            elseif event.key == keys.home or event.key == keys.up then
                ifield.nav_start()
            elseif event.key == keys["end"] or event.key == keys.down then
                ifield.nav_end()
            end
        end
    end

    -- set the value
    ---@param val string string to set
    function e.set_value(val)
        ifield.set_value(val)
    end

    -- replace text with pasted text
    ---@param text string string to set
    function e.handle_paste(text)
        ifield.set_value(text)
    end

    -- handle focus, enable, and redraw with show()
    e.on_focused = ifield.show
    e.on_unfocused = ifield.show
    e.on_enabled = ifield.show
    e.on_disabled = ifield.show
    e.redraw = ifield.show

    -- initial draw
    e.redraw()

    local elem, id = e.complete()
    return elem, id, ifield.censor
end

return text_field
