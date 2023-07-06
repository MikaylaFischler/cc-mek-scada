-- Checkbox Graphics Element

local core    = require("graphics.core")
local element = require("graphics.element")

---@class checkbox_args
---@field label string checkbox text
---@field box_fg_bg cpair colors for checkbox
---@field callback function function to call on press
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new checkbox control
---@param args checkbox_args
---@return graphics_element element, element_id id
local function checkbox(args)
    assert(type(args.label) == "string", "graphics.elements.controls.checkbox: label is a required field")
    assert(type(args.box_fg_bg) == "table", "graphics.elements.controls.checkbox: box_fg_bg is a required field")
    assert(type(args.callback) == "function", "graphics.elements.controls.checkbox: callback is a required field")

    args.height = 1
    args.width = 3 + string.len(args.label)

    -- create new graphics element base object
    local e = element.new(args)

    e.value = false

    -- show the button state
    local function draw()
        e.window.setCursorPos(1, 1)

        if e.value then
            -- show as selected
            e.window.setTextColor(args.box_fg_bg.bkg)
            e.window.setBackgroundColor(args.box_fg_bg.fgd)
            e.window.write("\x88")
            e.window.setTextColor(args.box_fg_bg.fgd)
            e.window.setBackgroundColor(e.fg_bg.bkg)
            e.window.write("\x95")
        else
            -- show as unselected
            e.window.setTextColor(e.fg_bg.bkg)
            e.window.setBackgroundColor(args.box_fg_bg.bkg)
            e.window.write("\x88")
            e.window.setTextColor(args.box_fg_bg.bkg)
            e.window.setBackgroundColor(e.fg_bg.bkg)
            e.window.write("\x95")
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if e.enabled and core.events.was_clicked(event.type) then
            e.value = not e.value
            draw()
            args.callback(e.value)
        end
    end

    -- set the value
    ---@param val integer new value
    function e.set_value(val)
        e.value = val
        draw()
    end

    -- write label text
    e.window.setCursorPos(3, 1)
    e.window.setTextColor(e.fg_bg.fgd)
    e.window.setBackgroundColor(e.fg_bg.bkg)
    e.window.write(args.label)

    -- initial draw
    draw()

    return e.complete()
end

return checkbox
