-- Button Graphics Element

local tcd     = require("scada-common.tcallbackdsp")

local core    = require("graphics.core")
local element = require("graphics.element")

local CLICK_TYPE = core.events.CLICK_TYPE

---@class push_button_args
---@field text string button text
---@field callback function function to call on touch
---@field min_width? integer text length if omitted
---@field active_fg_bg? cpair foreground/background colors when pressed
---@field dis_fg_bg? cpair foreground/background colors when disabled
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field height? integer parent height if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new push button
---@param args push_button_args
---@return graphics_element element, element_id id
local function push_button(args)
    assert(type(args.text) == "string", "graphics.elements.controls.push_button: text is a required field")
    assert(type(args.callback) == "function", "graphics.elements.controls.push_button: callback is a required field")
    assert(type(args.min_width) == "nil" or (type(args.min_width) == "number" and args.min_width > 0),
        "graphics.elements.controls.push_button: min_width must be nil or a number > 0")

    local text_width = string.len(args.text)

    -- single line height, calculate width
    args.height = 1
    args.min_width = args.min_width or 0
    args.width = math.max(text_width, args.min_width)

    -- create new graphics element base object
    local e = element.new(args)

    local h_pad = math.floor((e.frame.w - text_width) / 2) + 1
    local v_pad = math.floor(e.frame.h / 2) + 1

    -- draw the button
    local function draw()
        e.window.clear()

        -- write the button text
        e.window.setCursorPos(h_pad, v_pad)
        e.window.write(args.text)
    end

    -- draw the button as pressed (if active_fg_bg set)
    local function show_pressed()
        if e.enabled and args.active_fg_bg ~= nil then
            e.value = true
            e.window.setTextColor(args.active_fg_bg.fgd)
            e.window.setBackgroundColor(args.active_fg_bg.bkg)
            draw()
        end
    end

    -- draw the button as unpressed (if active_fg_bg set)
    local function show_unpressed()
        if e.enabled and args.active_fg_bg ~= nil then
            e.value = false
            e.window.setTextColor(e.fg_bg.fgd)
            e.window.setBackgroundColor(e.fg_bg.bkg)
            draw()
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if e.enabled then
            if event.type == CLICK_TYPE.TAP then
                show_pressed()
                -- show as unpressed in 0.25 seconds
                if args.active_fg_bg ~= nil then tcd.dispatch(0.25, show_unpressed) end
                args.callback()
            elseif event.type == CLICK_TYPE.DOWN then
                show_pressed()
            elseif event.type == CLICK_TYPE.UP then
                show_unpressed()
                if e.in_frame_bounds(event.current.x, event.current.y) then
                    args.callback()
                end
            end
        end
    end

    -- set the value (true simulates pressing the button)
    ---@param val boolean new value
    function e.set_value(val)
        if val then e.handle_mouse(core.events.mouse_generic(core.events.CLICK_TYPE.UP, 1, 1)) end
    end

    -- show butten as enabled
    function e.enable()
        if args.dis_fg_bg ~= nil then
            e.value = false
            e.window.setTextColor(e.fg_bg.fgd)
            e.window.setBackgroundColor(e.fg_bg.bkg)
            draw()
        end
    end

    -- show button as disabled
    function e.disable()
        if args.dis_fg_bg ~= nil then
            e.value = false
            e.window.setTextColor(args.dis_fg_bg.fgd)
            e.window.setBackgroundColor(args.dis_fg_bg.bkg)
            draw()
        end
    end

    -- initial draw
    draw()

    return e.complete()
end

return push_button
