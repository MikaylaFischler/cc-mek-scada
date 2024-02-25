--
-- Graphics Style Options
--

local core = require("graphics.core")

---@class crd_style
local style = {}

local cpair = core.cpair

-- GLOBAL --

-- add color mappings for front panel
colors.ivory = colors.pink
colors.yellow_hc = colors.purple
colors.red_off = colors.brown
colors.yellow_off = colors.magenta
colors.green_off = colors.lime

-- front panel styling

style.fp = {}

style.fp.root = cpair(colors.black, colors.ivory)
style.fp.header = cpair(colors.black, colors.lightGray)

style.fp.colors = {
    { c = colors.red,       hex = 0xdf4949 },   -- RED ON
    { c = colors.orange,    hex = 0xffb659 },
    { c = colors.yellow,    hex = 0xf9fb53 },   -- YELLOW ON
    { c = colors.lime,      hex = 0x16665a },   -- GREEN OFF
    { c = colors.green,     hex = 0x6be551 },   -- GREEN ON
    { c = colors.cyan,      hex = 0x34bac8 },
    { c = colors.lightBlue, hex = 0x6cc0f2 },
    { c = colors.blue,      hex = 0x0096ff },
    { c = colors.purple,    hex = 0xb156ee },   -- YELLOW HIGH CONTRAST
    { c = colors.pink,      hex = 0xdcd9ca },   -- IVORY
    { c = colors.magenta,   hex = 0x85862c },   -- YELLOW OFF
    -- { c = colors.white,     hex = 0xdcd9ca },
    { c = colors.lightGray, hex = 0xb1b8b3 },
    { c = colors.gray,      hex = 0x575757 },
    -- { c = colors.black,     hex = 0x191919 },
    { c = colors.brown,     hex = 0x672223 }    -- RED OFF
}

-- main GUI styling

---@class theme
local deepslate = {
    text = colors.white,
    text_inv = colors.black,
    label = colors.lightGray,
    label_dark = colors.gray,
    disabled = colors.gray,
    bg = colors.black,
    accent_light = colors.gray,
    accent_dark = colors.lightGray,

    fuel_color = colors.lightGray,

    header = cpair(colors.white, colors.gray),

    text_fg = cpair(colors.white, colors._INHERIT),
    label_fg = cpair(colors.lightGray, colors._INHERIT),
    disabled_fg = cpair(colors.gray, colors._INHERIT),

    highlight_box = cpair(colors.white, colors.gray),
    highlight_box_bright = cpair(colors.black, colors.lightGray),
    field_box = cpair(colors.white, colors.gray),

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
    }
}

---@type theme
local smooth_stone = {
    text = colors.black,
    text_inv = colors.white,
    label = colors.gray,
    label_dark = colors.gray,
    disabled = colors.lightGray,
    bg = colors.lightGray,
    accent_light = colors.white,
    accent_dark = colors.gray,

    fuel_color = colors.black,

    header = cpair(colors.white, colors.gray),

    text_fg = cpair(colors.black, colors._INHERIT),
    label_fg = cpair(colors.gray, colors._INHERIT),
    disabled_fg = cpair(colors.lightGray, colors._INHERIT),

    highlight_box = cpair(colors.black, colors.white),
    highlight_box_bright = cpair(colors.black, colors.white),
    field_box = cpair(colors.black, colors.white),

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
    }
}

style.theme = deepslate
-- style.theme = smooth_stone

style.root = cpair(style.theme.text, style.theme.bg)
style.label = cpair(style.theme.label, style.theme.bg)

-- high contrast text (also tags)
style.hc_text = cpair(style.theme.text, style.theme.text_inv)
-- text on default background
style.text_colors = cpair(style.theme.text, style.theme.bg)
-- label & unit colors
style.lu_colors = cpair(style.theme.label, style.theme.label)
-- label & unit colors (darker if set)
style.lu_colors_dark = cpair(style.theme.label_dark, style.theme.label_dark)

-- COMMON COLOR PAIRS --

style.wh_gray = cpair(colors.white, colors.gray)

style.bw_fg_bg = cpair(colors.black, colors.white)

style.hzd_fg_bg  = style.wh_gray
style.dis_colors = cpair(colors.white, colors.lightGray)

style.lg_gray = cpair(colors.lightGray, colors.gray)
style.lg_white = cpair(colors.lightGray, colors.white)
style.gray_white = cpair(colors.gray, colors.white)

style.ind_grn = cpair(colors.green, colors.gray)
style.ind_yel = cpair(colors.yellow, colors.gray)
style.ind_red = cpair(colors.red, colors.gray)
style.ind_wht = style.wh_gray

