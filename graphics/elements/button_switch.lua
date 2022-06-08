-- Button Graphics Element

local element = require("graphics.element")

---@class switch_button_args
---@field text string button text
---@field callback function function to call on touch
---@field default? boolean default state, defaults to off (false)
---@field min_width? integer text length + 2 if omitted
---@field active_fg_bg cpair foreground/background colors when pressed
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg cpair foreground/background colors

-- new switch button (latch high/low)
---@param args switch_button_args
local function switch_button(args)
    -- button state (convert nil to false if missing)
    local state = args.default or false

    -- determine widths
    local text_width = string.len(args.text)
    args.width = math.max(text_width + 2, args.min_width)

    -- create new graphics element base object
    local e = element.new(args)

    local h_pad = math.floor((e.frame.w - text_width) / 2)
    local v_pad = math.floor(e.frame.h / 2) + 1

    -- write the button text
    e.window.setCursorPos(h_pad, v_pad)
    e.write(args.text)

    -- show the button state
    local function draw_state()
        if state then
            -- show as pressed
            e.window.setTextColor(args.active_fg_bg.fgd)
            e.window.setBackgroundColor(args.active_fg_bg.bkg)
        else
            -- show as unpressed
            e.window.setTextColor(e.fg_bg.fgd)
            e.window.setBackgroundColor(e.fg_bg.bkg)
        end

        e.window.redraw()
    end

    -- initial draw
    draw_state()

    -- handle touch
    function e.handle_touch(event)
        -- toggle state
        state = not state
        draw_state()

        -- call the touch callback with state
        args.callback(state)
    end

    return e.get()
end

return switch_button
