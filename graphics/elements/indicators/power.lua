-- Power Indicator Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class power_indicator_args
---@field label string indicator label
---@field format string power format override (lua string format)
---@field rate boolean? whether to append /t to the end (power per tick)
---@field lu_colors? cpair label foreground color (a), unit foreground color (b)
---@field value any default value
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width integer length
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new power indicator
---@nodiscard
---@param args power_indicator_args
---@return graphics_element element, element_id id
local function power(args)
    assert(args.value ~= nil, "graphics.elements.indicators.power: value is a required field")
    assert(util.is_int(args.width), "graphics.elements.indicators.power: width is a required field")

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

    local data_start = string.len(args.label) + 2
    if string.len(args.label) == 0 then data_start = 1 end

    -- on state change
    ---@param value any new value
    function e.on_update(value)
        e.value = value

        local data_str, unit = util.power_format(value, false, args.format)

        -- write data
        e.window.setCursorPos(data_start, 1)
        e.window.setTextColor(e.fg_bg.fgd)
        e.window.write(util.comma_format(data_str))

        -- write unit
        if args.lu_colors ~= nil then
            e.window.setTextColor(args.lu_colors.color_b)
        end

        -- append per tick if rate is set
        -- add space to FE so we don't end up with FEE (after having kFE for example)
        if args.rate == true then
            unit = unit .. "/t"
            if unit == "FE/t" then unit = "FE/t " end
        else
            if unit == "FE" then unit = "FE " end
        end

        e.window.write(" " .. unit)
    end

    -- set the value
    ---@param val any new value
    function e.set_value(val) e.on_update(val) end

    -- initial value draw
    e.on_update(args.value)

    return e.complete()
end

return power
