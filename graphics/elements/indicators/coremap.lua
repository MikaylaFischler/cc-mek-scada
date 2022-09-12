-- Reactor Core View Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

---@class core_map_args
---@field reactor_l integer reactor length
---@field reactor_w integer reactor width
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted

-- new core map box
---@param args core_map_args
---@return graphics_element element, element_id id
local function core_map(args)
    assert(util.is_int(args.reactor_l), "graphics.elements.indicators.coremap: reactor_l is a required field")
    assert(util.is_int(args.reactor_w), "graphics.elements.indicators.coremap: reactor_w is a required field")

    args.width = args.reactor_l
    args.height = args.reactor_w

    -- inherit only foreground color
    args.fg_bg = core.graphics.cpair(args.parent.get_fg_bg().fgd, colors.gray)

    -- create new graphics element base object
    local e = element.new(args)

    local start_x = 2
    local start_y = 2

    local inner_width = e.frame.w - 2
    local inner_height = e.frame.h - 2
    local alternator = true

    -- check dimensions
    assert(inner_width > 0, "graphics.elements.indicators.coremap: inner_width <= 0")
    assert(inner_height > 0, "graphics.elements.indicators.coremap: inner_height <= 0")
    assert(start_x <= inner_width, "graphics.elements.indicators.coremap: start_x > inner_width")
    assert(start_y <= inner_height, "graphics.elements.indicators.coremap: start_y > inner_height")

    -- label coordinates

    e.window.setTextColor(colors.white)

    for x = 0, (inner_width - 1) do
        e.window.setCursorPos(x + start_x, 1)
        e.window.write(util.sprintf("%X", x))
    end

    for y = 0, (inner_height - 1) do
        e.window.setCursorPos(1, y + start_y)
        e.window.write(util.sprintf("%X", y))
    end

    -- even out bottom edge
    e.window.setTextColor(e.fg_bg.bkg)
    e.window.setBackgroundColor(args.parent.get_fg_bg().bkg)
    e.window.setCursorPos(1, e.frame.h)
    e.window.write(util.strrep("\x8f", e.frame.w))
    e.window.setTextColor(e.fg_bg.fgd)
    e.window.setBackgroundColor(e.fg_bg.bkg)

    -- draw the core
    ---@param t number temperature in K
    local function draw(t)
        local i = 1
        local back_c = "F"
        local text_c = "8"

        -- determine fuel assembly coloring
        if t <= 300 then
            -- gray
            text_c = "8"
        elseif t <= 350 then
            -- blue
            text_c = "3"
        elseif t < 600 then
            -- green
            text_c = "D"
        elseif t < 1000 then
            -- yellow
            text_c = "4"
            -- back_c = "8"
        elseif t < 1200 then
            -- orange
            text_c = "1"
        elseif t < 1300 then
            -- red
            text_c = "E"
        else
            -- pink
            text_c = "2"
        end

        -- draw pattern
        for y = start_y, inner_height + (start_y - 1) do
            e.window.setCursorPos(start_x, y)
            for x = 1, inner_width do
                local str = util.sprintf("%02X", i)

                if alternator then
                    i = i + 1
                    e.window.blit("\x07", text_c, back_c)
                else
                    e.window.blit("\x07", "7", "8")
                end

                alternator = not alternator
            end

            if inner_width % 2 == 0 then alternator = not alternator end
        end
    end

    -- on state change
    ---@param temperature number temperature in Kelvin
    function e.on_update(temperature)
        e.value = temperature
        draw(temperature)
    end

    function e.set_value(val) e.on_update(val) end

    -- initial draw at base temp
    e.on_update(300)

    return e.get()
end

return core_map
