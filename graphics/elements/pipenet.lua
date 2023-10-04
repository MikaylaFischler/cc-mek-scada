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
---@field y? integer auto incremented if omitted
---@field hidden? boolean true to hide on initial draw

---@class _pipe_map_entry
---@field atr boolean align top right (or bottom left for false)
---@field thin boolean thin pipe or not
---@field fg string foreground blit
---@field bg string background blit

-- new pipe network
---@param args pipenet_args
---@return graphics_element element, element_id id
local function pipenet(args)
    element.assert(type(args.pipes) == "table", "pipes is a required field")

    args.width = 0
    args.height = 0

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
        args.fg_bg = core.cpair(args.bg, args.bg)
    end

    -- create new graphics element base object
    local e = element.new(args)

    -- determine if there are any thin pipes involved
    local any_thin = false
    for p = 1, #args.pipes do
        any_thin = args.pipes[p].thin
        if any_thin then break end
    end

    -- draw all pipes by drawing out lines
    local function vector_draw()
        for p = 1, #args.pipes do
            local pipe = args.pipes[p]  ---@type pipe

            local x = 1 + pipe.x1
            local y = 1 + pipe.y1

            local x_step = util.trinary(pipe.x1 >= pipe.x2, -1, 1)
            local y_step = util.trinary(pipe.y1 >= pipe.y2, -1, 1)

            if pipe.thin then
                x_step = util.trinary(pipe.x1 == pipe.x2, 0, x_step)
                y_step = util.trinary(pipe.y1 == pipe.y2, 0, y_step)
            end

            e.w_set_cur(x, y)

            local c = core.cpair(pipe.color, e.fg_bg.bkg)

            if pipe.align_tr then
                -- cross width then height
                for i = 1, pipe.w do
                    if pipe.thin then
                        if i == pipe.w then
                            -- corner
                            if y_step > 0 then
                                e.w_blit("\x93", c.blit_bkg, c.blit_fgd)
                            else
                                e.w_blit("\x8e", c.blit_fgd, c.blit_bkg)
                            end
                        else
                            e.w_blit("\x8c", c.blit_fgd, c.blit_bkg)
                        end
                    else
                        if i == pipe.w and y_step > 0 then
                            -- corner
                            e.w_blit(" ", c.blit_bkg, c.blit_fgd)
                        else
                            e.w_blit("\x8f", c.blit_fgd, c.blit_bkg)
                        end
                    end

                    x = x + x_step
                    e.w_set_cur(x, y)
                end

                -- back up one
                x = x - x_step

                for _ = 1, pipe.h - 1 do
                    y = y + y_step
                    e.w_set_cur(x, y)

                    if pipe.thin then
                        e.w_blit("\x95", c.blit_bkg, c.blit_fgd)
                    else
                        e.w_blit(" ", c.blit_bkg, c.blit_fgd)
                    end
                end
            else
                -- cross height then width
                for i = 1, pipe.h do
                    if pipe.thin then
                        if i == pipe.h then
                            -- corner
                            if y_step < 0 then
                                e.w_blit("\x97", c.blit_bkg, c.blit_fgd)
                            elseif y_step > 0 then
                                e.w_blit("\x8d", c.blit_fgd, c.blit_bkg)
                            else
                                e.w_blit("\x8c", c.blit_fgd, c.blit_bkg)
                            end
                        else
                            e.w_blit("\x95", c.blit_fgd, c.blit_bkg)
                        end
                    else
                        if i == pipe.h and y_step < 0 then
                            -- corner
                            e.w_blit("\x83", c.blit_bkg, c.blit_fgd)
                        else
                            e.w_blit(" ", c.blit_bkg, c.blit_fgd)
                        end
                    end

                    y = y + y_step
                    e.w_set_cur(x, y)
                end

                -- back up one
                y = y - y_step

                for _ = 1, pipe.w - 1 do
                    x = x + x_step
                    e.w_set_cur(x, y)

                    if pipe.thin then
                        e.w_blit("\x8c", c.blit_fgd, c.blit_bkg)
                    else
                        e.w_blit("\x83", c.blit_bkg, c.blit_fgd)
                    end
                end
            end
        end
    end

    -- draw a particular map cell
    ---@param map table 2D cell map
    ---@param x integer x coord
    ---@param y integer y coord
    local function draw_map_cell(map, x, y)
        local entry = map[x][y] ---@type _pipe_map_entry already confirmed not false
        local char
        local invert = false

        local function check(cx, cy)
            return (map[cx] ~= nil) and (map[cx][cy] ~= nil) and (map[cx][cy] ~= false) and (map[cx][cy].fg == entry.fg)
        end

        if entry.thin then
            if check(x - 1, y) then -- if left
                if check(x, y - 1) then -- if above
                    if check(x + 1, y) then -- if right
                        if check(x, y + 1) then -- if below
                            char = util.trinary(entry.atr, "\x91", "\x9d")
                            invert = entry.atr
                        else -- not below
                            char = util.trinary(entry.atr, "\x8e", "\x8d")
                        end
                    else -- not right
                        if check(x, y + 1) then -- if below
                            char = util.trinary(entry.atr, "\x91", "\x95")
                            invert = entry.atr
                        else -- not below
                            char = util.trinary(entry.atr, "\x8e", "\x85")
                        end
                    end
                elseif check(x, y + 1) then-- not above, if below
                    if check(x + 1, y) then -- if right
                        char = util.trinary(entry.atr, "\x93", "\x9c")
                        invert = entry.atr
                    else -- not right
                        char = util.trinary(entry.atr, "\x93", "\x94")
                        invert = entry.atr
                    end
                else -- not above, not below
                    char = "\x8c"
                end
            elseif check(x + 1, y) then -- not left, if right
                if check(x, y - 1) then -- if above
                    if check(x, y + 1) then -- if below
                        char = util.trinary(entry.atr, "\x95", "\x9d")
                        invert = entry.atr
                    else -- not below
                        char = util.trinary(entry.atr, "\x8a", "\x8d")
                    end
                else -- not above
                    if check(x, y + 1) then -- if below
                        char = util.trinary(entry.atr, "\x97", "\x9c")
                        invert = entry.atr
                    else -- not below
                        char = "\x8c"
                    end
                end
            else -- not left, not right
                char = "\x95"
                invert = entry.atr
            end
        else
            if check(x, y - 1) then -- above
                -- not below and (if left or right)
                if (not check(x, y + 1)) and (check(x - 1, y) or check(x + 1, y)) then
                    char = util.trinary(entry.atr, "\x8f", " ")
                    invert = not entry.atr
                else -- not below w/ sides only
                    char = " "
                    invert = true
                end
            elseif check(x, y + 1) then -- not above, if below
                -- if left or right
                if (check(x - 1, y) or check(x + 1, y)) then
                    char = "\x83"
                    invert = true
                else -- not left or right
                    char = " "
                    invert = true
                end
            else -- not above, not below
                char = util.trinary(entry.atr, "\x8f", "\x83")
                invert = not entry.atr
            end
        end

        e.w_set_cur(x, y)

        if invert then
            e.w_blit(char, entry.bg, entry.fg)
        else
            e.w_blit(char, entry.fg, entry.bg)
        end
    end

    -- draw all pipes by assembling and marking up a 2D map<br>
    -- this is an easy way to check adjacent blocks, which is required to properly draw thin pipes
    local function map_draw()
        local map = {}

        for x = 1, args.width do
            table.insert(map, {})
            for _ = 1, args.height do table.insert(map[x], false) end
        end

        -- build map
        for p = 1, #args.pipes do
            local pipe = args.pipes[p]  ---@type pipe

            local x = 1 + pipe.x1
            local y = 1 + pipe.y1

            local x_step = util.trinary(pipe.x1 >= pipe.x2, -1, 1)
            local y_step = util.trinary(pipe.y1 >= pipe.y2, -1, 1)

            local entry = { atr = pipe.align_tr, thin = pipe.thin, fg = colors.toBlit(pipe.color), bg = e.fg_bg.blit_bkg }

            if pipe.align_tr then
                -- cross width then height
                for _ = 1, pipe.w do
                    map[x][y] = entry
                    x = x + x_step
                end

                x = x - x_step  -- back up one

                for _ = 1, pipe.h do
                    map[x][y] = entry
                    y = y + y_step
                end
            else
                -- cross height then width
                for _ = 1, pipe.h do
                    map[x][y] = entry
                    y = y + y_step
                end

                y = y - y_step  -- back up one

                for _ = 1, pipe.w do
                    map[x][y] = entry
                    x = x + x_step
                end
            end
        end

        -- render
        for x = 1, args.width do
            for y = 1, args.height do
                if map[x][y] ~= false then draw_map_cell(map, x, y) end
            end
        end
    end

    -- element redraw
    function e.redraw()
        if any_thin then map_draw() else vector_draw() end
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return pipenet
