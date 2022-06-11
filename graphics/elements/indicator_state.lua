-- State (Text) Indicator Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class state_text_color
---@field color cpair
---@field text string

---@class state_indicator_args
---@field states table state color and text table
---@field default? integer default state, defaults to 1
---@field min_width? integer max state text length if omitted
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field height? integer 1 if omitted, must be an odd number
---@field fg_bg? cpair foreground/background colors

-- new state indicator
---@param args state_indicator_args
local function state_indicator(args)
    assert(type(args.states) == "table", "graphics.elements.indicator_state: states is a required field")

    -- determine height
    if util.is_int(args.height) then
        assert(args.height % 2 == 1, "graphics.elements.indicator_state: height should be an odd number")
    else
        args.height = 1
    end

    -- initial guess at width
    args.width = args.min_width or 1

    -- state blit strings
    local state_blit_cmds = {}
    for i = 1, #args.states do
        local state_def = args.states[i]    ---@type state_text_color

        -- re-determine width
        if string.len(state_def.text) > args.width then
            args.width = string.len(state_def.text)
        end

        local len = string.len(state_def.text)
        local lpad = math.floor((args.width - len) / 2)
        local rpad = len - lpad

        table.insert(state_blit_cmds, {
            text = util.spaces(lpad) .. state_def.text .. util.spaces(rpad),
            fgd = util.strrep(state_def.color.blit_fgd, 3),
            bkg = util.strrep(state_def.color.blit_bkg, 3)
        })
    end

    -- create new graphics element base object
    local e = element.new(args)

    -- on state change
    ---@param new_state integer indicator state
    function e.on_update(new_state)
        local blit_cmd = state_blit_cmds[new_state]
        e.window.setCursorPos(1, 1)
        e.window.blit(blit_cmd.text, blit_cmd.fgd, blit_cmd.bkg)
    end

    -- initial draw
    e.on_update(args.default or 1)

    return e.get()
end

return state_indicator
