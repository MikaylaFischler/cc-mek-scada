--
-- Graphics Style Options
--

local core   = require("graphics.core")
local themes = require("graphics.themes")

---@class svr_style
local style = {}

local cpair = core.cpair

style.theme = themes.sandstone
style.fp = themes.get_fp_style(style.theme)

style.ind_grn = cpair(colors.green, colors.green_off)

-- set theme per configuration
---@param fp integer fp theme ID (1 = sandstone, 2 = basalt)
function style.set_theme(fp)
    if fp == 1 then
        style.theme = themes.sandstone
    elseif fp == 2 then
        style.theme = themes.basalt
    end

    style.fp = themes.get_fp_style(style.theme)
end

return style
