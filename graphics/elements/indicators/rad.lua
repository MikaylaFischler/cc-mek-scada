-- Radiation Indicator Graphics Element

local types   = require("scada-common.types")
local util    = require("scada-common.util")

local element = require("graphics.element")

---@class rad_indicator_args
---@field label string indicator label
---@field format string data format (lua string format)
---@field commas? boolean whether to use commas if a number is given (default to false)
---@field lu_colors? cpair label foreground color (a), unit foreground color (b)
---@field value any default value
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width integer length
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new radiation indicator
---@nodiscard
---@param args rad_indicator_args
---@return graphics_element element, element_id id
local function rad(args)
    assert(type(args.label) == "string", "graphics.elements.indicators.rad: label is a required field")
    assert(type(args.format) == "string", "graphics.elements.indicators.rad: format is a required field")
    assert(util.is_int(args.width), "graphics.elements.indicators.rad: width is a required field")

    -- single line
    args.height = 1

    -- create new graphics element base object
    local e = element.new(args)

    -- label color
    if args.lu_colors ~= nil then
        e.window.setTextColor(args.lu_colors.color_a)
    end

    -- write label
    e.window.setCursorPos(1, 1)
    e.window.write(args.label)

    local label_len = string.len(args.label)
    local data_start = 1
    local clear_width = args.width

    if label_len > 0 then
        data_start = data_start + (label_len + 1)
        clear_width = args.width - (label_len + 1)
    end

    -- on state change
    ---@param value any new value
    function e.on_update(value)
        e.value = value.radiation

        -- clear old data and label
        e.window.setCursorPos(data_start, 1)
        e.window.write(util.spaces(clear_width))

        -- write data
        local data_str = util.sprintf(args.format, e.value)
        e.window.setCursorPos(data_start, 1)
        e.window.setTextColor(e.fg_bg.fgd)
        if args.commas then
            e.window.write(util.comma_format(data_str))
        else
            e.window.write(data_str)
        end

        -- write unit
        if args.lu_colors ~= nil then
            e.window.setTextColor(args.lu_colors.color_b)
        end
        e.window.write(" " .. value.unit)
    end

    -- set the value
    ---@param val any new value
    function e.set_value(val) e.on_update(val) end

    -- initial value draw
    e.on_update(types.new_zero_radiation_reading())

    return e.complete()
end

return rad
