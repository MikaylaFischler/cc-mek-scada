-- Horizontal Bar Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class hbar_args
---@field bar_fg_bg cpair bar foreground/background colors
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width? integer parent width if omitted
---@field fg_bg cpair foreground/background colors

-- new horizontal bar
---@param args hbar_args
local function hbar(args)
    local bkg = ""
    local last_num_bars = -1

    -- create new graphics element base object
    local e = element.new(args)

    -- bar width is width - 5 characters for " 100%"
    local bar_width = e.frame.w - 5

    assert(bar_width > 0, "graphics.elements.hbar: too small for bar")

    -- set background blit string
    bkg = util.strrep(args.bar_fg_bg.blit_bkg, bar_width)

    -- handle data changes
    function e.on_update(fraction)
        -- enforce minimum and maximum
        if fraction < 0 then
            fraction = 0.0
        elseif fraction > 1 then
            fraction = 1.0
        end

        -- compute number of bars
        local num_bars = util.round((fraction * 100) / (bar_width * 2))

        -- redraw bar if changed
        if num_bars ~= last_num_bars then
            last_num_bars = num_bars

            local bar = ""
            local spaces = ""

            -- fill percentage
            for _ = 1, num_bars / 2 do
                spaces = spaces .. " "
                bar = bar .. args.bar_fg_bg.blit_fgd
            end

            -- add fractional bar if needed
            if num_bars % 2 == 1 then
                spaces = spaces .. "\x95"
                bar = bar .. args.bar_fg_bg.blit_fgd
            end

            -- pad background
            for _ = 1, bar_width - ((num_bars / 2) + num_bars % 2) do
                spaces = spaces .. " "
                bar = bar .. args.bar_fg_bg.blit_bkg
            end

            e.window.setCursorPos(1, 1)
            e.window.blit(spaces, bar, bkg)
        end

        -- update percentage
        e.window.setCursorPos(bar_width + 1, 1)
        e.window.write(util.sprintf("%3.0f%%", fraction * 100))
    end

    return e.get()
end

return hbar
