-- Tri-State Indicator Light Graphics Element

local element = require("graphics.element")

---@class tristate_indicator_light_args
---@field label string indicator label
---@field c1 color color for state 1
---@field c2 color color for state 2
---@field c3 color color for state 3
---@field min_label_width? integer label length if omitted
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field fg_bg? cpair foreground/background colors

-- new indicator light
---@param args tristate_indicator_light_args
---@return graphics_element element, element_id id
local function tristate_indicator_light(args)
    assert(type(args.label) == "string", "graphics.elements.indicators.trilight: label is a required field")
    assert(type(args.c1) == "integer", "graphics.elements.indicators.trilight: c1 is a required field")
    assert(type(args.c2) == "integer", "graphics.elements.indicators.trilight: c2 is a required field")
    assert(type(args.c3) == "integer", "graphics.elements.indicators.trilight: c3 is a required field")

    -- single line
    args.height = 1

    -- determine width
    args.width = math.max(args.min_label_width or 1, string.len(args.label)) + 2

    -- blit translations
    local c1 colors.toBlit(args.c1)
    local c2 colors.toBlit(args.c2)
    local c3 colors.toBlit(args.c3)

    -- create new graphics element base object
    local e = element.new(args)

    -- on state change
    ---@param new_state integer indicator state
    function e.on_update(new_state)
        e.window.setCursorPos(1, 1)
        if new_state == 2 then
            e.window.blit(" \x95", "0" .. c2, c2 .. e.fg_bg.blit_bkg)
        elseif new_state == 3 then
            e.window.blit(" \x95", "0" .. c3, c3 .. e.fg_bg.blit_bkg)
        else
            e.window.blit(" \x95", "0" .. c1, c1 .. e.fg_bg.blit_bkg)
        end
    end

    -- write label and initial indicator light
    e.on_update(0)
    e.window.write(args.label)

    return e.get()
end

return tristate_indicator_light
