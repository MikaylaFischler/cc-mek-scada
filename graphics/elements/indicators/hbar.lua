-- Horizontal Bar Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class hbar_args
---@field show_percent? boolean whether or not to show the percent
---@field bar_fg_bg? cpair bar foreground/background colors if showing percent
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new horizontal bar
---@nodiscard
---@param args hbar_args
---@return graphics_element element, element_id id
local function hbar(args)
    -- create new graphics element base object
    local e = element.new(args)

    e.value = 0.0

    -- bar width is width - 5 characters for " 100%" if showing percent
    local bar_width = util.trinary(args.show_percent, e.frame.w - 5, e.frame.w)

    element.assert(bar_width > 0, "too small for bar")

    local last_num_bars = -1

    -- determine bar colors
    local bar_bkg = e.fg_bg.blit_bkg
    local bar_fgd = e.fg_bg.blit_fgd
    if args.bar_fg_bg ~= nil then
        bar_bkg = args.bar_fg_bg.blit_bkg
        bar_fgd = args.bar_fg_bg.blit_fgd
    end

    -- handle data changes
    ---@param fraction number 0.0 to 1.0
    function e.on_update(fraction)
        e.value = fraction

        -- enforce minimum and maximum
        if fraction < 0 then
            fraction = 0.0
        elseif fraction > 1 then
            fraction = 1.0
        end

        -- compute number of bars
        local num_bars = util.round(fraction * (bar_width * 2))

        -- redraw bar if changed
        if num_bars ~= last_num_bars then
            last_num_bars = num_bars

            local fgd = ""
            local bkg = ""
            local spaces = ""

            -- fill percentage
            for _ = 1, num_bars / 2 do
                spaces = spaces .. " "
                fgd = fgd .. bar_fgd
                bkg = bkg .. bar_bkg
            end

            -- add fractional bar if needed
            if num_bars % 2 == 1 then
                spaces = spaces .. "\x95"
                fgd = fgd .. bar_bkg
                bkg = bkg .. bar_fgd
            end

            -- pad background
            for _ = 1, ((bar_width * 2) - num_bars) / 2 do
                spaces = spaces .. " "
                fgd = fgd .. bar_bkg
                bkg = bkg .. bar_bkg
            end

            -- draw bar
            for y = 1, e.frame.h do
                e.w_set_cur(1, y)
                -- intentionally swapped fgd/bkg since we use spaces as fill, but they are the opposite
                e.w_blit(spaces, bkg, fgd)
            end
        end

        -- update percentage
        if args.show_percent then
            e.w_set_cur(bar_width + 2, math.max(1, math.ceil(e.frame.h / 2)))
            e.w_write(util.sprintf("%3.0f%%", fraction * 100))
        end
    end

    -- change bar color
    ---@param bar_fg_bg cpair new bar colors
    function e.recolor(bar_fg_bg)
        bar_bkg = bar_fg_bg.blit_bkg
        bar_fgd = bar_fg_bg.blit_fgd
        e.redraw()
    end

    -- set the percentage value
    ---@param val number 0.0 to 1.0
    function e.set_value(val) e.on_update(val) end

    -- element redraw
    function e.redraw()
        last_num_bars = -1
        e.on_update(e.value)
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return hbar
