-- Data Indicator Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

-- format a number string with commas as the thousands separator
--
-- subtracts from spaces at the start if present for each comma used
---@param num string number string
---@return string
local function comma_format(num)
    local formatted = num
    local commas = 0
    local i = 1

    while i > 0 do
        formatted, i = formatted:gsub("^(%s-%d+)(%d%d%d)", '%1,%2')
        if i > 0 then commas = commas + 1 end
    end

    local _, num_spaces = formatted:gsub(" %s-", "")
    local remove = math.min(num_spaces, commas)

    formatted = string.sub(formatted, remove + 1)

    return formatted
end

---@class data_indicator_args
---@field label string indicator label
---@field unit? string indicator unit
---@field format string data format (lua string format)
---@field commas boolean whether to use commas if a number is given (default to false)
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

    local data_start = string.len(args.label) + 2

    -- on state change
    ---@param value any new value
    function e.on_update(value)
        local data_str = util.sprintf(args.format, value)

        -- write data
        e.window.setCursorPos(data_start, 1)
        e.window.setTextColor(e.fg_bg.fgd)
        if args.commas then
            e.window.write(comma_format(data_str))
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

    -- initial value draw
    e.on_update(args.value)

    return e.complete()
end

return data
