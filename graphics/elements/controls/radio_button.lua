-- Radio Button Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

---@class radio_button_args
---@field options table button options
---@field callback function function to call on touch
---@field radio_colors cpair radio button colors (inner & outer)
---@field select_color color color for radio button border when selected
---@field default? integer default state, defaults to options[1]
---@field min_width? integer text length + 2 if omitted
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new radio button list (latch selection, exclusively one button at a time)
---@param args radio_button_args
---@return graphics_element element, element_id id
local function radio_button(args)
    assert(type(args.options) == "table", "graphics.elements.controls.radio_button: options is a required field")
    assert(#args.options > 0, "graphics.elements.controls.radio_button: at least one option is required")
    assert(type(args.callback) == "function", "graphics.elements.controls.radio_button: callback is a required field")
    assert(type(args.radio_colors) == "table", "graphics.elements.controls.radio_button: radio_colors is a required field")
    assert(type(args.select_color) == "number", "graphics.elements.controls.radio_button: select_color is a required field")
    assert(type(args.default) == "nil" or (type(args.default) == "number" and args.default > 0),
        "graphics.elements.controls.radio_button: default must be nil or a number > 0")
    assert(type(args.min_width) == "nil" or (type(args.min_width) == "number" and args.min_width > 0),
        "graphics.elements.controls.radio_button: min_width must be nil or a number > 0")

    -- one line per option
    args.height = #args.options

    -- determine widths
    local max_width = 1
    for i = 1, #args.options do
        local opt = args.options[i] ---@type string
        if string.len(opt) > max_width then
            max_width = string.len(opt)
        end
    end

    local button_text_width = math.max(max_width, args.min_width or 0)

    args.width = button_text_width + 2

    -- create new graphics element base object
    local e = element.new(args)

    -- button state (convert nil to 1 if missing)
    e.value = args.default or 1

    -- show the button state
    local function draw()
        for i = 1, #args.options do
            local opt = args.options[i] ---@type string

            local inner_color = util.trinary(e.value == i, args.radio_colors.color_b, args.radio_colors.color_a)
            local outer_color = util.trinary(e.value == i, args.select_color, args.radio_colors.color_b)

            e.w_set_cur(1, i)

            e.w_set_fgd(inner_color)
            e.w_set_bkg(outer_color)
            e.w_write("\x88")

            e.w_set_fgd(outer_color)
            e.w_set_bkg(e.fg_bg.bkg)
            e.w_write("\x95")

            -- write button text
            e.w_set_fgd(e.fg_bg.fgd)
            e.w_set_bkg(e.fg_bg.bkg)
            e.w_write(opt)
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if e.enabled and core.events.was_clicked(event.type) and (event.initial.y == event.current.y) then
            -- determine what was pressed
            if args.options[event.current.y] ~= nil then
                e.value = event.current.y
                draw()
                args.callback(e.value)
            end
        end
    end

    -- set the value
    ---@param val integer new value
    function e.set_value(val)
        e.value = val
        draw()
    end

    -- initial draw
    draw()

    return e.complete()
end

return radio_button
