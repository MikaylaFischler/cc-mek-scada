
local core = require("graphics.core")

local style = {}

local cpair = core.graphics.cpair

-- GLOBAL --

style.root = cpair(colors.black, colors.lightGray)
style.header = cpair(colors.white, colors.gray)

style.colors = {
    {
        c = colors.green,
        hex = 0x7ed788
    },
    {
        c = colors.lightGray,
        hex = 0xcacaca
    }
}

-- MAIN LAYOUT --

style.reactor = {
    -- reactor states
    states = {
        {
            color = cpair(colors.black, colors.yellow),
            text = "DISCONNECTED"
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
            text = "SCRAM!"
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

return style
