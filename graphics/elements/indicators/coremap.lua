-- Reactor Core View Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

---@class core_map_args
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field fg_bg? cpair foreground/background colors

-- new core map box
---@param args core_map_args
---@return graphics_element element, element_id id
local function core_map(args)
    args.width = 30
    args.height = 18

    -- arbitrary foreground color, gray reactor frame background
    args.fg_bg = core.graphics.cpair(colors.white, colors.gray)

    -- create new graphics element base object
    local e = element.new(args)

    -- draw core map box

    local start_x = 2
    local start_y = 2

    local inner_width = math.floor((e.frame.w - 2) / 2)
    local inner_height = e.frame.h - 2
    local alternator = true

    -- check dimensions
    assert(inner_width > 0, "graphics.elements.indicators.coremap: inner_width <= 0")
    assert(inner_height > 0, "graphics.elements.indicators.coremap: inner_height <= 0")
    assert(start_x <= inner_width, "graphics.elements.indicators.coremap: start_x > inner_width")
    assert(start_y <= inner_height, "graphics.elements.indicators.coremap: start_y > inner_height")

    -- draw the core
    local function draw(t)
        local i = 1
        local back_c = "FF"
        local text_c = "FF"

        -- determine fuel assembly coloring
        if t <= 300 then
            -- gray
            back_c = "88"
        elseif t <= 350 then
            -- blue
            back_c = "33"
        elseif t < 600 then
            -- green
            back_c = "DD"
        elseif t < 1000 then
            -- yellow
            back_c = "44"
        elseif t < 1200 then
            -- orange
            back_c = "11"
        elseif t < 1300 then
            -- red
            back_c = "EE"
            text_c = "00"
        else
            -- pink
            back_c = "22"
            text_c = "00"
        end

        -- draw pattern
        for y = start_y, inner_height + (start_y - 1) do
            e.window.setCursorPos(start_x, y)
            for x = 1, inner_width do
                local str = util.sprintf("%02X", i)

                if alternator then
                    i = i + 1
                    e.window.blit(str, text_c, back_c)
                else
                    e.window.blit("  ", "00", "00")
                end

                alternator = not alternator
            end

            if inner_width % 2 == 0 then alternator = not alternator end
        end
    end

    draw(300)

    -- on state change
    ---@param temperature integer temperature in Kelvin
    function e.on_update(temperature)
        draw(temperature)
    end

    return e.get()
end

return core_map
