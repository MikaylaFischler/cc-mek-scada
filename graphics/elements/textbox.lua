-- Text Box Graphics Element

local element = require("graphics.element")

---@class textbox_args
---@field text string text to show
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors

-- new text box
---@param args textbox_args
local function textbox(args)
    assert(args.text ~= nil, "graphics.elements.textbox: empty text box")

    -- create new graphics element base object
    local e = element.new(args)

    -- write text

    local text = args.text
    local lines = { text }

    local w = e.frame.w
    local h = e.frame.h

    -- wrap if needed
    if string.len(text) > w then
        local remaining = true
        local s_start = 1
        local s_end = w
        local i = 1

        lines = {}

        while remaining do
            local line = string.sub(text, s_start, s_end)

            if line == "" then
                remaining = false
            else
                lines[i] = line

                s_start = s_end + 1
                s_end = s_end + w
                i = i + 1
            end
        end
    end

    -- output message
    for i = 1, #lines do
        local cur_x, cur_y = e.window.getCursorPos()

        if i > 1 and cur_x > 1 then
            if cur_y == h then
                e.window.scroll(1)
                e.window.setCursorPos(1, cur_y)
            else
                e.window.setCursorPos(1, cur_y + 1)
            end
        end

        e.window.write(lines[i])
    end

    return e.get()
end

return textbox
