--
-- Graphics Style Options
--

local core = require("graphics.core")

local style = {}

local cpair = core.graphics.cpair

-- GLOBAL --

-- remap global colors
colors.ivory = colors.pink
colors.red_off = colors.brown
colors.green_off = colors.lime

style.root = cpair(colors.black, colors.ivory)
style.header = cpair(colors.black, colors.lightGray)
style.label = cpair(colors.gray, colors.lightGray)

style.colors = {
    { c = colors.red,       hex = 0xdf4949 },   -- RED ON
    { c = colors.orange,    hex = 0xffb659 },
    { c = colors.yellow,    hex = 0xe5e552 },
    { c = colors.lime,      hex = 0x16665a },   -- GREEN OFF
    { c = colors.green,     hex = 0x6be551 },   -- GREEN ON
    { c = colors.cyan,      hex = 0x34bac8 },
    { c = colors.lightBlue, hex = 0x6cc0f2 },
    { c = colors.blue,      hex = 0x0096ff },
    { c = colors.purple,    hex = 0xb156ee },
    { c = colors.pink,      hex = 0xdcd9ca },   -- IVORY
    { c = colors.magenta,   hex = 0xf9488a },
    -- { c = colors.white,     hex = 0xdcd9ca },
    { c = colors.lightGray, hex = 0x999f9b },
    { c = colors.gray,      hex = 0x575757 },
    -- { c = colors.black,     hex = 0x191919 },
    { c = colors.brown,     hex = 0x672223 }    -- RED OFF
}

return style
