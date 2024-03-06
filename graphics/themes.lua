--
-- Graphics Themes
--

local core = require("graphics.core")

local cpair = core.cpair

---@class graphics_themes
local themes = {}

-- add color mappings for front panel
colors.ivory = colors.pink
colors.yellow_hc = colors.purple
colors.red_off = colors.brown
colors.yellow_off = colors.magenta
colors.green_off = colors.lime

---@class fp_theme
themes.sandstone = {
    text = colors.black,
    label = colors.lightGray,
    label_dark = colors.gray,
    disabled = colors.lightGray,
    bg = colors.ivory,

    header = cpair(colors.black, colors.lightGray),

    highlight_box = cpair(colors.black, colors.lightGray),
    highlight_box_bright = cpair(colors.black, colors.white),
    field_box = cpair(colors.gray, colors.white),

    colors = {
        { c = colors.red,       hex = 0xdf4949 },   -- RED ON
        { c = colors.orange,    hex = 0xffb659 },
        { c = colors.yellow,    hex = 0xf9fb53 },   -- YELLOW ON
        { c = colors.lime,      hex = 0x16665a },   -- GREEN OFF
        { c = colors.green,     hex = 0x6be551 },   -- GREEN ON
        { c = colors.cyan,      hex = 0x34bac8 },
        { c = colors.lightBlue, hex = 0x6cc0f2 },
        { c = colors.blue,      hex = 0x0096ff },
        { c = colors.purple,    hex = 0xe3bc2a },   -- YELLOW HIGH CONTRAST
        { c = colors.pink,      hex = 0xdcd9ca },   -- IVORY
        { c = colors.magenta,   hex = 0x85862c },   -- YELLOW OFF
        { c = colors.white,     hex = 0xf0f0f0 },
        { c = colors.lightGray, hex = 0xb1b8b3 },
        { c = colors.gray,      hex = 0x575757 },
        { c = colors.black,     hex = 0x191919 },
        { c = colors.brown,     hex = 0x672223 }    -- RED OFF
    }
}

---@type fp_theme
themes.basalt = {
    text = colors.white,
    label = colors.gray,
    label_dark = colors.ivory,
    disabled = colors.lightGray,
    bg = colors.ivory,

    header = cpair(colors.white, colors.gray),

    highlight_box = cpair(colors.white, colors.gray),
    highlight_box_bright = cpair(colors.black, colors.lightGray),
    field_box = cpair(colors.white, colors.gray),

    colors = {
        { c = colors.red,       hex = 0xdc6466 },   -- RED ON
        { c = colors.orange,    hex = 0xffb659 },
        { c = colors.yellow,    hex = 0xebdf75 },   -- YELLOW ON
        { c = colors.lime,      hex = 0x496b41 },   -- GREEN OFF
        { c = colors.green,     hex = 0x81db6d },   -- GREEN ON
        { c = colors.cyan,      hex = 0x5ec7d1 },
        { c = colors.lightBlue, hex = 0x7dc6f2 },
        { c = colors.blue,      hex = 0x56aae6 },
        { c = colors.purple,    hex = 0xe9cd68 },   -- YELLOW HIGH CONTRAST
        { c = colors.pink,      hex = 0x4d4e52 },   -- IVORY
        { c = colors.magenta,   hex = 0x6b6c36 },   -- YELLOW OFF
        { c = colors.white,     hex = 0xbfbfbf },
        { c = colors.lightGray, hex = 0x848794 },
        { c = colors.gray,      hex = 0x5c5f68 },
        { c = colors.black,     hex = 0x262626 },
        { c = colors.brown,     hex = 0x653839 }    -- RED OFF
    }
}

-- get style fields for a front panel based on the provided theme
---@param theme fp_theme
function themes.get_fp_style(theme)
    ---@class fp_style
    local style =  {
        root = cpair(theme.text, theme.bg),

        text = cpair(theme.text, theme.bg),
        text_fg = cpair(theme.text, colors._INHERIT),

        label_fg = cpair(theme.label, colors._INHERIT),
        label_d_fg = cpair(theme.label_dark, colors._INHERIT),

        disabled_fg = cpair(theme.disabled, colors._INHERIT)
    }

    return style
end











return themes
