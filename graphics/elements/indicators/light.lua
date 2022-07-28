-- Indicator Light Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class indicator_light_args
---@field label string indicator label
---@field colors cpair on/off colors (a/b respectively)
---@field min_label_width? integer label length if omitted
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field fg_bg? cpair foreground/background colors

-- new indicator light
---@param args indicator_light_args
---@return graphics_element element, element_id id
local function indicator_light(args)
    assert(type(args.label) == "string", "graphics.elements.indicators.light: label is a required field")
    assert(type(args.colors) == "table", "graphics.elements.indicators.light: colors is a required field")

    -- single line
    args.height = 1

    -- determine width
    args.width = math.max(args.min_label_width or 1, string.len(args.label)) + 2

    -- create new graphics element base object
    local e = element.new(args)

    -- on state change
    ---@param new_state boolean indicator state
    function e.on_update(new_state)
        e.window.setCursorPos(1, 1)
        if new_state then
            e.window.blit(" \x95", "0" .. args.colors.blit_a, args.colors.blit_a .. e.fg_bg.blit_bkg)
        else
            e.window.blit(" \x95", "0" .. args.colors.blit_b, args.colors.blit_b .. e.fg_bg.blit_bkg)
        end
    end

    -- write label and initial indicator light
    e.on_update(false)
    e.window.write(args.label)

    return e.get()
end

return indicator_light
