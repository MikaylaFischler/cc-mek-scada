-- Button Graphics Element

local tcd     = require("scada-common.tcallbackdsp")

local element = require("graphics.element")

---@class button_args
---@field text string button text
---@field callback function function to call on touch
---@field min_width? integer text length + 2 if omitted
---@field active_fg_bg? cpair foreground/background colors when pressed
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg cpair foreground/background colors

-- new button
---@param args button_args
local function button(args)
    local text_width = string.len(args.text)
    args.width = math.max(text_width + 2, args.min_width)

    -- create new graphics element base object
    local e = element.new(args)

    local h_pad = math.floor((e.frame.w - text_width) / 2)
    local v_pad = math.floor(e.frame.h / 2) + 1

    -- write the button text
    e.window.setCursorPos(h_pad, v_pad)
    e.write(args.text)

    -- handle touch
    function e.handle_touch(event)
        if args.active_fg_bg ~= nil then
            -- show as pressed
            e.window.setTextColor(args.active_fg_bg.fgd)
            e.window.setBackgroundColor(args.active_fg_bg.bkg)
            e.window.redraw()

            -- show as unpressed in 0.5 seconds
            tcd.dispatch(0.5, function ()
                e.window.setTextColor(e.fg_bg.fgd)
                e.window.setBackgroundColor(e.fg_bg.bkg)
                e.window.redraw()
            end)
        end

        -- call the touch callback
        args.callback()
    end

    return e.get()
end

return button
