-- Hazard-bordered Button Graphics Element

local tcd     = require("scada-common.tcallbackdsp")
local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

---@class hazard_button_args
---@field text string text to show on button
---@field accent color accent color for hazard border
---@field dis_colors? cpair text color and border color when disabled
---@field callback function function to call on touch
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field fg_bg? cpair foreground/background colors

-- new hazard button
---@param args hazard_button_args
---@return graphics_element element, element_id id
local function hazard_button(args)
    assert(type(args.text) == "string", "graphics.elements.controls.hazard_button: text is a required field")
    assert(type(args.accent) == "number", "graphics.elements.controls.hazard_button: accent is a required field")
    assert(type(args.callback) == "function", "graphics.elements.controls.hazard_button: callback is a required field")

    -- static dimensions
    args.height = 3
    args.width = string.len(args.text) + 4

    -- create new graphics element base object
    local e = element.new(args)

    -- write the button text
    e.window.setCursorPos(3, 2)
    e.window.write(args.text)

    -- draw border
    ---@param accent color accent color
    local function draw_border(accent)
        -- top
        e.window.setTextColor(accent)
        e.window.setBackgroundColor(args.fg_bg.bkg)
        e.window.setCursorPos(1, 1)
        e.window.write("\x99" .. util.strrep("\x89", args.width - 2) .. "\x99")

        -- center left
        e.window.setCursorPos(1, 2)
        e.window.setTextColor(args.fg_bg.bkg)
        e.window.setBackgroundColor(accent)
        e.window.write("\x99")

        -- center right
        e.window.setTextColor(args.fg_bg.bkg)
        e.window.setBackgroundColor(accent)
        e.window.setCursorPos(args.width, 2)
        e.window.write("\x99")

        -- bottom
        e.window.setTextColor(accent)
        e.window.setBackgroundColor(args.fg_bg.bkg)
        e.window.setCursorPos(1, 3)
        e.window.write("\x99" .. util.strrep("\x98", args.width - 2) .. "\x99")
    end

    -- on request timeout: recursively calls itself to double flash button text
    ---@param n integer call count
    local function on_timeout(n)
        -- start at 0
        if n == nil then n = 0 end

        if n == 0 then
            -- go back off
            e.window.setTextColor(args.fg_bg.fgd)
            e.window.setCursorPos(3, 2)
            e.window.write(args.text)
        end

        if n >= 4 then
            -- done
        elseif n % 2 == 0 then
            -- toggle text color on after 0.25 seconds
            tcd.dispatch(0.25, function ()
                e.window.setTextColor(args.accent)
                e.window.setCursorPos(3, 2)
                e.window.write(args.text)
                on_timeout(n + 1)
                on_timeout(n + 1)
            end)
        elseif n % 1 then
            -- toggle text color off after 0.25 seconds
            tcd.dispatch(0.25, function ()
                e.window.setTextColor(args.fg_bg.fgd)
                e.window.setCursorPos(3, 2)
                e.window.write(args.text)
                on_timeout(n + 1)
            end)
        end
    end

    -- blink routine for success indication
    local function on_success()
        e.window.setTextColor(args.fg_bg.fgd)
        e.window.setCursorPos(3, 2)
        e.window.write(args.text)
    end

    -- blink routine for failure indication
    ---@param n integer call count
    local function on_failure(n)
        -- start at 0
        if n == nil then n = 0 end

        if n == 0 then
            -- go back off
            e.window.setTextColor(args.fg_bg.fgd)
            e.window.setCursorPos(3, 2)
            e.window.write(args.text)
        end

        if n >= 2 then
            -- done
        elseif n % 2 == 0 then
            -- toggle text color on after 0.5 seconds
            tcd.dispatch(0.5, function ()
                e.window.setTextColor(args.accent)
                e.window.setCursorPos(3, 2)
                e.window.write(args.text)
                on_failure(n + 1)
            end)
        elseif n % 1 then
            -- toggle text color off after 0.25 seconds
            tcd.dispatch(0.25, function ()
                e.window.setTextColor(args.fg_bg.fgd)
                e.window.setCursorPos(3, 2)
                e.window.write(args.text)
                on_failure(n + 1)
            end)
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
---@diagnostic disable-next-line: unused-local
    function e.handle_mouse(event)
        if e.enabled then
            -- change text color to indicate clicked
            e.window.setTextColor(args.accent)
            e.window.setCursorPos(3, 2)
            e.window.write(args.text)

            -- abort any other callbacks
            tcd.abort(on_timeout)
            tcd.abort(on_success)
            tcd.abort(on_failure)

            -- 1.5 second timeout
            tcd.dispatch(1.5, on_timeout)

            -- call the touch callback
            args.callback()
        end
    end

    -- callback on request response
    ---@param result boolean true for success, false for failure
    function e.response_callback(result)
        tcd.abort(on_timeout)

        if result then
            on_success()
        else
            on_failure(0)
        end
    end

    -- set the value (true simulates pressing the button)
    ---@param val boolean new value
    function e.set_value(val)
        if val then e.handle_mouse(core.events.mouse_generic("", core.events.click_type.VIRTUAL, 1, 1)) end
    end

    -- show the button as disabled
    function e.disable()
        if args.dis_colors then
            draw_border(args.dis_colors.color_a)
            e.window.setTextColor(args.dis_colors.color_b)
            e.window.setCursorPos(3, 2)
            e.window.write(args.text)
        end
    end

    -- show the button as enabled
    function e.enable()
        draw_border(args.accent)
        e.window.setTextColor(args.fg_bg.fgd)
        e.window.setCursorPos(3, 2)
        e.window.write(args.text)
    end

    -- initial draw of border
    draw_border(args.accent)

    return e.get()
end

return hazard_button
