-- Data Indicator Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class data_indicator_args
---@field label string indicator label
---@field unit? string indicator unit
---@field format string data format (lua string format)
---@field label_unit_colors? cpair label foreground color (a), unit foreground color (b)
---@field initial_value any default value
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width integer length
---@field fg_bg? cpair foreground/background colors

-- new data indicator
---@param args data_indicator_args
local function data_indicator(args)
    assert(type(args.label) == "string", "graphics.elements.indicator_data: label is a required field")
    assert(type(args.format) == "string", "graphics.elements.indicator_data: format is a required field")
    assert(args.initial_value ~= nil, "graphics.elements.indicator_data: initial_value is a required field")
    assert(util.is_int(args.width), "graphics.elements.indicator_data: width is a required field")

    -- create new graphics element base object
    local e = element.new(args)

    -- label color
    if args.label_unit_colors ~= nil then
        e.window.setTextColor(args.label_unit_colors.color_a)
    end

    -- write label
    e.window.setCursorPos(1, 1)
    e.window.write(args.label)

    local data_start = string.len(args.label) + 2

    -- on state change
    ---@param value any new value
    function e.on_update(value)
        local data_str = util.sprintf(args.format, value)

        -- write data
        e.window.setCursorPos(data_start, 1)
        e.window.setTextColor(e.fg_bg.fgd)
        e.window.write(data_str)

        -- write label
        if args.unit ~= nil then
            if args.label_unit_colors ~= nil then
                e.window.setTextColor(args.label_unit_colors.color_b)
            end
            e.window.write(" " .. args.unit)
        end
    end

    -- initial value draw
    e.on_update(args.initial_value)

    return e.get()
end

return data_indicator
