-- Multi Button Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

---@class button_option
---@field text string
---@field fg_bg cpair
---@field active_fg_bg cpair
---@field _start_x integer starting touch x range (inclusive)
---@field _end_x integer ending touch x range (inclusive)

---@class multi_button_args
---@field options table button options
---@field callback function function to call on touch
---@field default? integer default state, defaults to options[1]
---@field min_width? integer text length + 2 if omitted
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field height? integer parent height if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new multi button (latch selection, exclusively one button at a time)
---@param args multi_button_args
---@return graphics_element element, element_id id
local function multi_button(args)
    element.assert(type(args.options) == "table", "options is a required field")
    element.assert(#args.options > 0, "at least one option is required")
    element.assert(type(args.callback) == "function", "callback is a required field")
    element.assert(type(args.default) == "nil" or (type(args.default) == "number" and args.default > 0), "default must be nil or a number > 0")
    element.assert(type(args.min_width) == "nil" or (type(args.min_width) == "number" and args.min_width > 0), "min_width must be nil or a number > 0")

    -- single line
    args.height = 1

    -- determine widths
    local max_width = 1
    for i = 1, #args.options do
        local opt = args.options[i] ---@type button_option
        if string.len(opt.text) > max_width then
            max_width = string.len(opt.text)
        end
    end

    local button_width = math.max(max_width, args.min_width or 0)

    args.width = (button_width * #args.options) + #args.options + 1

    -- create new graphics element base object
    local e = element.new(args)

    -- button state (convert nil to 1 if missing)
    e.value = args.default or 1

    -- calculate required button information
    local next_x = 2
    for i = 1, #args.options do
        local opt = args.options[i] ---@type button_option

        opt._start_x = next_x
        opt._end_x = next_x + button_width - 1

        next_x = next_x + (button_width + 1)
    end

    -- show the button state
    function e.redraw()
        for i = 1, #args.options do
            local opt = args.options[i] ---@type button_option

            e.w_set_cur(opt._start_x, 1)

            if e.value == i then
                -- show as pressed
                e.w_set_fgd(opt.active_fg_bg.fgd)
                e.w_set_bkg(opt.active_fg_bg.bkg)
            else
                -- show as unpressed
                e.w_set_fgd(opt.fg_bg.fgd)
                e.w_set_bkg(opt.fg_bg.bkg)
            end

            e.w_write(util.pad(opt.text, button_width))
        end
    end

    -- check which button a given x is within
    ---@return integer|nil button index or nil if not within a button
    local function which_button(x)
        for i = 1, #args.options do
            local opt = args.options[i] ---@type button_option
            if x >= opt._start_x and x <= opt._end_x then return i end
        end

        return nil
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        -- if enabled and the button row was pressed...
        if e.enabled and core.events.was_clicked(event.type) then
            -- a button may have been pressed, which one was it?
            local button_ini = which_button(event.initial.x)
            local button_cur = which_button(event.current.x)

            -- mouse up must always have started with a mouse down on the same button to count as a click
            -- tap always has identical coordinates, so this always passes for taps
            if button_ini == button_cur and button_cur ~= nil then
                e.value = button_cur
                e.redraw()
                args.callback(e.value)
            end
        end
    end

    -- set the value
    ---@param val integer new value
    function e.set_value(val)
        e.value = val
        e.redraw()
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return multi_button
