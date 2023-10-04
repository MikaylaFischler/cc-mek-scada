-- State (Text) Indicator Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class state_text_color
---@field color cpair
---@field text string

---@class state_indicator_args
---@field states table state color and text table
---@field value? integer default state, defaults to 1
---@field min_width? integer max state text length if omitted
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field height? integer 1 if omitted, must be an odd number
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new state indicator
---@nodiscard
---@param args state_indicator_args
---@return graphics_element element, element_id id
local function state_indicator(args)
    element.assert(type(args.states) == "table", "states is a required field")

    if util.is_int(args.height) then
        element.assert(args.height % 2 == 1, "height should be an odd number")
    else args.height = 1 end

    args.width = args.min_width or 1

    -- state blit strings
    local state_blit_cmds = {}
    for i = 1, #args.states do
        local state_def = args.states[i]    ---@type state_text_color

        if string.len(state_def.text) > args.width then
            args.width = string.len(state_def.text)
        end

        local text = util.pad(state_def.text, args.width)

        table.insert(state_blit_cmds, {
            text = text,
            fgd = string.rep(state_def.color.blit_fgd, string.len(text)),
            bkg = string.rep(state_def.color.blit_bkg, string.len(text))
        })
    end

    -- create new graphics element base object
    local e = element.new(args)

    e.value = args.value or 1

    -- element redraw
    function e.redraw()
        local blit_cmd = state_blit_cmds[e.value]
        e.w_set_cur(1, 1)
        e.w_blit(blit_cmd.text, blit_cmd.fgd, blit_cmd.bkg)
    end

    -- on state change
    ---@param new_state integer indicator state
    function e.on_update(new_state)
        e.value = new_state
        e.redraw()
    end

    -- set indicator state
    ---@param val integer indicator state
    function e.set_value(val) e.on_update(val) end

    -- initial draw
    e.redraw()

    return e.complete()
end

return state_indicator
