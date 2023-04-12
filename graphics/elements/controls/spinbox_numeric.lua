-- Spinbox Numeric Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class spinbox_args
---@field default? number default value, defaults to 0.0
---@field min? number default 0, currently must be 0 or greater
---@field max? number default max number that can be displayed with the digits configuration
---@field whole_num_precision integer number of whole number digits
---@field fractional_precision integer number of fractional digits
---@field arrow_fg_bg cpair arrow foreground/background colors
---@field arrow_disable? color color when disabled (default light gray)
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field fg_bg? cpair foreground/background colors

-- new spinbox control (minimum value is 0)
---@param args spinbox_args
---@return graphics_element element, element_id id
local function spinbox(args)
    -- properties
    local digits = {}
    local wn_prec = args.whole_num_precision
    local fr_prec = args.fractional_precision

    assert(util.is_int(wn_prec), "graphics.element.controls.spinbox_numeric: whole number precision must be an integer")
    assert(util.is_int(fr_prec), "graphics.element.controls.spinbox_numeric: fractional precision must be an integer")

    local fmt, fmt_init ---@type string, string

    if fr_prec > 0 then
        fmt = "%" .. (wn_prec + fr_prec + 1) .. "." .. fr_prec .. "f"
        fmt_init = "%0" .. (wn_prec + fr_prec + 1) .. "." .. fr_prec .. "f"
    else
        fmt = "%" .. wn_prec .. "d"
        fmt_init = "%0" .. wn_prec .. "d"
    end

    local dec_point_x = args.whole_num_precision + 1

    assert(type(args.arrow_fg_bg) == "table", "graphics.element.spinbox_numeric: arrow_fg_bg is a required field")

    -- determine widths
    args.width = wn_prec + fr_prec + util.trinary(fr_prec > 0, 1, 0)
    args.height = 3

    -- create new graphics element base object
    local e = element.new(args)

    -- set initial value
    e.value = args.default or 0

    -- draw the arrows
    local function draw_arrows(color)
        e.window.setBackgroundColor(args.arrow_fg_bg.bkg)
        e.window.setTextColor(color)
        e.window.setCursorPos(1, 1)
        e.window.write(util.strrep("\x1e", wn_prec))
        e.window.setCursorPos(1, 3)
        e.window.write(util.strrep("\x1f", wn_prec))
        if fr_prec > 0 then
            e.window.setCursorPos(1 + wn_prec, 1)
            e.window.write(" " .. util.strrep("\x1e", fr_prec))
            e.window.setCursorPos(1 + wn_prec, 3)
            e.window.write(" " .. util.strrep("\x1f", fr_prec))
        end
    end

    draw_arrows(args.arrow_fg_bg.fgd)

    -- populate digits from current value
    local function set_digits()
        local initial_str = util.sprintf(fmt_init, e.value)

        digits = {}
---@diagnostic disable-next-line: discard-returns
        initial_str:gsub("%d", function (char) table.insert(digits, char) end)
    end

    -- update the value per digits table
    local function update_value()
        e.value = 0
        for i = 1, #digits do
            local pow = math.abs(wn_prec - i)
            if i <= wn_prec then
                e.value = e.value + (digits[i] * (10 ^ pow))
            else
                e.value = e.value + (digits[i] * (10 ^ -pow))
            end
        end
    end

    -- print out the current value
    local function show_num()
        -- enforce limits
        if (type(args.min) == "number") and (e.value < args.min) then
            e.value = args.min
            set_digits()
        elseif e.value < 0 then
            e.value = 0
            set_digits()
        else
            if string.len(util.sprintf(fmt, e.value)) > args.width then
                -- max printable exceeded, so max out to all 9s
                for i = 1, #digits do digits[i] = 9 end
                update_value()
            elseif (type(args.max) == "number") and (e.value > args.max) then
                e.value = args.max
                set_digits()
            else
                set_digits()
            end
        end

        -- draw
        e.window.setBackgroundColor(e.fg_bg.bkg)
        e.window.setTextColor(e.fg_bg.fgd)
        e.window.setCursorPos(1, 2)
        e.window.write(util.sprintf(fmt, e.value))
    end

    -- init with the default value
    show_num()

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        -- only handle if on an increment or decrement arrow
        if e.enabled and event.x ~= dec_point_x then
            local idx = util.trinary(event.x > dec_point_x, event.x - 1, event.x)
            if digits[idx] ~= nil then
                if event.y == 1 then
                    -- increment
                    digits[idx] = digits[idx] + 1
                elseif event.y == 3 then
                    -- decrement
                    digits[idx] = digits[idx] - 1
                end

                update_value()
                show_num()
            end
        end
    end

    -- set the value
    ---@param val number number to show
    function e.set_value(val)
        e.value = val
        show_num()
    end

    -- set minimum input value
    ---@param min integer minimum allowed value
    function e.set_min(min)
        if min >= 0 then
            args.min = min
            show_num()
        end
    end

    -- set maximum input value
    ---@param max integer maximum allowed value
    function e.set_max(max)
        args.max = max
        show_num()
    end

    -- enable this input
    function e.enable()
        draw_arrows(args.arrow_fg_bg.fgd)
    end

    -- disable this input
    function e.disable()
        draw_arrows(args.arrow_disable or colors.lightGray)
    end

    -- default to zero, init digits table
    e.value = 0
    set_digits()

    return e.get()
end

return spinbox
