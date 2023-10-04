-- Radio Button Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

local KEY_CLICK = core.events.KEY_CLICK

---@class radio_button_args
---@field options table button options
---@field radio_colors cpair radio button colors (inner & outer)
---@field select_color color color for radio button border when selected
---@field default? integer default state, defaults to options[1]
---@field min_width? integer text length + 2 if omitted
---@field callback? function function to call on touch
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
    element.assert(type(args.options) == "table", "options is a required field")
    element.assert(#args.options > 0, "at least one option is required")
    element.assert(type(args.radio_colors) == "table", "radio_colors is a required field")
    element.assert(type(args.select_color) == "number", "select_color is a required field")
    element.assert(type(args.default) == "nil" or (type(args.default) == "number" and args.default > 0), "default must be nil or a number > 0")
    element.assert(type(args.min_width) == "nil" or (type(args.min_width) == "number" and args.min_width > 0), "min_width must be nil or a number > 0")

    -- determine widths
    local max_width = 1
    for i = 1, #args.options do
        local opt = args.options[i] ---@type string
        if string.len(opt) > max_width then
            max_width = string.len(opt)
        end
    end

    local button_text_width = math.max(max_width, args.min_width or 0)

    -- set automatic args
    args.can_focus = true
    args.width = button_text_width + 2
    args.height = #args.options -- one line per option

    -- create new graphics element base object
    local e = element.new(args)

    local focused_opt = 1

    -- button state (convert nil to 1 if missing)
    e.value = args.default or 1

    -- show the button state
    function e.redraw()
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
            if i == focused_opt and e.is_focused() and e.enabled then
                e.w_set_fgd(e.fg_bg.bkg)
                e.w_set_bkg(e.fg_bg.fgd)
            else
                e.w_set_fgd(e.fg_bg.fgd)
                e.w_set_bkg(e.fg_bg.bkg)
            end

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
                focused_opt = e.value
                e.redraw()
                if type(args.callback) == "function" then args.callback(e.value) end
            end
        end
    end

    -- handle keyboard interaction
    ---@param event key_interaction key event
    function e.handle_key(event)
        if event.type == KEY_CLICK.DOWN or event.type == KEY_CLICK.HELD then
            if event.type == KEY_CLICK.DOWN and (event.key == keys.space or event.key == keys.enter or event.key == keys.numPadEnter) then
                e.value = focused_opt
                e.redraw()
                if type(args.callback) == "function" then args.callback(e.value) end
            elseif event.key == keys.down then
                if focused_opt < #args.options then
                    focused_opt = focused_opt + 1
                    e.redraw()
                end
            elseif event.key == keys.up then
                if focused_opt > 1 then
                    focused_opt = focused_opt - 1
                    e.redraw()
                end
            end
        end
    end

    -- set the value
    ---@param val integer new value
    function e.set_value(val)
        if type(val) == "number" and val > 0 and val <= #args.options then
            e.value = val
            e.redraw()
        end
    end

    -- handle focus & enable
    e.on_focused = e.redraw
    e.on_unfocused = e.redraw
    e.on_enabled = e.redraw
    e.on_disabled = e.redraw

    -- initial draw
    e.redraw()

    return e.complete()
end

return radio_button
