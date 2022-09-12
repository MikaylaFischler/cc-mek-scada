-- Button Graphics Element

local tcd     = require("scada-common.tcallbackdsp")

local core    = require("graphics.core")
local element = require("graphics.element")

---@class push_button_args
---@field text string button text
---@field callback function function to call on touch
---@field min_width? integer text length + 2 if omitted
---@field active_fg_bg? cpair foreground/background colors when pressed
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field height? integer parent height if omitted
---@field fg_bg? cpair foreground/background colors

-- new push button
---@param args push_button_args
---@return graphics_element element, element_id id
local function push_button(args)
    assert(type(args.text) == "string", "graphics.elements.controls.push_button: text is a required field")
    assert(type(args.callback) == "function", "graphics.elements.controls.push_button: callback is a required field")

    -- single line
    args.height = 1

    args.min_width = args.min_width or 0

    local text_width = string.len(args.text)
    args.width = math.max(text_width + 2, args.min_width)

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

    -- handle touch
    ---@param event monitor_touch monitor touch event
---@diagnostic disable-next-line: unused-local
    function e.handle_touch(event)
        if args.active_fg_bg ~= nil then
            -- show as pressed
            e.value = true
            e.window.setTextColor(args.active_fg_bg.fgd)
            e.window.setBackgroundColor(args.active_fg_bg.bkg)
            draw()

            -- show as unpressed in 0.25 seconds
            tcd.dispatch(0.25, function ()
                e.value = false
                e.window.setTextColor(e.fg_bg.fgd)
                e.window.setBackgroundColor(e.fg_bg.bkg)
                draw()
            end)
        end

        -- call the touch callback
        args.callback()
    end

    -- set the value
    ---@param val boolean new value
    function e.set_value(val)
        if val then e.handle_touch(core.events.touch("", 1, 1)) end
    end

    -- initial draw
    draw()

    return e.get()
end

return push_button
