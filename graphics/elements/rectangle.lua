-- Rectangle Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class rectangle_args
---@field border? graphics_border
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors

-- new rectangle
---@param args rectangle_args
---@return graphics_element element, element_id id
local function rectangle(args)
    -- offset children
    if args.border ~= nil then
        args.offset_x = args.border.width
        args.offset_y = args.border.width

        -- slightly different y offset if the border is set to even
        if args.border.even then
            local width_x2 = (2 * args.border.width)
            args.offset_y = math.floor(width_x2 / 3) + util.trinary(width_x2 % 3 > 0, 1, 0)
        end
    end

    -- create new graphics element base object
    local e = element.new(args)

    -- draw bordered box if requested
    -- element constructor will have drawn basic colored rectangle regardless
    if args.border ~= nil then
        e.window.setCursorPos(1, 1)

        local border_width = args.offset_x
        local border_height = args.offset_y
        local border_blit = colors.toBlit(args.border.color)
        local width_x2 = border_width * 2
        local inner_width = e.frame.w - width_x2

        -- check dimensions
        assert(width_x2 <= e.frame.w, "graphics.elements.rectangle: border too thick for width")
        assert(width_x2 <= e.frame.h, "graphics.elements.rectangle: border too thick for height")

        -- form the basic line strings and top/bottom blit strings
        local spaces = util.spaces(e.frame.w)
        local blit_fg = util.strrep(e.fg_bg.blit_fgd, e.frame.w)
        local blit_bg_sides = ""
        local blit_bg_top_bot = util.strrep(border_blit, e.frame.w)

        -- partial bars
        local p_a = util.spaces(border_width) .. util.strrep("\x8f", inner_width) .. util.spaces(border_width)
        local p_b = util.spaces(border_width) .. util.strrep("\x83", inner_width) .. util.spaces(border_width)
        local p_inv_fg = util.strrep(border_blit, border_width) .. util.strrep(e.fg_bg.blit_bkg, inner_width) ..
                            util.strrep(border_blit, border_width)
        local p_inv_bg = util.strrep(e.fg_bg.blit_bkg, border_width) .. util.strrep(border_blit, inner_width) ..
                            util.strrep(e.fg_bg.blit_bkg, border_width)

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
            e.window.setCursorPos(1, y)
            if y <= border_height then
                -- partial pixel fill
                if args.border.even and y == border_height then
                    if width_x2 % 3 == 1 then
                        e.window.blit(p_b, p_inv_bg, p_inv_fg)
                    elseif width_x2 % 3 == 2 then
                        e.window.blit(p_a, p_inv_bg, p_inv_fg)
                    else
                        -- skip line
                        e.window.blit(spaces, blit_fg, blit_bg_sides)
                    end
                else
                    e.window.blit(spaces, blit_fg, blit_bg_top_bot)
                end
            elseif y > (e.frame.h - border_width) then
                -- partial pixel fill
                if args.border.even and y == ((e.frame.h - border_width) + 1) then
                    if width_x2 % 3 == 1 then
                        e.window.blit(p_a, p_inv_fg, blit_bg_top_bot)
                    elseif width_x2 % 3 == 2 then
                        e.window.blit(p_b, p_inv_fg, blit_bg_top_bot)
                    else
                        -- skip line
                        e.window.blit(spaces, blit_fg, blit_bg_sides)
                    end
                else
                    e.window.blit(spaces, blit_fg, blit_bg_top_bot)
                end
            else
                e.window.blit(spaces, blit_fg, blit_bg_sides)
            end
        end
    end

    return e.complete()
end

return rectangle
