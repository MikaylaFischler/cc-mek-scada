-- Rectangle Graphics Element

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
    -- create new graphics element rectangle object
    local e = element.new(args)

    -- draw bordered box if requested
    -- element constructor will have drawn basic colored rectangle regardless
    if args.border ~= nil then
        assert(args.border.width * 2 <= e.frame.w, "graphics.elements.rectangle: border too thick for width")
        assert(args.border.width * 2 <= e.frame.h, "graphics.elements.rectangle: border too thick for height")

        e.setCursorPos(1, 1)

        local border_width = args.border.width
        local border_blit = colors.toBlit(args.border.color)
        local spaces = ""
        local blit_fg = ""
        local blit_bg_top_bot = ""
        local blit_bg_sides = ""

        -- form the basic and top/bottom blit strings
        for _ = 1, e.frame.w do
            spaces = spaces .. " "
            blit_fg = blit_fg .. e.fg_bg.blit_fgd
            blit_bg_top_bot = blit_bg_top_bot .. border_blit
        end

        -- form the body blit strings (sides are border, inside is normal)
        for x = 1, e.frame.w do
            -- edges get border color, center gets normal
            if x <= border_width or x > (e.frame.w - border_width) then
                blit_bg_sides = blit_bg_sides .. border_blit
            else
                blit_bg_sides = blit_bg_sides .. e.fg_bg.blit_bkg
            end
        end

        -- draw rectangle with borders
        for y = 1, e.frame.h do
            e.setCursorPos(y, 1)
            if y <= border_width or y > (e.frame.h - border_width) then
                e.blit(spaces, blit_fg, blit_bg_top_bot)
            else
                e.blit(spaces, blit_fg, blit_bg_sides)
            end
        end
    end

    return e.get()
end

return rectangle
