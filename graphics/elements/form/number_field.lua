-- Numeric Value Entry Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

local KEY_CLICK = core.events.KEY_CLICK
local MOUSE_CLICK = core.events.MOUSE_CLICK

---@class number_field_args
---@field default? number default value, defaults to 0
---@field min? number minimum, enforced on unfocus
---@field max? number maximum, enforced on unfocus
---@field max_chars? integer maximum number of characters, defaults to width
---@field max_int_digits? integer maximum number of integer digits, enforced on unfocus
---@field max_frac_digits? integer maximum number of fractional digits, enforced on unfocus
---@field allow_decimal? boolean true to allow decimals
---@field allow_negative? boolean true to allow negative numbers
---@field dis_fg_bg? cpair foreground/background colors when disabled
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width? integer parent width if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new numeric entry field
---@param args number_field_args
---@return graphics_element element, element_id id
local function number_field(args)
    element.assert(args.max_int_digits == nil or (util.is_int(args.max_int_digits) and args.max_int_digits > 0), "max_int_digits must be an integer greater than zero if supplied")
    element.assert(args.max_frac_digits == nil or (util.is_int(args.max_frac_digits) and args.max_frac_digits > 0), "max_frac_digits must be an integer greater than zero if supplied")

    args.height = 1
    args.can_focus = true

    -- create new graphics element base object
    local e = element.new(args)

    local has_decimal = false

    args.max_chars = args.max_chars or e.frame.w

    -- set initial value
    e.value = "" .. (args.default or 0)

    -- make an interactive field manager
    local ifield = core.new_ifield(e, args.max_chars, args.fg_bg, args.dis_fg_bg)

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
        if event.type == KEY_CLICK.CHAR and string.len(e.value) < args.max_chars then
            if tonumber(event.name) then
                if e.value == 0 then e.value = "" end
                ifield.try_insert_char(event.name)
            end
        elseif event.type == KEY_CLICK.DOWN or event.type == KEY_CLICK.HELD then
            if (event.key == keys.backspace or event.key == keys.delete) and (string.len(e.value) > 0) then
                ifield.backspace()
                has_decimal = string.find(e.value, "%.") ~= nil
            elseif (event.key == keys.period or event.key == keys.numPadDecimal) and (not has_decimal) and args.allow_decimal then
                has_decimal = true
                ifield.try_insert_char(".")
            elseif (event.key == keys.minus or event.key == keys.numPadSubtract) and (string.len(e.value) == 0) and args.allow_negative then
                ifield.set_value("-")
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

    -- set the value (must be a number)
    ---@param val number number to show
    function e.set_value(val)
        if tonumber(val) then ifield.set_value("" .. tonumber(val)) end
    end

    -- set minimum input value
    ---@param min integer minimum allowed value
    function e.set_min(min)
        args.min = min
        e.on_unfocused()
    end

    -- set maximum input value
    ---@param max integer maximum allowed value
    function e.set_max(max)
        args.max = max
        e.on_unfocused()
    end

    -- replace text with pasted text if its a number
    ---@param text string string pasted
    function e.handle_paste(text)
        if tonumber(text) then
            ifield.set_value("" .. tonumber(text))
        else
            ifield.set_value("0")
        end
    end

    -- handle unfocused
    function e.on_unfocused()
        local val = tonumber(e.value)
        local max = tonumber(args.max)
        local min = tonumber(args.min)

        if type(val) == "number" then
            if args.max_int_digits or args.max_frac_digits then
                local str = e.value
                local ceil = false

                if string.find(str, "-") then str = string.sub(e.value, 2) end
                local parts = util.strtok(str, ".")

                if parts[1] and args.max_int_digits then
                    if string.len(parts[1]) > args.max_int_digits then
                        parts[1] = string.rep("9", args.max_int_digits)
                        ceil = true
                    end
                end

                if args.allow_decimal and args.max_frac_digits then
                    if ceil then
                        parts[2] = string.rep("9", args.max_frac_digits)
                    elseif parts[2] and (string.len(parts[2]) > args.max_frac_digits) then
                        -- add a half of the highest precision fractional value in order to round using floor
                        local scaled = math.fmod(val, 1) * (10 ^ (args.max_frac_digits))
                        local value = math.floor(scaled + 0.5)
                        local unscaled = value * (10 ^ (-args.max_frac_digits))
                        parts[2] = string.sub(tostring(unscaled), 3) -- remove starting "0."
                    end
                end

                if parts[2] then parts[2] = "." .. parts[2] else parts[2] = "" end

                val = tonumber((parts[1] or "") .. parts[2])
            end

            if type(args.max) == "number" and val > max then
                e.value = "" .. max
                ifield.nav_start()
            elseif type(args.min) == "number" and val < min then
                e.value = "" .. min
                ifield.nav_start()
            else
                e.value = "" .. val
                ifield.nav_end()
            end
        else
            e.value = ""
        end

        ifield.show()
    end

    -- handle focus (not unfocus), enable, and redraw with show()
    e.on_focused = ifield.show
    e.on_enabled = ifield.show
    e.on_disabled = ifield.show
    e.redraw = ifield.show

    -- initial draw
    e.redraw()

    return e.complete()
end

return number_field
