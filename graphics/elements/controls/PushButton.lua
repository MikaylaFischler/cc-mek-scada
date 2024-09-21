-- Button Graphics Element

local tcd     = require("scada-common.tcd")
local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

local ALIGN = core.ALIGN

local MOUSE_CLICK = core.events.MOUSE_CLICK
local KEY_CLICK = core.events.KEY_CLICK

---@class push_button_args
---@field text string button text
---@field callback function function to call on touch
---@field min_width? integer text length if omitted
---@field alignment? ALIGN text align if min width > length
---@field active_fg_bg? cpair foreground/background colors when pressed
---@field dis_fg_bg? cpair foreground/background colors when disabled
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new push button
---@param args push_button_args
---@return graphics_element element, element_id id
local function push_button(args)
    element.assert(type(args.text) == "string", "text is a required field")
    element.assert(type(args.callback) == "function", "callback is a required field")
    element.assert(type(args.min_width) == "nil" or (type(args.min_width) == "number" and args.min_width > 0), "min_width must be nil or a number > 0")

    local text_width = string.len(args.text)
    local alignment = args.alignment or ALIGN.CENTER

    -- set automatic settings
    args.can_focus = true
    args.min_width = args.min_width or 0
    args.width = math.max(text_width, args.min_width)

    -- provide a constraint condition to element creation to prefer a single line button
    ---@param frame graphics_frame
    local function constrain(frame)
        return frame.w, math.max(1, #util.strwrap(args.text, frame.w))
    end

    -- create new graphics element base object
    local e = element.new(args, constrain)

    local text_lines = util.strwrap(args.text, e.frame.w)

    -- draw the button
    function e.redraw()
        e.window.clear()

        for i = 1, #text_lines do
            if i > e.frame.h then break end

            local len = string.len(text_lines[i])

            -- use cursor position to align this line
            if alignment == ALIGN.CENTER then
                e.w_set_cur(math.floor((e.frame.w - len) / 2) + 1, i)
            elseif alignment == ALIGN.RIGHT then
                e.w_set_cur((e.frame.w - len) + 1, i)
            else
                e.w_set_cur(1, i)
            end

            e.w_write(text_lines[i])
        end
    end

    -- draw the button as pressed (if active_fg_bg set)
    local function show_pressed()
        if e.enabled and args.active_fg_bg ~= nil then
            e.value = true
            e.w_set_fgd(args.active_fg_bg.fgd)
            e.w_set_bkg(args.active_fg_bg.bkg)
            e.redraw()
        end
    end

    -- draw the button as unpressed (if active_fg_bg set)
    local function show_unpressed()
        if e.enabled and args.active_fg_bg ~= nil then
            e.value = false
            e.w_set_fgd(e.fg_bg.fgd)
            e.w_set_bkg(e.fg_bg.bkg)
            e.redraw()
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if e.enabled then
            if event.type == MOUSE_CLICK.TAP then
                show_pressed()
                -- show as unpressed in 0.25 seconds
                if args.active_fg_bg ~= nil then tcd.dispatch(0.25, show_unpressed) end
                args.callback()
            elseif event.type == MOUSE_CLICK.DOWN then
                show_pressed()
            elseif event.type == MOUSE_CLICK.UP then
                show_unpressed()
                if e.in_frame_bounds(event.current.x, event.current.y) then
                    args.callback()
                end
            end
        end
    end

    -- handle keyboard interaction
    ---@param event key_interaction key event
    function e.handle_key(event)
        if event.type == KEY_CLICK.DOWN then
            if event.key == keys.space or event.key == keys.enter or event.key == keys.numPadEnter then
                args.callback()
                -- visualize click without unfocusing
                show_unpressed()
                if args.active_fg_bg ~= nil then tcd.dispatch(0.25, show_pressed) end
            end
        end
    end

    -- set the value (true simulates pressing the button)
    ---@param val boolean new value
    function e.set_value(val)
        if val then e.handle_mouse(core.events.mouse_generic(core.events.MOUSE_CLICK.UP, 1, 1)) end
    end

    -- show butten as enabled
    function e.on_enabled()
        if args.dis_fg_bg ~= nil then
            e.value = false
            e.w_set_fgd(e.fg_bg.fgd)
            e.w_set_bkg(e.fg_bg.bkg)
            e.redraw()
        end
    end

    -- show button as disabled
    function e.on_disabled()
        if args.dis_fg_bg ~= nil then
            e.value = false
            e.w_set_fgd(args.dis_fg_bg.fgd)
            e.w_set_bkg(args.dis_fg_bg.bkg)
            e.redraw()
        end
    end

    -- handle focus
    e.on_focused = show_pressed
    e.on_unfocused = show_unpressed

    -- initial draw
    e.redraw()

    return e.complete()
end

return push_button
