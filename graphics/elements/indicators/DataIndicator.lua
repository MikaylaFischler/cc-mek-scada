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
---@field y? integer auto incremented if omitted
---@field width integer length
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new data indicator
---@nodiscard
---@param args data_indicator_args
---@return graphics_element element, element_id id
local function data(args)
    element.assert(type(args.label) == "string", "label is a required field")
    element.assert(type(args.format) == "string", "format is a required field")
    element.assert(args.value ~= nil, "value is a required field")
    element.assert(util.is_int(args.width), "width is a required field")

    args.height = 1

    -- create new graphics element base object
    local e = element.new(args)

    e.value = args.value

    local value_color = e.fg_bg.fgd
    local label_len   = string.len(args.label)
    local data_start  = 1
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
        e.w_set_cur(data_start, 1)
        e.w_write(util.spaces(clear_width))

        -- write data
        local data_str = util.sprintf(args.format, value)
        e.w_set_cur(data_start, 1)
        e.w_set_fgd(value_color)
        if args.commas then
            e.w_write(util.comma_format(data_str))
        else
            e.w_write(data_str)
        end

        -- write label
        if args.unit ~= nil then
            if args.lu_colors ~= nil then
                e.w_set_fgd(args.lu_colors.color_b)
            end
            e.w_write(" " .. args.unit)
        end
    end

    -- set the value
    ---@param val any new value
    function e.set_value(val) e.on_update(val) end

    -- change the foreground color of the value, or all text if no label/unit colors provided
    ---@param c color
    function e.recolor(c)
        value_color = c
        e.on_update(e.value)
    end

    -- element redraw
    function e.redraw()
        if args.lu_colors ~= nil then e.w_set_fgd(args.lu_colors.color_a) end
        e.w_set_cur(1, 1)
        e.w_write(args.label)

        e.on_update(e.value)
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return data
