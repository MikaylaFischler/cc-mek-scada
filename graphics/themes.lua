--
-- Graphics Themes
--

local core = require("graphics.core")

local cpair = core.cpair

---@class graphics_themes
local themes = {}

-- add color mappings for front panels
colors.ivory      = colors.pink
colors.green_hc   = colors.cyan
colors.yellow_hc  = colors.purple
colors.red_off    = colors.brown
colors.yellow_off = colors.magenta
colors.green_off  = colors.lime

--#region Types

---@enum UI_THEME
themes.UI_THEME = { SMOOTH_STONE = 1, DEEPSLATE = 2 }
themes.UI_THEME_NAMES = { "Smooth Stone", "Deepslate" }

-- attempts to get the string name of a main ui theme
---@nodiscard
---@param id any
---@return string|nil
function themes.ui_theme_name(id)
    if id == themes.UI_THEME.SMOOTH_STONE or
       id == themes.UI_THEME.DEEPSLATE then
        return themes.UI_THEME_NAMES[id]
    else return nil end
end

---@enum FP_THEME
themes.FP_THEME = { SANDSTONE = 1, BASALT = 2 }
themes.FP_THEME_NAMES = { "Sandstone", "Basalt" }

-- attempts to get the string name of a front panel theme
---@nodiscard
---@param id any
---@return string|nil
function themes.fp_theme_name(id)
    if id == themes.FP_THEME.SANDSTONE or
       id == themes.FP_THEME.BASALT then
        return themes.FP_THEME_NAMES[id]
    else return nil end
end

---@enum COLOR_MODE
themes.COLOR_MODE = {
    STANDARD = 1,
    DEUTERANOPIA = 2,
    PROTANOPIA = 3,
    TRITANOPIA = 4,
    BLUE_IND = 5,
    STD_ON_BLACK = 6,
    BLUE_ON_BLACK = 7,
    NUM_MODES = 8
}

themes.COLOR_MODE_NAMES = {
    "Standard",
    "Deuteranopia",
    "Protanopia",
    "Tritanopia",
    "Blue for 'Good'",
    "Standard + Black",
    "Blue + Black"
}

-- attempts to get the string name of a color mode
---@nodiscard
---@param id any
---@return string|nil
function themes.color_mode_name(id)
    if id == themes.COLOR_MODE.STANDARD or
       id == themes.COLOR_MODE.DEUTERANOPIA or
       id == themes.COLOR_MODE.PROTANOPIA or
       id == themes.COLOR_MODE.TRITANOPIA or
       id == themes.COLOR_MODE.BLUE_IND or
       id == themes.COLOR_MODE.STD_ON_BLACK or
       id == themes.COLOR_MODE.BLUE_ON_BLACK then
        return themes.COLOR_MODE_NAMES[id]
    else return nil end
end

--#endregion

