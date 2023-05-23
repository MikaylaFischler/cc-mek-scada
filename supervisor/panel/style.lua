--
-- Graphics Style Options
--

local core = require("graphics.core")

local style = {}

local cpair = core.cpair

-- GLOBAL --

-- remap global colors
colors.ivory = colors.pink
colors.yellow_hc = colors.purple
colors.red_off = colors.brown
colors.yellow_off = colors.magenta
colors.green_off = colors.lime

style.root = cpair(colors.black, colors.ivory)
style.header = cpair(colors.black, colors.lightGray)

style.colors = {
    { c = colors.red,       hex = 0xdf4949 },   -- RED ON
    { c = colors.orange,    hex = 0xffb659 },
    { c = colors.yellow,    hex = 0xf9fb53 },   -- YELLOW ON
    { c = colors.lime,      hex = 0x16665a },   -- GREEN OFF
    { c = colors.green,     hex = 0x6be551 },   -- GREEN ON
    { c = colors.cyan,      hex = 0x34bac8 },
    { c = colors.lightBlue, hex = 0x6cc0f2 },
    { c = colors.blue,      hex = 0x0008fe },   -- LCD BLUE
    { c = colors.purple,    hex = 0xe3bc2a },   -- YELLOW HIGH CONTRAST
    { c = colors.pink,      hex = 0xdcd9ca },   -- IVORY
    { c = colors.magenta,   hex = 0x85862c },   -- YELLOW OFF
    -- { c = colors.white,     hex = 0xdcd9ca },
    { c = colors.lightGray, hex = 0xb1b8b3 },
    { c = colors.gray,      hex = 0x575757 },
    -- { c = colors.black,     hex = 0x191919 },
    { c = colors.brown,     hex = 0x672223 }    -- RED OFF
}

return style
