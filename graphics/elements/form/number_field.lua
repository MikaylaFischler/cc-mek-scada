-- Numeric Value Entry Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

local KEY_CLICK = core.events.KEY_CLICK

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
    e.value = util.strval(args.default or 0)

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
        if e.enabled and core.events.was_clicked(event.type) then
            e.req_focus()
        end
    end

    -- handle keyboard interaction
    ---@param event key_interaction key event
    function e.handle_key(event)
        if event.type == KEY_CLICK.CHAR and string.len(e.value) < args.max_digits then
            if tonumber(event.name) then
                e.value = util.trinary(e.value == "0", "", e.value) .. tonumber(event.name)
                show()
            end
        elseif event.type == KEY_CLICK.DOWN then
            if (event.key == keys.backspace or event.key == keys.delete) and (string.len(e.value) > 0) then
                e.value = string.sub(e.value, 1, string.len(e.value) - 1)
                has_decimal = string.find(e.value, "%.") ~= nil
                show()
            elseif (event.key == keys.period or event.key == keys.numPadDecimal) and (not has_decimal) and args.allow_decimal then
                e.value = e.value .. "."
                has_decimal = true
                show()
            elseif (event.key == keys.minus or event.key == keys.numPadSubtract) and (string.len(e.value) == 0) and args.allow_negative then
                e.value = "-"
                show()
            end
        end
    end

    -- set the value
    ---@param val number number to show
    function e.set_value(val)
        e.value = val
        show()
    end

    -- set minimum input value
    ---@param min integer minimum allowed value
    function e.set_min(min)
        args.min = min
        show()
    end

    -- set maximum input value
    ---@param max integer maximum allowed value
    function e.set_max(max)
        args.max = max
        show()
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

        show()
    end

    -- on enable/disable
    e.enable = show
    e.disable = show

    -- initial draw
    show()

    return e.complete()
end

return number_field
