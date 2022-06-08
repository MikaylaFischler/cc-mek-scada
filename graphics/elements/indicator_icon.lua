-- Icon Indicator Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class icon_sym_color
---@field color cpair
---@field symbol string

---@class icon_indicator_args
---@field text string indicator text
---@field states table state color and symbol table
---@field default? integer default state, defaults to 1
---@field min_text_width? integer text length if omitted
---@field parent graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field height? integer parent height if omitted
---@field fg_bg cpair foreground/background colors

-- new icon indicator
---@param args icon_indicator_args
local function icon_indicator(args)
    -- determine width
    args.width = (args.min_text_width or string.len(args.text)) + 4

    -- create new graphics element base object
    local e = element.new(args)

    -- state blit strings
    local state_blit_cmds = {}
    for i = 1, #args.states do
        local sym_color = args.states[i]    ---@type icon_sym_color

        table.insert(state_blit_cmds, {
            text = " " .. sym_color.symbol .. " ",
            fgd = util.strrep(sym_color.color.blit_fgd, 3),
            bkg = util.strrep(sym_color.color.blit_bkg, 3)
        })
    end

    -- write text and initial indicator light
    e.setCursorPos(5, 1)
    e.window.write(args.text)

    -- on state change
    ---@param new_state integer indicator state
    function e.on_update(new_state)
        local blit_cmd = state_blit_cmds[new_state]
        e.window.setCursorPos(1, 1)
        e.window.blit(blit_cmd.text, blit_cmd.fgd, blit_cmd.bkg)
    end

    -- initial icon draw
    e.on_update(args.default or 1)

    return e.get()
end

return icon_indicator
