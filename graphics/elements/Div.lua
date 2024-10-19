-- Div (Division, like in HTML) Graphics Element

local element = require("graphics.element")

---@class div_args
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- Create a new div container element.
---@nodiscard
---@param args div_args
---@return Div element, element_id id
return function (args)
    -- create new graphics element base object
    local e = element.new(args --[[@as graphics_args]])

    ---@class Div:graphics_element
    local Div, id = e.complete()

    return Div, id
end
