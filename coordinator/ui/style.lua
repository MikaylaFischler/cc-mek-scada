--
-- Graphics Style Options
--

local core = require("graphics.core")

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

style.root = cpair(colors.black, colors.lightGray)
style.header = cpair(colors.white, colors.gray)
style.label = cpair(colors.gray, colors.lightGray)

style.colors = {
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
    -- { c = colors.white,     hex = 0xf0f0f0 },
    { c = colors.lightGray, hex = 0xcacaca },
    { c = colors.gray,      hex = 0x575757 },
    -- { c = colors.black,     hex = 0x191919 },
    -- { c = colors.brown,     hex = 0x7f664c }
}

-- COMMON COLOR PAIRS --

style.bw_fg_bg = cpair(colors.black, colors.white)
style.text_colors = cpair(colors.black, colors.lightGray)
style.lu_colors = cpair(colors.gray, colors.gray)
style.hzd_fg_bg  = cpair(colors.white, colors.gray)
style.dis_colors = cpair(colors.white, colors.lightGray)

style.ind_grn = cpair(colors.green, colors.gray)
style.ind_yel = cpair(colors.yellow, colors.gray)
style.ind_red = cpair(colors.red, colors.gray)
style.ind_wht = cpair(colors.white, colors.gray)

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
            color = cpair(colors.black, colors.gray),
            text = "IDLE"
        },
        {
            color = cpair(colors.black, colors.blue),
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
        }
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
