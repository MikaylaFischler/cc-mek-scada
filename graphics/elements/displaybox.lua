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

-- new root display box
---@nodiscard
---@param args displaybox_args
---@return graphics_element element, element_id id
local function displaybox(args)
    -- create new graphics element base object
    return element.new(args).complete()
end

return displaybox
