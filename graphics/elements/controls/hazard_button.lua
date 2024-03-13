-- Hazard-bordered Button Graphics Element

local tcd     = require("scada-common.tcd")

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
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new hazard button
---@param args hazard_button_args
---@return graphics_element element, element_id id
local function hazard_button(args)
    element.assert(type(args.text) == "string", "text is a required field")
    element.assert(type(args.accent) == "number", "accent is a required field")
    element.assert(type(args.callback) == "function", "callback is a required field")

    args.height = 3
    args.width = string.len(args.text) + 4

    -- create new graphics element base object
    local e = element.new(args)

    -- draw border
    ---@param accent color accent color
    local function draw_border(accent)
        -- top
        e.w_set_fgd(accent)
        e.w_set_bkg(args.fg_bg.bkg)
        e.w_set_cur(1, 1)
        e.w_write("\x99" .. string.rep("\x89", args.width - 2) .. "\x99")

        -- center left
        e.w_set_cur(1, 2)
        e.w_set_fgd(args.fg_bg.bkg)
        e.w_set_bkg(accent)
        e.w_write("\x99")

        -- center right
        e.w_set_fgd(args.fg_bg.bkg)
        e.w_set_bkg(accent)
        e.w_set_cur(args.width, 2)
        e.w_write("\x99")

        -- bottom
        e.w_set_fgd(accent)
        e.w_set_bkg(args.fg_bg.bkg)
        e.w_set_cur(1, 3)
        e.w_write("\x99" .. string.rep("\x98", args.width - 2) .. "\x99")
    end

    -- on request timeout: recursively calls itself to double flash button text
    ---@param n integer call count
    local function on_timeout(n)
        -- start at 0
        if n == nil then n = 0 end

        if n == 0 then
            -- go back off
            e.w_set_fgd(args.fg_bg.fgd)
            e.w_set_cur(3, 2)
            e.w_write(args.text)
        end

        if n >= 4 then
            -- done
        elseif n % 2 == 0 then
            -- toggle text color on after 0.25 seconds
            tcd.dispatch(0.25, function ()
                e.w_set_fgd(args.accent)
                e.w_set_cur(3, 2)
                e.w_write(args.text)
                on_timeout(n + 1)
                on_timeout(n + 1)
            end)
        elseif n % 1 then
            -- toggle text color off after 0.25 seconds
            tcd.dispatch(0.25, function ()
                e.w_set_fgd(args.fg_bg.fgd)
                e.w_set_cur(3, 2)
                e.w_write(args.text)
                on_timeout(n + 1)
            end)
        end
    end

    -- blink routine for success indication
    local function on_success()
        e.w_set_fgd(args.fg_bg.fgd)
        e.w_set_cur(3, 2)
        e.w_write(args.text)
    end

    -- blink routine for failure indication
    ---@param n integer call count
    local function on_failure(n)
        -- start at 0
        if n == nil then n = 0 end

        if n == 0 then
            -- go back off
            e.w_set_fgd(args.fg_bg.fgd)
            e.w_set_cur(3, 2)
            e.w_write(args.text)
        end

        if n >= 2 then
            -- done
        elseif n % 2 == 0 then
            -- toggle text color on after 0.5 seconds
            tcd.dispatch(0.5, function ()
                e.w_set_fgd(args.accent)
                e.w_set_cur(3, 2)
                e.w_write(args.text)
                on_failure(n + 1)
            end)
        elseif n % 1 then
            -- toggle text color off after 0.25 seconds
            tcd.dispatch(0.25, function ()
                e.w_set_fgd(args.fg_bg.fgd)
                e.w_set_cur(3, 2)
                e.w_write(args.text)
                on_failure(n + 1)
            end)
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if e.enabled and core.events.was_clicked(event.type) and e.in_frame_bounds(event.current.x, event.current.y) then
            -- change text color to indicate clicked
            e.w_set_fgd(args.accent)
            e.w_set_cur(3, 2)
            e.w_write(args.text)

            -- abort any other callbacks
            tcd.abort(on_timeout)
            tcd.abort(on_success)
            tcd.abort(on_failure)

            -- 1.5 second timeout
            tcd.dispatch(1.5, on_timeout)

            args.callback()
        end
    end

    -- callback on request response
    ---@param result boolean true for success, false for failure
    function e.response_callback(result)
        tcd.abort(on_timeout)
        if result then on_success() else on_failure(0) end
    end

    -- set the value (true simulates pressing the button)
    ---@param val boolean new value
    function e.set_value(val)
        if val then e.handle_mouse(core.events.mouse_generic(core.events.MOUSE_CLICK.UP, 1, 1)) end
    end

    -- show the button as disabled
    function e.on_disabled()
        if args.dis_colors then
            draw_border(args.dis_colors.color_a)
            e.w_set_fgd(args.dis_colors.color_b)
            e.w_set_cur(3, 2)
            e.w_write(args.text)
        end
    end

    -- show the button as enabled
    function e.on_enabled()
        draw_border(args.accent)
        e.w_set_fgd(args.fg_bg.fgd)
        e.w_set_cur(3, 2)
        e.w_write(args.text)
    end

    -- element redraw
    function e.redraw()
        -- write the button text and draw border
        e.w_set_cur(3, 2)
        e.w_write(args.text)
        draw_border(args.accent)
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return hazard_button
