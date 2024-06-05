-- Text Box Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

local ALIGN = core.ALIGN

---@class textbox_args
---@field text string text to show
---@field alignment? ALIGN text alignment, left by default
---@field anchor? boolean true to use this as an anchor, making it focusable
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width? integer parent width if omitted
---@field height? integer minimum necessary height for wrapped text if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new text box
---@param args textbox_args
---@return graphics_element element, element_id id
local function textbox(args)
    element.assert(type(args.text) == "string", "text is a required field")

    if args.anchor == true then args.can_focus = true end

    -- regex to identify entries without a height currently: ^.*TextBox\{((?!height=).)*$
    -- provide a constraint condition to element creation to prevent an pointlessly tall text box
    ---@param frame graphics_frame
    local function constrain(frame)
        return frame.w, math.max(args.height, math.max(1, #util.strwrap(args.text, frame.w)))
    end

    -- create new graphics element base object
    local e = element.new(args, constrain)

    e.value = args.text

    local alignment = args.alignment or ALIGN.LEFT

    -- draw textbox
    function e.redraw()
        e.window.clear()

        local lines = util.strwrap(e.value, e.frame.w)

        for i = 1, #lines do
            if i > e.frame.h then break end

            local len = string.len(lines[i])

            -- use cursor position to align this line
            if alignment == ALIGN.CENTER then
                e.w_set_cur(math.floor((e.frame.w - len) / 2) + 1, i)
            elseif alignment == ALIGN.RIGHT then
                e.w_set_cur((e.frame.w - len) + 1, i)
            else
                e.w_set_cur(1, i)
            end

            e.w_write(lines[i])
        end
    end

    -- set the string value and re-draw the text
    ---@param val string value
    function e.set_value(val)
        e.value = val
        e.redraw()
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return textbox
