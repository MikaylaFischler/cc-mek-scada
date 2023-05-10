-- Button Graphics Element

local core    = require("graphics.core")
local element = require("graphics.element")

---@class switch_button_args
---@field text string button text
---@field callback function function to call on touch
---@field default? boolean default state, defaults to off (false)
---@field min_width? integer text length + 2 if omitted
---@field active_fg_bg cpair foreground/background colors when pressed
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field height? integer parent height if omitted
---@field fg_bg? cpair foreground/background colors

-- new switch button (latch high/low)
---@param args switch_button_args
---@return graphics_element element, element_id id
local function switch_button(args)
    assert(type(args.text) == "string", "graphics.elements.controls.switch_button: text is a required field")
    assert(type(args.callback) == "function", "graphics.elements.controls.switch_button: callback is a required field")
    assert(type(args.active_fg_bg) == "table", "graphics.elements.controls.switch_button: active_fg_bg is a required field")

    -- single line
    args.height = 1

    -- determine widths
    local text_width = string.len(args.text)
    args.width = math.max(text_width + 2, args.min_width)

    -- create new graphics element base object
    local e = element.new(args)

    -- button state (convert nil to false if missing)
    e.value = args.default or false

    local h_pad = math.floor((e.frame.w - text_width) / 2) + 1
    local v_pad = math.floor(e.frame.h / 2) + 1

    -- show the button state
    local function draw_state()
        if e.value then
            -- show as pressed
            e.window.setTextColor(args.active_fg_bg.fgd)
            e.window.setBackgroundColor(args.active_fg_bg.bkg)
        else
            -- show as unpressed
            e.window.setTextColor(e.fg_bg.fgd)
            e.window.setBackgroundColor(e.fg_bg.bkg)
        end

        -- clear to redraw background
        e.window.clear()

        -- write the button text
        e.window.setCursorPos(h_pad, v_pad)
        e.window.write(args.text)
    end

    -- initial draw
    draw_state()

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if e.enabled and core.events.was_clicked(event.type) then
            -- toggle state
            e.value = not e.value
            draw_state()

            -- call the touch callback with state
            args.callback(e.value)
        end
    end

    -- set the value
    ---@param val boolean new value
    function e.set_value(val)
        -- set state
        e.value = val
        draw_state()
    end

    return e.get()
end

return switch_button
