--
-- Graphics Style Options
--

local core   = require("graphics.core")
local themes = require("graphics.themes")

---@class plc_style
local style = {}

local cpair = core.cpair

style.theme = themes.basalt
style.fp = themes.get_fp_style(style.theme)

style.ind_grn = cpair(colors.green, colors.green_off)
style.ind_red = cpair(colors.red, colors.red_off)

return style
