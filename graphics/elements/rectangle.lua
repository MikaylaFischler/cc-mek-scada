-- Rectangle Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class rectangle_args
---@field border? graphics_border
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg cpair foreground/background colors

-- new rectangle
---@param args rectangle_args
local function rectangle(args)
    -- create new graphics element base object
    local e = element.new(args)

    -- draw bordered box if requested
    -- element constructor will have drawn basic colored rectangle regardless
    if args.border ~= nil then
        e.setCursorPos(1, 1)

        local border_width_v = args.border.width
        local border_width_h = util.trinary(args.border.even, args.border.width * 2, args.border.width)
        local border_blit = colors.toBlit(args.border.color)
        local spaces = ""
        local blit_fg = ""
        local blit_bg_top_bot = ""
        local blit_bg_sides = ""

        -- check dimensions
        assert(border_width_v * 2 <= e.frame.w, "graphics.elements.rectangle: border too thick for width")
        assert(border_width_h * 2 <= e.frame.h, "graphics.elements.rectangle: border too thick for height")

        -- form the basic and top/bottom blit strings
        spaces = util.spaces(e.frame.w)
        blit_fg = util.strrep(e.fg_bg.blit_fgd, e.frame.w)
        blit_bg_top_bot = util.strrep(border_blit, e.frame.w)

        -- form the body blit strings (sides are border, inside is normal)
        for x = 1, e.frame.w do
            -- edges get border color, center gets normal
            if x <= border_width_h or x > (e.frame.w - border_width_h) then
                blit_bg_sides = blit_bg_sides .. border_blit
            else
                blit_bg_sides = blit_bg_sides .. e.fg_bg.blit_bkg
            end
        end

        -- draw rectangle with borders
        for y = 1, e.frame.h do
            e.setCursorPos(1, y)
            if y <= border_width_v or y > (e.frame.h - border_width_v) then
                e.blit(spaces, blit_fg, blit_bg_top_bot)
            else
                e.blit(spaces, blit_fg, blit_bg_sides)
            end
        end
    end

    return e.get()
end

return rectangle
