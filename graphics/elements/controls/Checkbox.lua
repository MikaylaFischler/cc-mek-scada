-- Checkbox Graphics Element

local core    = require("graphics.core")
local element = require("graphics.element")

---@class checkbox_args
---@field label string checkbox text
---@field box_fg_bg cpair colors for checkbox
---@field disable_fg_bg? cpair text colors when disabled
---@field default? boolean default value
---@field callback? function function to call on press
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- Create a new checkbox control element.
---@param args checkbox_args
---@return Checkbox element, element_id id
return function (args)
    element.assert(type(args.label) == "string", "label is a required field")
    element.assert(type(args.box_fg_bg) == "table", "box_fg_bg is a required field")

    args.can_focus = true
    args.height = 1
    args.width = 2 + string.len(args.label)

    -- create new graphics element base object
    local e = element.new(args --[[@as graphics_args]])

    e.value = args.default == true

    -- show the button state
    local function draw()
        e.w_set_cur(1, 1)

        local fgd, bkg = args.box_fg_bg.fgd, args.box_fg_bg.bkg

        if (not e.enabled) and type(args.disable_fg_bg) == "table" then
            fgd = args.disable_fg_bg.bkg
            bkg = args.disable_fg_bg.fgd
        end

        if e.value then
            -- show as selected
            e.w_set_fgd(bkg)
            e.w_set_bkg(fgd)
            e.w_write("\x88")
            e.w_set_fgd(fgd)
            e.w_set_bkg(e.fg_bg.bkg)
            e.w_write("\x95")
        else
            -- show as unselected
            e.w_set_fgd(e.fg_bg.bkg)
            e.w_set_bkg(bkg)
            e.w_write("\x88")
            e.w_set_fgd(bkg)
            e.w_set_bkg(e.fg_bg.bkg)
            e.w_write("\x95")
        end
    end

    -- write label text
    local function draw_label()
        if e.enabled and e.is_focused() then
            e.w_set_fgd(e.fg_bg.bkg)
            e.w_set_bkg(e.fg_bg.fgd)
        elseif (not e.enabled) and type(args.disable_fg_bg) == "table" then
            e.w_set_fgd(args.disable_fg_bg.fgd)
            e.w_set_bkg(args.disable_fg_bg.bkg)
        else
            e.w_set_fgd(e.fg_bg.fgd)
            e.w_set_bkg(e.fg_bg.bkg)
        end

        e.w_set_cur(3, 1)
        e.w_write(args.label)
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if e.enabled and core.events.was_clicked(event.type) and e.in_frame_bounds(event.current.x, event.current.y) then
            e.value = not e.value
            draw()
            if type(args.callback) == "function" then args.callback(e.value) end
        end
    end

    -- handle keyboard interaction
    ---@param event key_interaction key event
    function e.handle_key(event)
        if event.type == core.events.KEY_CLICK.DOWN then
            if event.key == keys.space or event.key == keys.enter or event.key == keys.numPadEnter then
                e.value = not e.value
                draw()
                if type(args.callback) == "function" then args.callback(e.value) end
            end
        end
    end

    -- set the value
    ---@param val boolean new value
    function e.set_value(val)
        e.value = val
        draw()
    end

    -- element redraw
    function e.redraw()
        draw()
        draw_label()
    end

    -- handle focus
    e.on_focused = draw_label
    e.on_unfocused = draw_label

    -- handle enable
    e.on_enabled = e.redraw
    e.on_disabled = e.redraw

    ---@class Checkbox:graphics_element
    local Checkbox, id = e.complete(true)

    return Checkbox, id
end
