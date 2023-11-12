-- Button Graphics Element

local tcd     = require("scada-common.tcd")

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
---@field height? integer parent height if omitted
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
    args.height = 1
    args.min_width = args.min_width or 0
    args.width = math.max(text_width, args.min_width)

    -- create new graphics element base object
    local e = element.new(args)

    local h_pad = 1
    local v_pad = math.floor(e.frame.h / 2) + 1

    if alignment == ALIGN.CENTER then
        h_pad = math.floor((e.frame.w - text_width) / 2) + 1
    elseif alignment == ALIGN.RIGHT then
        h_pad = (e.frame.w - text_width) + 1
    end

    -- draw the button
    function e.redraw()
        e.window.clear()

        -- write the button text
        e.w_set_cur(h_pad, v_pad)
        e.w_write(args.text)
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
                e.defocus()
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
