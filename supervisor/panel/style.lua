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
style.colorblind = false

style.ind_grn = cpair(colors.green, colors.green_off)

-- set theme per configuration
---@param fp FP_THEME front panel theme
---@param color_mode COLOR_MODE the color mode to use
function style.set_theme(fp, color_mode)
    if fp == themes.FP_THEME.SANDSTONE then
        style.theme = themes.sandstone
    elseif fp == themes.FP_THEME.BASALT then
        style.theme = themes.basalt
    end

    style.fp = themes.get_fp_style(style.theme)

    style.colorblind = color_mode ~= themes.COLOR_MODE.STANDARD and color_mode ~= themes.COLOR_MODE.STD_ON_BLACK
end

return style
