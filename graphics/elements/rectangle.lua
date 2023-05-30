-- Rectangle Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class rectangle_args
---@field border? graphics_border
---@field thin? boolean true to use extra thin even borders
---@field even_inner? boolean true to make the inner area of a border even
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new rectangle
---@param args rectangle_args
---@return graphics_element element, element_id id
local function rectangle(args)
    assert(args.border ~= nil or args.thin ~= true, "graphics.elements.rectangle: thin requires border to be provided")

    -- if thin, then width will always need to be 1
    if args.thin == true then
        args.border.width = 1
        args.border.even = true
    end

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
        local blit_fg_sides = blit_fg
        local blit_bg_sides = ""
        local blit_bg_top_bot = util.strrep(border_blit, e.frame.w)

        -- partial bars
        local p_a, p_b, p_s
        if args.thin == true then
            if args.even_inner == true then
                p_a = "\x9c" .. util.strrep("\x8c", inner_width) .. "\x93"
                p_b = "\x8d" .. util.strrep("\x8c", inner_width) .. "\x8e"
            else
                p_a = "\x97" .. util.strrep("\x83", inner_width) .. "\x94"
                p_b = "\x8a" .. util.strrep("\x8f", inner_width) .. "\x85"
            end

            p_s = "\x95" .. util.spaces(inner_width) .. "\x95"
        else
            if args.even_inner == true then
                p_a = util.strrep("\x83", inner_width + width_x2)
                p_b = util.strrep("\x8f", inner_width + width_x2)
            else
                p_a = util.spaces(border_width) .. util.strrep("\x8f", inner_width) .. util.spaces(border_width)
                p_b = util.spaces(border_width) .. util.strrep("\x83", inner_width) .. util.spaces(border_width)
            end

            p_s = spaces
        end

        local p_inv_fg = util.strrep(border_blit, border_width) .. util.strrep(e.fg_bg.blit_bkg, inner_width) ..
                            util.strrep(border_blit, border_width)
        local p_inv_bg = util.strrep(e.fg_bg.blit_bkg, border_width) .. util.strrep(border_blit, inner_width) ..
                            util.strrep(e.fg_bg.blit_bkg, border_width)

        if args.thin == true then
            p_inv_fg = e.fg_bg.blit_bkg .. util.strrep(e.fg_bg.blit_bkg, inner_width) .. util.strrep(border_blit, border_width)
            p_inv_bg = border_blit .. util.strrep(border_blit, inner_width) .. util.strrep(e.fg_bg.blit_bkg, border_width)

            blit_fg_sides = border_blit .. util.strrep(e.fg_bg.blit_bkg, inner_width) .. e.fg_bg.blit_bkg
        end

        -- form the body blit strings (sides are border, inside is normal)
        for x = 1, e.frame.w do
            -- edges get border color, center gets normal
            if x <= border_width or x > (e.frame.w - border_width) then
                if args.thin and x == 1 then
                    blit_bg_sides = blit_bg_sides .. e.fg_bg.blit_bkg
                else
                    blit_bg_sides = blit_bg_sides .. border_blit
                end
            else
                blit_bg_sides = blit_bg_sides .. e.fg_bg.blit_bkg
            end
        end

        -- draw rectangle with borders
        for y = 1, e.frame.h do
            e.window.setCursorPos(1, y)
            -- top border
            if y <= border_height then
                -- partial pixel fill
                if args.border.even and y == border_height then
                    if args.thin == true then
                        e.window.blit(p_a, p_inv_bg, p_inv_fg)
                    else
                        local _fg = util.trinary(args.even_inner == true, util.strrep(e.fg_bg.blit_bkg, e.frame.w), p_inv_bg)
                        local _bg = util.trinary(args.even_inner == true, blit_bg_top_bot, p_inv_fg)

                        if width_x2 % 3 == 1 then
                            e.window.blit(p_b, _fg, _bg)
                        elseif width_x2 % 3 == 2 then
                            e.window.blit(p_a, _fg, _bg)
                        else
                            -- skip line
                            e.window.blit(spaces, blit_fg, blit_bg_sides)
                        end
                    end
                else
                    e.window.blit(spaces, blit_fg, blit_bg_top_bot)
                end
            -- bottom border
            elseif y > (e.frame.h - border_width) then
                -- partial pixel fill
                if args.border.even and y == ((e.frame.h - border_width) + 1) then
                    if args.thin == true then
                        if args.even_inner == true then
                            e.window.blit(p_b, blit_bg_top_bot, util.strrep(e.fg_bg.blit_bkg, e.frame.w))
                        else
                            e.window.blit(p_b, util.strrep(e.fg_bg.blit_bkg, e.frame.w), blit_bg_top_bot)
                        end
                    else
                        local _fg = util.trinary(args.even_inner == true, blit_bg_top_bot, p_inv_fg)
                        local _bg = util.trinary(args.even_inner == true, util.strrep(e.fg_bg.blit_bkg, e.frame.w), blit_bg_top_bot)

                        if width_x2 % 3 == 1 then
                            e.window.blit(p_a, _fg, _bg)
                        elseif width_x2 % 3 == 2 then
                            e.window.blit(p_b, _fg, _bg)
                        else
                            -- skip line
                            e.window.blit(spaces, blit_fg, blit_bg_sides)
                        end
                    end
                else
                    e.window.blit(spaces, blit_fg, blit_bg_top_bot)
                end
            else
                if args.thin == true then
                    e.window.blit(p_s, blit_fg_sides, blit_bg_sides)
                else
                    e.window.blit(p_s, blit_fg, blit_bg_sides)
                end
            end
        end
    end

    return e.complete()
end

return rectangle