style.fp_text = cpair(colors.black, colors.ivory)
style.fp_label = cpair(colors.lightGray, colors.ivory)
style.led_grn = cpair(colors.green, colors.green_off)

-- UI COMPONENTS --

style.reactor = {
    -- reactor states
    states = {
        {
            color = cpair(colors.black, colors.yellow),
            text = "PLC OFF-LINE"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "NOT FORMED"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "PLC  FAULT"
        },
        {
            color = cpair(colors.white, colors.gray),
            text = "DISABLED"
        },
        {
            color = cpair(colors.black, colors.green),
            text = "ACTIVE"
        },
        {
            color = cpair(colors.black, colors.red),
            text = "SCRAMMED"
        },
        {
            color = cpair(colors.black, colors.red),
            text = "FORCE DISABLED"
        }
    }
}

style.boiler = {
    -- boiler states
    states = {
        {
            color = cpair(colors.black, colors.yellow),
            text = "OFF-LINE"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "NOT FORMED"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "RTU  FAULT"
        },
        {
            color = cpair(colors.white, colors.gray),
            text = "IDLE"
        },
        {
            color = cpair(colors.black, colors.green),
            text = "ACTIVE"
        }
    }
}

style.turbine = {
    -- turbine states
    states = {
        {
            color = cpair(colors.black, colors.yellow),
            text = "OFF-LINE"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "NOT FORMED"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "RTU  FAULT"
        },
        {
            color = cpair(colors.white, colors.gray),
            text = "IDLE"
        },
        {
            color = cpair(colors.black, colors.green),
            text = "ACTIVE"
        },
        {
            color = cpair(colors.black, colors.red),
            text = "TRIP"
        }
    }
}

style.imatrix = {
    -- induction matrix states
    states = {
        {
            color = cpair(colors.black, colors.yellow),
            text = "OFF-LINE"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "NOT FORMED"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "RTU  FAULT"
        },
        {
            color = cpair(colors.black, colors.green),
            text = "ONLINE"
        },
        {
            color = cpair(colors.black, colors.yellow),
            text = "LOW CHARGE"
        },
        {
            color = cpair(colors.black, colors.yellow),
            text = "HIGH  CHARGE"
        }
    }
}

style.sps = {
    -- SPS states
    states = {
        {
            color = cpair(colors.black, colors.yellow),
            text = "OFF-LINE"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "NOT FORMED"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "RTU  FAULT"
        },
        {
            color = cpair(colors.white, colors.gray),
            text = "IDLE"
        },
        {
            color = cpair(colors.black, colors.green),
            text = "ACTIVE"
        }
    }
}

style.dtank = {
    -- dynamic tank states
    states = {
        {
            color = cpair(colors.black, colors.yellow),
            text = "OFF-LINE"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "NOT FORMED"
        },
        {
            color = cpair(colors.black, colors.orange),
            text = "RTU  FAULT"
        },
        {
            color = cpair(colors.black, colors.green),
            text = "ONLINE"
        },
        {
            color = cpair(colors.black, colors.yellow),
            text = "LOW FILL"
        },
        {
            color = cpair(colors.black, colors.green),
            text = "FILLED"
        },
    }
}

style.waste = {
    -- auto waste processing states
    states = {
        {
            color = cpair(colors.black, colors.green),
            text = "PLUTONIUM"
        },
        {
            color = cpair(colors.black, colors.cyan),
            text = "POLONIUM"
        },
        {
            color = cpair(colors.black, colors.purple),
            text = "ANTI MATTER"
        }
    },
    states_abbrv = {
        {
            color = cpair(colors.black, colors.green),
            text = "Pu"
        },
        {
            color = cpair(colors.black, colors.cyan),
            text = "Po"
        },
        {
            color = cpair(colors.black, colors.purple),
            text = "AM"
        }
    },
    -- process radio button options
    options = { "Plutonium", "Polonium", "Antimatter" },
    -- unit waste selection
    unit_opts = {
        {
            text = "Auto",
            fg_bg = cpair(colors.black, colors.lightGray),
            active_fg_bg = cpair(colors.white, colors.gray)
        },
        {
            text = "Pu",
            fg_bg = cpair(colors.black, colors.lightGray),
            active_fg_bg = cpair(colors.black, colors.green)
        },
        {
            text = "Po",
            fg_bg = cpair(colors.black, colors.lightGray),
            active_fg_bg = cpair(colors.black, colors.cyan)
        },
        {
            text = "AM",
            fg_bg = cpair(colors.black, colors.lightGray),
            active_fg_bg = cpair(colors.black, colors.purple)
        }
    }
}

return style
