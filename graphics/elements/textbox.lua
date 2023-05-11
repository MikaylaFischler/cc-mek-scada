-- Text Box Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

local TEXT_ALIGN = core.TEXT_ALIGN

---@class textbox_args
---@field text string text to show
---@field alignment? TEXT_ALIGN text alignment, left by default
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors

-- new text box
---@param args textbox_args
---@return graphics_element element, element_id id
local function textbox(args)
    assert(type(args.text) == "string", "graphics.elements.textbox: text is a required field")

    -- create new graphics element base object
    local e = element.new(args)

    local alignment = args.alignment or TEXT_ALIGN.LEFT

    -- draw textbox

    local function display_text(text)
        e.value = text

        local lines = util.strwrap(text, e.frame.w)

        for i = 1, #lines do
            if i > e.frame.h then break end

            local len = string.len(lines[i])

            -- use cursor position to align this line
            if alignment == TEXT_ALIGN.CENTER then
                e.window.setCursorPos(math.floor((e.frame.w - len) / 2) + 1, i)
            elseif alignment == TEXT_ALIGN.RIGHT then
                e.window.setCursorPos((e.frame.w - len) + 1, i)
            else
                e.window.setCursorPos(1, i)
            end

            e.window.write(lines[i])
        end
    end

    display_text(args.text)

    -- set the string value and re-draw the text
    ---@param val string value
    function e.set_value(val)
        e.window.clear()
        display_text(val)
    end

    return e.get()
end

return textbox
