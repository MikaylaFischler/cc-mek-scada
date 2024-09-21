-- Power Indicator Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class power_indicator_args
---@field label string indicator label
---@field unit string energy unit
---@field format string power format override (lua string format)
---@field rate boolean? whether to append /t to the end (power per tick)
---@field lu_colors? cpair label foreground color (a), unit foreground color (b)
---@field value number default value
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width integer length
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new power indicator
---@nodiscard
---@param args power_indicator_args
---@return graphics_element element, element_id id
local function power(args)
    element.assert(type(args.label) == "string", "label is a required field")
    element.assert(type(args.unit) == "string", "unit is a required field")
    element.assert(type(args.value) == "number", "value is a required field")
    element.assert(util.is_int(args.width), "width is a required field")

    args.height = 1

    -- create new graphics element base object
    local e = element.new(args)

    e.value = args.value

    local data_start = 0

    -- on state change
    ---@param value any new value
    function e.on_update(value)
        e.value = value

        local data_str, unit = util.power_format(value, args.unit, false, args.format)

        -- write data
        e.w_set_cur(data_start, 1)
        e.w_set_fgd(e.fg_bg.fgd)
        e.w_write(util.comma_format(data_str))

        -- write unit
        if args.lu_colors ~= nil then
            e.w_set_fgd(args.lu_colors.color_b)
        end

        -- append per tick if rate is set
        if args.rate == true then
            unit = unit .. "/t"
        end

        -- add space to unit so we don't end up with something like FEE after having kFE
        unit = util.strminw(unit, 5)

        e.w_write(" " .. unit)
    end

    -- set the value
    ---@param val any new value
    function e.set_value(val) e.on_update(val) end

    -- element redraw
    function e.redraw()
        if args.lu_colors ~= nil then e.w_set_fgd(args.lu_colors.color_a) end
        e.w_set_cur(1, 1)
        e.w_write(args.label)

        data_start = string.len(args.label) + 2
        if string.len(args.label) == 0 then data_start = 1 end

        e.on_update(e.value)
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return power
