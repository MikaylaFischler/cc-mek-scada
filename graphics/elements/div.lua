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

-- new div element
---@nodiscard
---@param args div_args
---@return graphics_element element, element_id id
local function div(args)
    -- create new graphics element base object
    return element.new(args).complete()
end

return div