--#region Front Panel Themes

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
        { c = colors.red,        hex = 0xdf4949 },
        { c = colors.orange,     hex = 0xffb659 },
        { c = colors.yellow,     hex = 0xf9fb53 },
        { c = colors.green_off,  hex = 0x16665a },
        { c = colors.green,      hex = 0x6be551 },
        { c = colors.green_hc,   hex = 0x6be551 },
        { c = colors.lightBlue,  hex = 0x6cc0f2 },
        { c = colors.blue,       hex = 0x0096ff },
        { c = colors.yellow_hc,  hex = 0xe3bc2a },
        { c = colors.ivory,      hex = 0xdcd9ca },
        { c = colors.yellow_off, hex = 0x85862c },
        { c = colors.white,      hex = 0xf0f0f0 },
        { c = colors.lightGray,  hex = 0xb1b8b3 },
        { c = colors.gray,       hex = 0x575757 },
        { c = colors.black,      hex = 0x191919 },
        { c = colors.red_off,    hex = 0x672223 }
    },

    -- color re-mappings for assistive modes
    color_modes = {
        -- standard
        {},
        -- deuteranopia
        {
            { c = colors.green,      hex = 0x1081ff },
            { c = colors.green_hc,   hex = 0x1081ff },
            { c = colors.green_off,  hex = 0x141414 },
            { c = colors.yellow,     hex = 0xf7c311 },
            { c = colors.yellow_off, hex = 0x141414 },
            { c = colors.red,        hex = 0xfb5615 },
            { c = colors.red_off,    hex = 0x141414 }
        },
        -- protanopia
        {
            { c = colors.green,      hex = 0x1081ff },
            { c = colors.green_hc,   hex = 0x1081ff },
            { c = colors.green_off,  hex = 0x141414 },
            { c = colors.yellow,     hex = 0xf5e633 },
            { c = colors.yellow_off, hex = 0x141414 },
            { c = colors.red,        hex = 0xff521a },
            { c = colors.red_off,    hex = 0x141414 }
        },
        -- tritanopia
        {
            { c = colors.green,      hex = 0x40cbd7 },
            { c = colors.green_hc,   hex = 0x40cbd7 },
            { c = colors.green_off,  hex = 0x141414 },
            { c = colors.yellow,     hex = 0xffbc00 },
            { c = colors.yellow_off, hex = 0x141414 },
            { c = colors.red,        hex = 0xff0000 },
            { c = colors.red_off,    hex = 0x141414 }
        },
        -- blue indicators
        {
            { c = colors.green,      hex = 0x1081ff },
            { c = colors.green_hc,   hex = 0x1081ff },
            { c = colors.green_off,  hex = 0x053466 },
        },
        -- standard, black backgrounds
        {
            { c = colors.green_off,  hex = 0x141414 },
            { c = colors.yellow_off, hex = 0x141414 },
            { c = colors.red_off,    hex = 0x141414 }
        },
        -- blue indicators, black backgrounds
        {
            { c = colors.green,      hex = 0x1081ff },
            { c = colors.green_hc,   hex = 0x1081ff },
            { c = colors.green_off,  hex = 0x141414 },
            { c = colors.yellow_off, hex = 0x141414 },
            { c = colors.red_off,    hex = 0x141414 }
        }
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
        { c = colors.red,        hex = 0xf18486 },
        { c = colors.orange,     hex = 0xffb659 },
        { c = colors.yellow,     hex = 0xefe37c },
        { c = colors.green_off,  hex = 0x436b41 },
        { c = colors.green,      hex = 0x7ae175 },
        { c = colors.green_hc,   hex = 0x7ae175 },
        { c = colors.lightBlue,  hex = 0x7dc6f2 },
        { c = colors.blue,       hex = 0x56aae6 },
        { c = colors.yellow_hc,  hex = 0xe9cd68 },
        { c = colors.ivory,      hex = 0x4d4e52 },
        { c = colors.yellow_off, hex = 0x757040 },
        { c = colors.white,      hex = 0xbfbfbf },
        { c = colors.lightGray,  hex = 0x848794 },
        { c = colors.gray,       hex = 0x5c5f68 },
        { c = colors.black,      hex = 0x333333 },
        { c = colors.red_off,    hex = 0x512d2d }
    },

    color_modes = {
        -- standard
        {},
        -- deuteranopia
        {
            { c = colors.green,      hex = 0x65aeff },
            { c = colors.green_hc,   hex = 0x99c9ff },
            { c = colors.green_off,  hex = 0x333333 },
            { c = colors.yellow,     hex = 0xf7c311 },
            { c = colors.yellow_off, hex = 0x333333 },
            { c = colors.red,        hex = 0xf18486 },
            { c = colors.red_off,    hex = 0x333333 }
        },
        -- protanopia
        {
            { c = colors.green,      hex = 0x65aeff },
            { c = colors.green_hc,   hex = 0x99c9ff },
            { c = colors.green_off,  hex = 0x333333 },
            { c = colors.yellow,     hex = 0xf5e633 },
            { c = colors.yellow_off, hex = 0x333333 },
            { c = colors.red,        hex = 0xff8058 },
            { c = colors.red_off,    hex = 0x333333 }
        },
        -- tritanopia
        {
            { c = colors.green,      hex = 0x00ecff },
            { c = colors.green_hc,   hex = 0x00ecff },
            { c = colors.green_off,  hex = 0x333333 },
            { c = colors.yellow,     hex = 0xffbc00 },
            { c = colors.yellow_off, hex = 0x333333 },
            { c = colors.red,        hex = 0xdf4949 },
            { c = colors.red_off,    hex = 0x333333 }
        },
        -- blue indicators
        {
            { c = colors.green,      hex = 0x65aeff },
            { c = colors.green_hc,   hex = 0x99c9ff },
            { c = colors.green_off,  hex = 0x365e8a },
        },
        -- standard, black backgrounds
        {
            { c = colors.green_off,  hex = 0x333333 },
            { c = colors.yellow_off, hex = 0x333333 },
            { c = colors.red_off,    hex = 0x333333 }
        },
        -- blue indicators, black backgrounds
        {
            { c = colors.green,      hex = 0x65aeff },
            { c = colors.green_hc,   hex = 0x99c9ff },
            { c = colors.green_off,  hex = 0x333333 },
            { c = colors.yellow_off, hex = 0x333333 },
            { c = colors.red_off,    hex = 0x333333 }
        }
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

--#endregion

--#region Main UI Color Palettes

---@class ui_palette
themes.smooth_stone = {
    colors = {
        { c = colors.red,       hex = 0xdf4949 },
        { c = colors.orange,    hex = 0xffb659 },
        { c = colors.yellow,    hex = 0xfffc79 },
        { c = colors.lime,      hex = 0x80ff80 },
        { c = colors.green,     hex = 0x4aee8a },
        { c = colors.cyan,      hex = 0x34bac8 },
        { c = colors.lightBlue, hex = 0x6cc0f2 },
        { c = colors.blue,      hex = 0x0096ff },
        { c = colors.purple,    hex = 0xb156ee },
        { c = colors.pink,      hex = 0xf26ba2 },
        { c = colors.magenta,   hex = 0xf9488a },
        { c = colors.white,     hex = 0xf0f0f0 },
        { c = colors.lightGray, hex = 0xcacaca },
        { c = colors.gray,      hex = 0x575757 },
        { c = colors.black,     hex = 0x191919 },
        { c = colors.brown,     hex = 0x7f664c }
    },

    -- color re-mappings for assistive modes
    color_modes = {
        -- standard
        {},
        -- deuteranopia
        {
            { c = colors.blue,   hex = 0x1081ff },
            { c = colors.yellow, hex = 0xf7c311 },
            { c = colors.red,    hex = 0xfb5615 }
        },
        -- protanopia
        {
            { c = colors.blue,   hex = 0x1081ff },
            { c = colors.yellow, hex = 0xf5e633 },
            { c = colors.red,    hex = 0xff521a }
        },
        -- tritanopia
        {
            { c = colors.blue,   hex = 0x40cbd7 },
            { c = colors.yellow, hex = 0xffbc00 },
            { c = colors.red,    hex = 0xff0000 }
        },
        -- blue indicators
        {
            { c = colors.blue,   hex = 0x1081ff },
            { c = colors.yellow, hex = 0xfffc79 },
            { c = colors.red,    hex = 0xdf4949 }
        },
        -- standard, black backgrounds
        {},
        -- blue indicators, black backgrounds
        {
            { c = colors.blue,   hex = 0x1081ff },
            { c = colors.yellow, hex = 0xfffc79 },
            { c = colors.red,    hex = 0xdf4949 }
        }
    }
}

---@type ui_palette
themes.deepslate = {
    colors = {
        { c = colors.red,       hex = 0xeb6a6c },
        { c = colors.orange,    hex = 0xf2b86c },
        { c = colors.yellow,    hex = 0xd9cf81 },
        { c = colors.lime,      hex = 0x80ff80 },
        { c = colors.green,     hex = 0x70e19b },
        { c = colors.cyan,      hex = 0x7ccdd0 },
        { c = colors.lightBlue, hex = 0x99ceef },
        { c = colors.blue,      hex = 0x60bcff },
        { c = colors.purple,    hex = 0xc38aea },
        { c = colors.pink,      hex = 0xff7fb8 },
        { c = colors.magenta,   hex = 0xf980dd },
        { c = colors.white,     hex = 0xd9d9d9 },
        { c = colors.lightGray, hex = 0x949494 },
        { c = colors.gray,      hex = 0x575757 },
        { c = colors.black,     hex = 0x262626 },
        { c = colors.brown,     hex = 0xb18f6a }
    },

    -- color re-mappings for assistive modes
    color_modes = {
        -- standard
        {},
        -- deuteranopia
        {
            { c = colors.blue,   hex = 0x65aeff },
            { c = colors.yellow, hex = 0xf7c311 },
            { c = colors.red,    hex = 0xfb5615 }
        },
        -- protanopia
        {
            { c = colors.blue,   hex = 0x65aeff },
            { c = colors.yellow, hex = 0xf5e633 },
            { c = colors.red,    hex = 0xff8058 }
        },
        -- tritanopia
        {
            { c = colors.blue,   hex = 0x00ecff },
            { c = colors.yellow, hex = 0xffbc00 },
            { c = colors.red,    hex = 0xdf4949 }
        },
        -- blue indicators
        {
            { c = colors.blue,   hex = 0x65aeff },
            { c = colors.yellow, hex = 0xd9cf81 },
            { c = colors.red,    hex = 0xeb6a6c }
        },
        -- standard, black backgrounds
        {},
        -- blue indicators, black backgrounds
        {
            { c = colors.blue,   hex = 0x65aeff },
            { c = colors.yellow, hex = 0xd9cf81 },
            { c = colors.red,    hex = 0xeb6a6c }
        }
    }
}

--#endregion

return themes
