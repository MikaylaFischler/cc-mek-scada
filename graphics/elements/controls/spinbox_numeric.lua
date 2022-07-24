-- Spinbox Numeric Graphics Element

local element = require("graphics.element")
local util    = require("scada-common.util")

---@class spinbox_args
---@field default? number default value, defaults to 0.0
---@field whole_num_precision integer number of whole number digits
---@field fractional_precision integer number of fractional digits
---@field arrow_fg_bg cpair arrow foreground/background colors
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field fg_bg? cpair foreground/background colors

-- new spinbox control (minimum value is 0)
---@param args spinbox_args
local function spinbox(args)
    -- properties
    local value = args.default or 0.0
    local digits = {}
    local wn_prec = args.whole_num_precision
    local fr_prec = args.fractional_precision

    assert(util.is_int(wn_prec), "graphics.element.controls.spinbox_numeric: whole number precision must be an integer")
    assert(util.is_int(fr_prec), "graphics.element.controls.spinbox_numeric: fractional precision must be an integer")

    local fmt = "%" .. (wn_prec + fr_prec + 1) .. "." .. fr_prec .. "f"
    local fmt_init = "%0" .. (wn_prec + fr_prec + 1) .. "." .. fr_prec .. "f"
    local dec_point_x = args.whole_num_precision + 1

    assert(type(args.arrow_fg_bg) == "table", "graphics.element.spinbox_numeric: arrow_fg_bg is a required field")

    local initial_str = util.sprintf(fmt_init, value)

---@diagnostic disable-next-line: discard-returns
    initial_str:gsub("%d", function(char) table.insert(digits, char) end)

    -- determine widths
    args.width = wn_prec + fr_prec + util.trinary(fr_prec > 0, 1, 0)
    args.height = 3

    -- create new graphics element base object
    local e = element.new(args)

    -- draw the arrows
    e.window.setBackgroundColor(args.arrow_fg_bg.bkg)
    e.window.setTextColor(args.arrow_fg_bg.fgd)
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

    -- zero the value
    local function zero()
        for i = 1, #digits do digits[i] = 0 end
        value = 0
    end

    -- print out the current value
    local function show_num()
        e.window.setBackgroundColor(e.fg_bg.bkg)
        e.window.setTextColor(e.fg_bg.fgd)
        e.window.setCursorPos(1, 2)
        e.window.write(util.sprintf(fmt, value))
    end

    -- init with the default value
    show_num()

    -- handle touch
    ---@param event monitor_touch monitor touch event
    function e.handle_touch(event)
        -- only handle if on an increment or decrement arrow
        if event.x ~= dec_point_x then
            local idx = util.trinary(event.x > dec_point_x, event.x - 1, event.x)
            if event.y == 1 then
                -- increment
                digits[idx] = digits[idx] + 1
            elseif event.y == 3 then
                -- decrement
                digits[idx] = digits[idx] - 1
            end

            -- update value
            value = 0
            for i = 1, #digits do
                local pow = math.abs(wn_prec - i)
                if i <= wn_prec then
                    value = value + (digits[i] * (10 ^ pow))
                else
                    value = value + (digits[i] * (10 ^ -pow))
                end
            end

            -- min 0
            if value < 0 then zero() end

            show_num()
        end
    end

    -- get current value
    ---@return number|integer
    function e.get_value() return value end

    return e.get()
end

return spinbox
