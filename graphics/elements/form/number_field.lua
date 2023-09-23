-- Numeric Value Entry Graphics Element

local core    = require("graphics.core")
local element = require("graphics.element")

local KEY_CLICK = core.events.KEY_CLICK
local MOUSE_CLICK = core.events.MOUSE_CLICK

---@class number_field_args
---@field default? number default value, defaults to 0
---@field min? number minimum, forced on unfocus
---@field max? number maximum, forced on unfocus
---@field max_digits? integer maximum number of digits, defaults to width
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
    args.height = 1
    args.can_focus = true

    -- create new graphics element base object
    local e = element.new(args)

    local has_decimal = false

    args.max_digits = args.max_digits or e.frame.w

    -- set initial value
    e.value = "" .. (args.default or 0)

    -- make an interactive field manager
    local ifield = core.new_ifield(e, args.max_digits, args.fg_bg, args.dis_fg_bg)


    -- draw input
    local function show()
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
        e.w_write(e.value)

        -- show cursor if focused
        if e.is_focused() and e.enabled then
            e.w_set_fgd(colors.lightGray)
            e.w_write("_")
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        -- only handle if on an increment or decrement arrow
        if e.enabled then
            if core.events.was_clicked(event.type) then
                e.req_focus()

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
        if event.type == KEY_CLICK.CHAR and string.len(e.value) < args.max_digits then
            if tonumber(event.name) then
                if e.value == 0 then e.value = "" end
                ifield.try_insert_char(event.name)
            end
        elseif event.type == KEY_CLICK.DOWN then
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
        if tonumber(val) then
            ifield.set_value("" .. tonumber(val))
        end
    end

    -- set minimum input value
    ---@param min integer minimum allowed value
    function e.set_min(min) args.min = min end

    -- set maximum input value
    ---@param max integer maximum allowed value
    function e.set_max(max) args.max = max end

    -- replace text with pasted text if its a number
    ---@param text string string pasted
    function e.handle_paste(text)
        if tonumber(text) then
            ifield.set_value("" .. tonumber(text))
        else
            ifield.set_value("0")
        end
    end

    -- handle focused
    e.on_focused = show

    -- handle unfocused
    function e.on_unfocused()
        local val = tonumber(e.value)
        local max = tonumber(args.max)
        local min = tonumber(args.min)

        if type(val) == "number" then
            if type(args.max) == "number" and val > max then
                e.value = "" .. max
            elseif type(args.min) == "number" and val < min then
                e.value = "" .. min
            end
        else
            e.value = ""
        end

        ifield.show()
    end

    -- handle enable
    e.on_enabled = ifield.show
    e.on_disabled = ifield.show

    -- initial draw
    ifield.show()

    return e.complete()
end

return number_field
