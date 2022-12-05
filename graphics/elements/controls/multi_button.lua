-- Button Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class button_option
---@field text string
---@field fg_bg cpair
---@field active_fg_bg cpair
---@field _lpad integer automatically calculated left pad
---@field _start_x integer starting touch x range (inclusive)
---@field _end_x integer ending touch x range (inclusive)

---@class multi_button_args
---@field options table button options
---@field callback function function to call on touch
---@field default? boolean default state, defaults to options[1]
---@field min_width? integer text length + 2 if omitted
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field height? integer parent height if omitted
---@field fg_bg? cpair foreground/background colors

-- new multi button (latch selection, exclusively one button at a time)
---@param args multi_button_args
---@return graphics_element element, element_id id
local function multi_button(args)
    assert(type(args.options) == "table", "graphics.elements.controls.multi_button: options is a required field")
    assert(type(args.callback) == "function", "graphics.elements.controls.multi_button: callback is a required field")

    -- single line
    args.height = 3

    -- determine widths
    local max_width = 1
    for i = 1, #args.options do
        local opt = args.options[i] ---@type button_option
        if string.len(opt.text) > max_width then
            max_width = string.len(opt.text)
        end
    end

    local button_width = math.max(max_width, args.min_width or 1)

    args.width = (button_width * #args.options) + #args.options + 1

    -- create new graphics element base object
    local e = element.new(args)

    -- button state (convert nil to 1 if missing)
    e.value = args.default or 1

    -- calculate required button information
    local next_x = 2
    for i = 1, #args.options do
        local opt = args.options[i] ---@type button_option
        local w = string.len(opt.text)

        opt._lpad = math.floor((e.frame.w - w) / 2)
        opt._start_x = next_x
        opt._end_x = next_x + button_width - 1

        next_x = next_x + (button_width + 1)
    end

    -- show the button state
    local function draw()
        for i = 1, #args.options do
            local opt = args.options[i] ---@type button_option

            e.window.setCursorPos(opt._start_x, 2)

            if e.value == i then
                -- show as pressed
                e.window.setTextColor(opt.active_fg_bg.fgd)
                e.window.setBackgroundColor(opt.active_fg_bg.bkg)
            else
                -- show as unpressed
                e.window.setTextColor(opt.fg_bg.fgd)
                e.window.setBackgroundColor(opt.fg_bg.bkg)
            end

            e.window.write(util.pad(opt.text, button_width))
        end
    end

    -- handle touch
    ---@param event monitor_touch monitor touch event
    function e.handle_touch(event)
        -- determine what was pressed
        if e.enabled and event.y == 2 then
            for i = 1, #args.options do
                local opt = args.options[i] ---@type button_option

                if event.x >= opt._start_x and event.x <= opt._end_x then
                    e.value = i
                    draw()
                    args.callback(e.value)
                end
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

return multi_button
