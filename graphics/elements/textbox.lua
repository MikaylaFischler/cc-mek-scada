-- Text Box Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

---@class textbox_args
---@field text string text to show
---@field parent graphics_element
---@field alignment? TEXT_ALIGN text alignment, left by default
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

    local alignment = args.alignment or TEXT_ALIGN.LEFT

    -- draw textbox

    local text = args.text
    local lines = util.strwrap(text, e.frame.w)

    for i = 1, #lines do
        if i > e.frame.h then break end

        local len = string.len(lines[i])

        -- use cursor position to align this line
        if alignment == TEXT_ALIGN.CENTER then
            e.window.setCursorPos(math.floor((e.frame.w - len) / 2), i)
        elseif alignment == TEXT_ALIGN.RIGHT then
            e.window.setCursorPos(e.frame.w - len, i)
        else
            e.window.setCursorPos(1, i)
        end

        e.window.write(lines[i])
    end

    return e.get()
end

return textbox
