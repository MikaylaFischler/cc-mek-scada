--
-- Graphics Style Options
--

local util   = require("scada-common.util")

local core   = require("graphics.core")

local pocket = require("pocket.pocket")

local style = {}

local cpair = core.cpair

local config = pocket.config

-- GLOBAL --

style.root            = cpair(colors.white, colors.black)
style.header          = cpair(colors.white, colors.gray)
style.text_fg         = cpair(colors.white, colors._INHERIT)

style.label           = cpair(colors.lightGray, colors.black)
style.label_unit_pair = cpair(colors.lightGray, colors.lightGray)

style.field           = cpair(colors.white, colors.gray)
style.field_disable   = cpair(colors.gray, colors.lightGray)
style.btn_disable     = cpair(colors.gray, colors.black)
style.hzd_fg_bg       = cpair(colors.white, colors.gray)
style.hzd_dis_colors  = cpair(colors.white, colors.lightGray)

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

local states = {}

states.basic_states = {
    { color = cpair(colors.black, colors.lightGray), symbol = "\x07" },
    { color = cpair(colors.black, colors.red), symbol = "-" },
    { color = cpair(colors.black, colors.yellow), symbol = "\x1e" },
    { color = cpair(colors.black, colors.green), symbol = "+" }
}

states.mode_states = {
    { color = cpair(colors.black, colors.lightGray), symbol = "\x07" },
    { color = cpair(colors.black, colors.red), symbol = "-" },
    { color = cpair(colors.black, colors.green), symbol = "+" },
    { color = cpair(colors.black, colors.purple), symbol = "A" }
}

states.emc_ind_s = {
    { color = cpair(colors.black, colors.gray), symbol = "-" },
    { color = cpair(colors.black, colors.white), symbol = "\x07" },
    { color = cpair(colors.black, colors.green), symbol = "+" }
}

states.tri_ind_s = {
    { color = cpair(colors.black, colors.lightGray), symbol = "+" },
    { color = cpair(colors.black, colors.yellow), symbol = "\x1e" },
    { color = cpair(colors.black, colors.red), symbol = "-" }
}

states.red_ind_s = {
    { color = cpair(colors.black, colors.lightGray), symbol = "+" },
    { color = cpair(colors.black, colors.red), symbol = "-" }
}

states.yel_ind_s = {
    { color = cpair(colors.black, colors.lightGray), symbol = "+" },
    { color = cpair(colors.black, colors.yellow), symbol = "-" }
}

states.grn_ind_s = {
    { color = cpair(colors.black, colors.lightGray), symbol = "\x07" },
    { color = cpair(colors.black, colors.green), symbol = "+" }
}

states.wht_ind_s = {
    { color = cpair(colors.black, colors.lightGray), symbol = "\x07" },
    { color = cpair(colors.black, colors.white), symbol = "+" }
}

style.icon_states = states

-- MAIN LAYOUT --

style.reactor = {
    -- reactor states<br>
    ---@see REACTOR_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "PLC  FAULT" },
        { color = cpair(colors.white, colors.gray),   text = "DISABLED" },
        { color = cpair(colors.black, colors.green),  text = "ACTIVE" },
        { color = cpair(colors.black, colors.red),    text = "SCRAMMED" },
        { color = cpair(colors.black, colors.red),    text = "FORCE DSBL" }
    }
}

style.boiler = {
    -- boiler states<br>
    ---@see BOILER_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "RTU  FAULT" },
        { color = cpair(colors.white, colors.gray),   text = "IDLE" },
        { color = cpair(colors.black, colors.green),  text = "ACTIVE" }
    }
}

style.turbine = {
    -- turbine states<br>
    ---@see TURBINE_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "RTU  FAULT" },
        { color = cpair(colors.white, colors.gray),   text = "IDLE" },
        { color = cpair(colors.black, colors.green),  text = "ACTIVE" },
        { color = cpair(colors.black, colors.red),    text = "TRIP" }
    }
}

style.dtank = {
    -- dynamic tank states<br>
    ---@see TANK_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "RTU  FAULT" },
        { color = cpair(colors.black, colors.green),  text = "ONLINE" },
        { color = cpair(colors.black, colors.yellow), text = "LOW FILL" },
        { color = cpair(colors.black, colors.green),  text = "FILLED" }
    }
}

style.imatrix = {
    -- induction matrix states<br>
    ---@see IMATRIX_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "RTU  FAULT" },
        { color = cpair(colors.black, colors.green),  text = "ONLINE" },
        { color = cpair(colors.black, colors.yellow), text = "LOW CHARGE" },
        { color = cpair(colors.black, colors.yellow), text = "HIGH  CHARGE" }
    }
}

style.sps = {
    -- SPS states<br>
    ---@see SPS_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "RTU  FAULT" },
        { color = cpair(colors.white, colors.gray),   text = "IDLE" },
        { color = cpair(colors.black, colors.green),  text = "ACTIVE" }
    }
}

-- get waste styling, which depends on the configuration
---@return { states: { color: color, text: string }, states_abbrv: { color: color, text: string }, options: string[], unit_opts: string[] }
function style.get_waste()
    local pu_color = util.trinary(config.GreenPuPellet, colors.green, colors.cyan)
    local po_color = util.trinary(config.GreenPuPellet, colors.cyan, colors.green)

    return {
        -- auto waste processing states
        states = {
            { color = cpair(colors.black, pu_color),      text = "PLUTONIUM" },
            { color = cpair(colors.black, po_color),      text = "POLONIUM" },
            { color = cpair(colors.black, colors.purple), text = "ANTI MATTER" }
        },
        states_abbrv = {
            { color = cpair(colors.black, pu_color),      text = "Pu" },
            { color = cpair(colors.black, po_color),      text = "Po" },
            { color = cpair(colors.black, colors.purple), text = "AM" }
        },
        -- process radio button options
        options = { "Plutonium", "Polonium", "Antimatter" },
        -- unit waste selection
        unit_opts = { "Auto", "Plutonium", "Polonium", "Antimatter" }
    }
end

return style
