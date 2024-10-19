-- Root Display Box Graphics Element

local element = require("graphics.element")

---@class displaybox_args
---@field window table
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- Create a root display box.
---@nodiscard
---@param args displaybox_args
---@return DisplayBox element, element_id id
return function (args)
    -- create new graphics element base object
    local e = element.new(args --[[@as graphics_args]])

    ---@class DisplayBox:graphics_element
    local DisplayBox, id = e.complete()

    return DisplayBox, id
end
