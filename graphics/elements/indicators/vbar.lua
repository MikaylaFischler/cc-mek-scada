-- Vertical Bar Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class vbar_args
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new vertical bar
---@nodiscard
---@param args vbar_args
---@return graphics_element element, element_id id
local function vbar(args)
    -- create new graphics element base object
    local e = element.new(args)

    e.value = 0.0

    local last_num_bars = -1

    local fgd = string.rep(e.fg_bg.blit_fgd, e.frame.w)
    local bkg = string.rep(e.fg_bg.blit_bkg, e.frame.w)
    local spaces = util.spaces(e.frame.w)
    local one_third = string.rep("\x8f", e.frame.w)
    local two_thirds = string.rep("\x83", e.frame.w)

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
        local num_bars = util.round(fraction * (e.frame.h * 3))

        -- redraw only if number of bars has changed
        if num_bars ~= last_num_bars then
            last_num_bars = num_bars

            local y = e.frame.h
            e.w_set_cur(1, y)

            -- fill percentage
            for _ = 1, num_bars / 3 do
                e.w_blit(spaces, bkg, fgd)
                y = y - 1
                e.w_set_cur(1, y)
            end

            -- add fractional bar if needed
            if num_bars % 3 == 1 then
                e.w_blit(one_third, bkg, fgd)
                y = y - 1
            elseif num_bars % 3 == 2 then
                e.w_blit(two_thirds, bkg, fgd)
                y = y - 1
            end

            -- fill the rest blank
            while y > 0 do
                e.w_set_cur(1, y)
                e.w_blit(spaces, fgd, bkg)
                y = y - 1
            end
        end
    end

    -- set the percentage value
    ---@param val number 0.0 to 1.0
    function e.set_value(val) e.on_update(val) end

    -- element redraw
    function e.redraw()
        last_num_bars = -1
        e.on_update(e.value)
    end

    -- change bar color
    ---@param fg_bg cpair new bar colors
    function e.recolor(fg_bg)
        fgd = string.rep(fg_bg.blit_fgd, e.frame.w)
        bkg = string.rep(fg_bg.blit_bkg, e.frame.w)
        e.redraw()
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return vbar
