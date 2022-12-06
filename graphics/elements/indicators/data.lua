-- Data Indicator Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class data_indicator_args
---@field label string indicator label
---@field unit? string indicator unit
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

-- new data indicator
---@param args data_indicator_args
---@return graphics_element element, element_id id
local function data(args)
    assert(type(args.label) == "string", "graphics.elements.indicators.data: label is a required field")
    assert(type(args.format) == "string", "graphics.elements.indicators.data: format is a required field")
    assert(args.value ~= nil, "graphics.elements.indicators.data: value is a required field")
    assert(util.is_int(args.width), "graphics.elements.indicators.data: width is a required field")

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
        e.value = value

        -- clear old data and label
        e.window.setCursorPos(data_start, 1)
        e.window.write(util.spaces(clear_width))

        -- write data
        local data_str = util.sprintf(args.format, value)
        e.window.setCursorPos(data_start, 1)
        e.window.setTextColor(e.fg_bg.fgd)
        if args.commas then
            e.window.write(util.comma_format(data_str))
        else
            e.window.write(data_str)
        end

        -- write label
        if args.unit ~= nil then
            if args.lu_colors ~= nil then
                e.window.setTextColor(args.lu_colors.color_b)
            end
            e.window.write(" " .. args.unit)
        end
    end

    -- set the value
    ---@param val any new value
    function e.set_value(val) e.on_update(val) end

    -- initial value draw
    e.on_update(args.value)

    return e.get()
end

return data
