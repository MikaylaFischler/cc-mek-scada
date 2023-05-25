-- Color Map Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class colormap_args
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field hidden? boolean true to hide on initial draw

-- new color map
---@param args colormap_args
---@return graphics_element element, element_id id
local function colormap(args)
    local bkg = "008877FFCCEE114455DD9933BBAA2266"
    local spaces = util.spaces(32)

    args.width = 32
    args.height = 1

    -- create new graphics element base object
    local e = element.new(args)

    -- draw color map
    e.window.setCursorPos(1, 1)
    e.window.blit(spaces, bkg, bkg)

    return e.get()
end

return colormap
