-- "Basketweave" Tiling Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class tiling_args
---@field fill_c cpair colors to fill with
---@field even? boolean whether to account for rectangular pixels
---@field border? graphics_border
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg cpair foreground/background colors

-- new tiling box
---@param args tiling_args
local function tiling(args)
    -- create new graphics element base object
    local e = element.new(args)

    -- draw tiling box

    local fill_a = args.fill_c.blit_a
    local fill_b = args.fill_c.blit_b

    local even = args.even == true

    local start_x = 1
    local start_y = 1
    local width = e.frame.w
    local height = e.frame.h
    local alternator = true

    -- border
    if args.border ~= nil then
        e.window.setBackgroundColor(args.border.color)
        e.window.clear()

        start_x = 1 + util.trinary(args.border.even, args.border.width * 2, args.border.width)
        start_y = 1 + args.border.width

        width = width - (2 * util.trinary(args.border.even, args.border.width * 2, args.border.width))
        height = height - (2 * args.border.width)
    end

    -- check dimensions
    assert(start_x <= width, "graphics.elements.tiling: start_x > width")
    assert(start_y <= height, "graphics.elements.tiling: start_y > height")
    assert(width > 0, "graphics.elements.tiling: width <= 0")
    assert(height > 0, "graphics.elements.tiling: height <= 0")

    -- create pattern
    for y = start_y, height do
        e.window.setCursorPos(1, y)
        for _ = start_x, width do
            if alternator then
                if even then
                    e.window.blit("  ", "00", fill_a .. fill_a)
                else
                    e.window.blit(" ", "0", fill_a)
                end
            else
                if even then
                    e.window.blit("  ", "00", fill_b .. fill_b)
                else
                    e.window.blit(" ", "0", fill_b)
                end
            end

            alternator = not alternator
        end
    end

    return e.get()
end

return tiling
