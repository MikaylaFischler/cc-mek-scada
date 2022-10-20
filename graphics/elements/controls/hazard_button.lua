-- Hazard-bordered Button Graphics Element

local tcd     = require("scada-common.tcallbackdsp")

local core    = require("graphics.core")
local element = require("graphics.element")

---@class hazard_button_args
---@field text string text to show on button
---@field accent color accent color for hazard border
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
        e.window.setTextColor(args.accent)
        e.window.setBackgroundColor(args.fg_bg.bkg)
        e.window.setCursorPos(1, 1)
        e.window.write("\x99\x89\x89\x89\x89\x89\x89\x89\x99")

        -- center left
        e.window.setCursorPos(1, 2)
        e.window.setTextColor(args.fg_bg.bkg)
        e.window.setBackgroundColor(args.accent)
        e.window.write("\x99")

        -- center right
        e.window.setTextColor(args.fg_bg.bkg)
        e.window.setBackgroundColor(args.accent)
        e.window.setCursorPos(9, 2)
        e.window.write("\x99")

        -- bottom
        e.window.setTextColor(args.accent)
        e.window.setBackgroundColor(args.fg_bg.bkg)
        e.window.setCursorPos(1, 3)
        e.window.write("\x99\x98\x98\x98\x98\x98\x98\x98\x99")
    end

    -- handle touch
    ---@param event monitor_touch monitor touch event
---@diagnostic disable-next-line: unused-local
    function e.handle_touch(event)
        if e.enabled then
            -- call the touch callback
            args.callback()

            -- change text color to indicate clicked
            e.window.setTextColor(args.accent)
            e.window.setCursorPos(3, 2)
            e.window.write(args.text)

            -- restore text color after 1 second
            tcd.dispatch(1, function ()
                e.window.setTextColor(args.fg_bg.fgd)
                e.window.setCursorPos(3, 2)
                e.window.write(args.text)
            end)
        end
    end

    -- set the value
    ---@param val boolean new value
    function e.set_value(val)
        if val then e.handle_touch(core.events.touch("", 1, 1)) end
    end

    return e.get()
end

return hazard_button
