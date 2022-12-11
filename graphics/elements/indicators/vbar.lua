-- Vertical Bar Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class vbar_args
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors

-- new vertical bar
---@param args vbar_args
---@return graphics_element element, element_id id
local function vbar(args)
    -- properties/state
    local last_num_bars = -1

    -- create new graphics element base object
    local e = element.new(args)

    -- blit strings
    local fgd = util.strrep(e.fg_bg.blit_fgd, e.frame.w)
    local bkg = util.strrep(e.fg_bg.blit_bkg, e.frame.w)
    local spaces = util.spaces(e.frame.w)
    local one_third = util.strrep("\x8f", e.frame.w)
    local two_thirds = util.strrep("\x83", e.frame.w)

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

            -- start bottom up
            local y = e.frame.h

            -- start at base of vertical bar
            e.window.setCursorPos(1, y)

            -- fill percentage
            for _ = 1, num_bars / 3 do
                e.window.blit(spaces, bkg, fgd)
                y = y - 1
                e.window.setCursorPos(1, y)
            end

            -- add fractional bar if needed
            if num_bars % 3 == 1 then
                e.window.blit(one_third, bkg, fgd)
                y = y - 1
            elseif num_bars % 3 == 2 then
                e.window.blit(two_thirds, bkg, fgd)
                y = y - 1
            end

            -- fill the rest blank
            while y > 0 do
                e.window.setCursorPos(1, y)
                e.window.blit(spaces, fgd, bkg)
                y = y - 1
            end
        end
    end

    -- change bar color
    ---@param fg_bg cpair new bar colors
    function e.recolor(fg_bg)
        fgd = util.strrep(fg_bg.blit_fgd, e.frame.w)
        bkg = util.strrep(fg_bg.blit_bkg, e.frame.w)

        -- re-draw
        last_num_bars = 0
        if type(e.value) == "number" then
            e.on_update(e.value)
        end
    end

    -- set the percentage value
    ---@param val number 0.0 to 1.0
    function e.set_value(val) e.on_update(val) end

    return e.get()
end

return vbar
