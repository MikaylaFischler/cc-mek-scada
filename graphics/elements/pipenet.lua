-- Pipe Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

---@class pipenet_args
---@field pipes table pipe list
---@field bg? color background color
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted

-- new pipe network
---@param args pipenet_args
---@return graphics_element element, element_id id
local function pipenet(args)
    assert(type(args.pipes) == "table", "graphics.elements.indicators.pipenet: pipes is a required field")

    args.width = 0
    args.height = 0

    -- determine width/height
    for i = 1, #args.pipes do
        local pipe = args.pipes[i]  ---@type pipe

        local true_w = pipe.w + math.min(pipe.x1, pipe.x2)
        local true_h = pipe.h + math.min(pipe.y1, pipe.y2)

        if true_w > args.width  then args.width  = true_w end
        if true_h > args.height then args.height = true_h end
    end

    args.x = args.x or 1
    args.y = args.y or 1

    if args.bg ~= nil then
        args.fg_bg = core.graphics.cpair(args.bg, args.bg)
    end

    -- create new graphics element base object
    local e = element.new(args)

    -- draw all pipes
    for p = 1, #args.pipes do
        local pipe = args.pipes[p]  ---@type pipe

        local x = 1 + pipe.x1
        local y = 1 + pipe.y1

        local x_step = util.trinary(pipe.x1 >= pipe.x2, -1, 1)
        local y_step = util.trinary(pipe.y1 >= pipe.y2, -1, 1)

        e.window.setCursorPos(x, y)

        local c = core.graphics.cpair(pipe.color, e.fg_bg.bkg)

        if pipe.align_tr then
            -- cross width then height
            for i = 1, pipe.w do
                if pipe.thin then
                    if i == pipe.w then
                        -- corner
                        if y_step > 0 then
                            e.window.blit("\x93", c.blit_bkg, c.blit_fgd)
                        else
                            e.window.blit("\x8e", c.blit_fgd, c.blit_bkg)
                        end
                    else
                        e.window.blit("\x8c", c.blit_fgd, c.blit_bkg)
                    end
                else
                    if i == pipe.w and y_step > 0 then
                        -- corner
                        e.window.blit(" ", c.blit_bkg, c.blit_fgd)
                    else
                        e.window.blit("\x8f", c.blit_fgd, c.blit_bkg)
                    end
                end

                x = x + x_step
                e.window.setCursorPos(x, y)
            end

            -- back up one
            x = x - x_step

            for _ = 1, pipe.h - 1 do
                y = y + y_step
                e.window.setCursorPos(x, y)

                if pipe.thin then
                    e.window.blit("\x95", c.blit_bkg, c.blit_fgd)
                else
                    e.window.blit(" ", c.blit_bkg, c.blit_fgd)
                end
            end
        else
            -- cross height then width
            for i = 1, pipe.h do
                if pipe.thin then
                    if i == pipe.h then
                        -- corner
                        if y_step < 0 then
                            e.window.blit("\x97", c.blit_bkg, c.blit_fgd)
                        else
                            e.window.blit("\x8d", c.blit_fgd, c.blit_bkg)
                        end
                    else
                        e.window.blit("\x95", c.blit_fgd, c.blit_bkg)
                    end
                else
                    if i == pipe.h and y_step < 0 then
                        -- corner
                        e.window.blit("\x83", c.blit_bkg, c.blit_fgd)
                    else
                        e.window.blit(" ", c.blit_bkg, c.blit_fgd)
                    end
                end

                y = y + y_step
                e.window.setCursorPos(x, y)
            end

            -- back up one
            y = y - y_step

            for _ = 1, pipe.w - 1 do
                x = x + x_step
                e.window.setCursorPos(x, y)

                if pipe.thin then
                    e.window.blit("\x8c", c.blit_fgd, c.blit_bkg)
                else
                    e.window.blit("\x83", c.blit_bkg, c.blit_fgd)
                end
            end
        end

    end

    return e.complete()
end

return pipenet
