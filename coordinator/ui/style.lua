
local core = require("graphics.core")

local style = {}

local cpair = core.graphics.cpair

-- MAIN LAYOUT --

style.root = cpair(colors.black, colors.lightGray)
style.header = cpair(colors.white, colors.gray)

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

return style
