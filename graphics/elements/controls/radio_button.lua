-- Radio Button Graphics Element

local element = require("graphics.element")

---@class radio_button_args
---@field options table button options
---@field callback function function to call on touch
---@field radio_colors cpair colors for radio button center dot when active (a) or inactive (b)
---@field radio_bg color background color of radio button
---@field default? integer default state, defaults to options[1]
---@field min_width? integer text length + 2 if omitted
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field fg_bg? cpair foreground/background colors

-- new radio button list (latch selection, exclusively one button at a time)
---@param args radio_button_args
---@return graphics_element element, element_id id
local function radio_button(args)
    assert(type(args.options) == "table", "graphics.elements.controls.radio_button: options is a required field")
    assert(#args.options > 0, "graphics.elements.controls.radio_button: at least one option is required")
    assert(type(args.callback) == "function", "graphics.elements.controls.radio_button: callback is a required field")
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

            e.window.setCursorPos(1, i)

            if e.value == i then
                -- show as selected
                e.window.setTextColor(args.radio_colors.color_a)
                e.window.setBackgroundColor(args.radio_bg)
            else
                -- show as unselected
                e.window.setTextColor(args.radio_colors.color_b)
                e.window.setBackgroundColor(args.radio_bg)
            end

            e.window.write("\x88")

            e.window.setTextColor(args.radio_bg)
            e.window.setBackgroundColor(e.fg_bg.bkg)
            e.window.write("\x95")

            -- write button text
            e.window.setTextColor(e.fg_bg.fgd)
            e.window.setBackgroundColor(e.fg_bg.bkg)
            e.window.write(opt)
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        -- determine what was pressed
        if e.enabled then
            if args.options[event.y] ~= nil then
                e.value = event.y
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

    return e.get()
end

return radio_button
