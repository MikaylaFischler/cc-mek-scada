-- Multi-Pane Display Graphics Element

local element = require("graphics.element")

---@class multipane_args
---@field panes table panes to swap between
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- Create a new multipane container element.
---@nodiscard
---@param args multipane_args
---@return MultiPane element, element_id id
return function (args)
    element.assert(type(args.panes) == "table", "panes is a required field")

    -- create new graphics element base object
    local e = element.new(args --[[@as graphics_args]])

    e.value = 1

    -- show the selected pane
    function e.redraw()
        for i = 1, #args.panes do args.panes[i].hide() end
        args.panes[e.value].show()
    end

    -- select which pane is shown
    ---@param value integer pane to show
    function e.set_value(value)
        if (e.value ~= value) and (value > 0) and (value <= #args.panes) then
            e.value = value
            e.redraw()
        end
    end

    ---@class MultiPane:graphics_element
    local MultiPane, id = e.complete(true)

    return MultiPane, id
end
