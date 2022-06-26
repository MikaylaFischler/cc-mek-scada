-- Pipe Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class pipe_args
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field end_x integer end of pipe
---@field end_y integer end of pipe
---@field thin boolean true for 1 subpixels, false (default) for 2
---@field align_tr? boolean false to align bottom left (default), true to align top right
---@field fg_bg? cpair foreground/background colors

-- new pipe
---@param args pipe_args
local function pipe(args)
    assert(util.is_int(args.end_x), "graphics.elements.indicators.pipe: end_x is a required field")
    assert(util.is_int(args.end_y), "graphics.elements.indicators.pipe: end_y is a required field")

    args.x = args.x or 1
    args.y = args.y or 1
    args.width = args.end_x - args.x
    args.height = args.end_y - args.y

    -- create new graphics element base object
    local e = element.new(args)

    -- draw pipe

    local align_tr = args.align_tr or false

    local x = 1
    local y = 1

    if align_tr then
        -- cross width then height
        for i = 1, args.width do
            if args.thin then
                if i == args.width then
                    -- corner
                    e.window.blit("\x93", e.fg_bg.blit_bkg, e.fg_bg.blit_fgd)
                else
                    e.window.blit("\x8c", e.fg_bg.blit_fgd, e.fg_bg.blit_bkg)
                end
            else
                if i == args.width then
                    -- corner
                    e.window.blit(" ", e.fg_bg.blit_bkg, e.fg_bg.blit_fgd)
                else
                    e.window.blit("\x8f", e.fg_bg.blit_fgd, e.fg_bg.blit_bkg)
                end
            end

            x = x + 1
            e.window.setCursorPos(x, y)
        end

        -- back up one
        x = x - 1

        for _ = 1, args.height do
            y = y + 1
            e.window.setCursorPos(x, y)

            if args.thin then
                e.window.blit("\x95", e.fg_bg.blit_bkg, e.fg_bg.blit_fgd)
            else
                e.window.blit(" ", e.fg_bg.blit_bkg, e.fg_bg.blit_fgd)
            end
        end
    else
        -- cross height then width
        for i = 1, args.height do
            if args.thin then
                if i == args.height then
                    -- corner
                    e.window.blit("\x8d", e.fg_bg.blit_fgd, e.fg_bg.blit_bkg)
                else
                    e.window.blit("\x95", e.fg_bg.blit_fgd, e.fg_bg.blit_bkg)
                end
            else
                e.window.blit(" ", e.fg_bg.blit_bkg, e.fg_bg.blit_fgd)
            end

            y = y + 1
            e.window.setCursorPos(x, y)
        end

        -- back up one
        y = y - 1

        for _ = 1, args.width do
            x = x + 1
            e.window.setCursorPos(x, y)

            if args.thin then
                e.window.blit("\x8c", e.fg_bg.blit_fgd, e.fg_bg.blit_bkg)
            else
                e.window.blit("\x83", e.fg_bg.blit_bkg, e.fg_bg.blit_fgd)
            end
        end
    end

    return e.get()
end

return pipe
