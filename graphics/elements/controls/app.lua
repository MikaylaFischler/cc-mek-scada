-- App Button Graphics Element

local tcd     = require("scada-common.tcd")

local core    = require("graphics.core")
local element = require("graphics.element")

local MOUSE_CLICK = core.events.MOUSE_CLICK

---@class app_button_args
---@field text string app icon text
---@field title string app title text
---@field callback function function to call on touch
---@field app_fg_bg cpair app icon foreground/background colors
---@field active_fg_bg? cpair foreground/background colors when pressed
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new app button
---@param args app_button_args
---@return graphics_element element, element_id id
local function app_button(args)
    element.assert(type(args.text) == "string", "text is a required field")
    element.assert(type(args.title) == "string", "title is a required field")
    element.assert(type(args.callback) == "function", "callback is a required field")
    element.assert(type(args.app_fg_bg) == "table", "app_fg_bg is a required field")

    args.height = 4
    args.width = 5

    -- create new graphics element base object
    local e = element.new(args)

    -- draw the app button
    local function draw()
        local fgd = args.app_fg_bg.fgd
        local bkg = args.app_fg_bg.bkg

        if e.value then
            fgd = args.active_fg_bg.fgd
            bkg = args.active_fg_bg.bkg
        end

        -- draw icon
        e.w_set_cur(1, 1)
        e.w_set_fgd(fgd)
        e.w_set_bkg(bkg)
        e.w_write("\x9f\x83\x83\x83")
        e.w_set_fgd(bkg)
        e.w_set_bkg(fgd)
        e.w_write("\x90")
        e.w_set_fgd(fgd)
        e.w_set_bkg(bkg)
        e.w_set_cur(1, 2)
        e.w_write("\x95   ")
        e.w_set_fgd(bkg)
        e.w_set_bkg(fgd)
        e.w_write("\x95")
        e.w_set_cur(1, 3)
        e.w_write("\x82\x8f\x8f\x8f\x81")

        -- write the icon text
        e.w_set_cur(3, 2)
        e.w_set_fgd(fgd)
        e.w_set_bkg(bkg)
        e.w_write(args.text)
    end

    -- draw the app button as pressed (if active_fg_bg set)
    local function show_pressed()
        if e.enabled and args.active_fg_bg ~= nil then
            e.value = true
            e.w_set_fgd(args.active_fg_bg.fgd)
            e.w_set_bkg(args.active_fg_bg.bkg)
            draw()
        end
    end

    -- draw the app button as unpressed (if active_fg_bg set)
    local function show_unpressed()
        if e.enabled and args.active_fg_bg ~= nil then
            e.value = false
            e.w_set_fgd(e.fg_bg.fgd)
            e.w_set_bkg(e.fg_bg.bkg)
            draw()
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

    -- set the value (true simulates pressing the app button)
    ---@param val boolean new value
    function e.set_value(val)
        if val then e.handle_mouse(core.events.mouse_generic(core.events.MOUSE_CLICK.UP, 1, 1)) end
    end

    -- element redraw
    function e.redraw()
        e.w_set_cur(math.floor((e.frame.w - string.len(args.title)) / 2) + 1, 4)
        e.w_write(args.title)
        draw()
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return app_button
