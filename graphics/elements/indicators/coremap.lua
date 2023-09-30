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
---@field y? integer auto incremented if omitted

-- new core map box
---@nodiscard
---@param args core_map_args
---@return graphics_element element, element_id id
local function core_map(args)
    element.assert(util.is_int(args.reactor_l), "reactor_l is a required field")
    element.assert(util.is_int(args.reactor_w), "reactor_w is a required field")

    -- require max dimensions
    args.width = 18
    args.height = 18

    -- inherit only foreground color
    args.fg_bg = core.cpair(args.parent.get_fg_bg().fgd, colors.gray)

    -- create new graphics element base object
    local e = element.new(args)

    e.value = 0

    local alternator = true

    local core_l = args.reactor_l - 2
    local core_w = args.reactor_w - 2

    local shift_x = 8 - math.floor(core_l / 2)
    local shift_y = 8 - math.floor(core_w / 2)

    local start_x = 2 + shift_x
    local start_y = 2 + shift_y

    local inner_width = core_l
    local inner_height = core_w

    -- create coordinate grid and frame
    local function draw_frame()
        e.w_set_fgd(colors.white)

        for x = 0, (inner_width - 1) do
            e.w_set_cur(x + start_x, 1)
            e.w_write(util.sprintf("%X", x))
        end

        for y = 0, (inner_height - 1) do
            e.w_set_cur(1, y + start_y)
            e.w_write(util.sprintf("%X", y))
        end

        -- even out bottom edge
        e.w_set_fgd(e.fg_bg.bkg)
        e.w_set_bkg(args.parent.get_fg_bg().bkg)
        e.w_set_cur(1, e.frame.h)
        e.w_write(string.rep("\x8f", e.frame.w))
        e.w_set_fgd(e.fg_bg.fgd)
        e.w_set_bkg(e.fg_bg.bkg)
    end

    -- draw the core
    ---@param t number temperature in K
    local function draw_core(t)
        local i = 1
        local back_c = "F"
        local text_c    ---@type string

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
            e.w_set_cur(start_x, y)
            for _ = 1, inner_width do
                if alternator then
                    i = i + 1
                    e.w_blit("\x07", text_c, back_c)
                else
                    e.w_blit("\x07", "7", "8")
                end

                alternator = not alternator
            end

            if inner_width % 2 == 0 then alternator = not alternator end
        end

        -- reset alternator
        alternator = true
    end

    -- on state change
    ---@param temperature number temperature in Kelvin
    function e.on_update(temperature)
        e.value = temperature
        draw_core(e.value)
    end

    -- set temperature to display
    ---@param val number degrees K
    function e.set_value(val) e.on_update(val) end

    -- resize reactor dimensions
    ---@param reactor_l integer reactor length (rendered in 2D top-down as width)
    ---@param reactor_w integer reactor width (rendered in 2D top-down as height)
    function e.resize(reactor_l, reactor_w)
        -- enforce possible dimensions
        if reactor_l > 18 then reactor_l = 18 elseif reactor_l < 3 then reactor_l = 3 end
        if reactor_w > 18 then reactor_w = 18 elseif reactor_w < 3 then reactor_w = 3 end

        -- update dimensions
        core_l = reactor_l - 2
        core_w = reactor_w - 2
        shift_x = 8 - math.floor(core_l / 2)
        shift_y = 8 - math.floor(core_w / 2)
        start_x = 2 + shift_x
        start_y = 2 + shift_y
        inner_width = core_l
        inner_height = core_w

        e.window.clear()

        -- re-draw
        draw_frame()
        e.on_update(e.value)
    end

    -- redraw both frame and core
    function e.redraw()
        draw_frame()
        draw_core(e.value)
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return core_map
