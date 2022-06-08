-- Indicator Light Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class indicator_light_args
---@field text string indicator text
---@field colors cpair on/off colors (a/b respectively)
---@field min_text_width? integer text length if omitted
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field height? integer parent height if omitted
---@field fg_bg cpair foreground/background colors

-- new indicator light
---@param args indicator_light_args
local function indicator_light(args)
    -- determine width
    args.width = (args.min_text_width or string.len(args.text)) + 3

    -- create new graphics element base object
    local e = element.new(args)

    -- on/off blit strings
    local on_blit = util.strrep(args.colors.blit_a, 2)
    local off_blit = util.strrep(args.colors.blit_b, 2)

    -- write text and initial indicator light
    e.setCursorPos(1, 1)
    e.window.blit("   ", "000", off_blit .. e.fg_bg.blit_bkg)
    e.window.write(args.text)

    -- on state change
    ---@param new_state boolean indicator state
    function e.on_update(new_state)
        e.window.setCursorPos(1, 1)
        if new_state then
            e.window.blit("  ", "00", on_blit)
        else
            e.window.blit("  ", "00", off_blit)
        end
    end

    return e.get()
end

return indicator_light
