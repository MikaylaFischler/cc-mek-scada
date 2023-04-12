--
-- Pocket GUI Root
--

local util          = require("scada-common.util")

local style         = require("pocket.ui.style")

local conn_waiting  = require("pocket.ui.components.conn_waiting")

local core          = require("graphics.core")

local ColorMap      = require("graphics.elements.colormap")
local DisplayBox    = require("graphics.elements.displaybox")
local Div           = require("graphics.elements.div")
local TextBox       = require("graphics.elements.textbox")

local PushButton    = require("graphics.elements.controls.push_button")
local SwitchButton  = require("graphics.elements.controls.switch_button")
local Sidebar       = require("graphics.elements.controls.sidebar")

local DataIndicator = require("graphics.elements.indicators.data")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair

-- create new main view
---@param monitor table main viewscreen
local function init(monitor)
    local main = DisplayBox{window=monitor,fg_bg=style.root}

    -- window header message
    local header = TextBox{parent=main,y=1,text="",alignment=TEXT_ALIGN.LEFT,height=1,fg_bg=style.header}

    -- local api_wait = conn_waiting(main, 8, true)
    -- local sv_wait = conn_waiting(main, 8, false)

    local sidebar_tabs = {
        {
            char = "#",
            color = cpair(colors.black,colors.green)
        },
        {
            char = "U",
            color = cpair(colors.black,colors.yellow)
        },
        {
            char = "R",
            color = cpair(colors.black,colors.cyan)
        },
        {
            char = "B",
            color = cpair(colors.black,colors.lightGray)
        },
        {
            char = "T",
            color = cpair(colors.black,colors.white)
        }
    }

    local sidebar = Sidebar{parent=main,x=1,y=2,tabs=sidebar_tabs,fg_bg=cpair(colors.white,colors.gray),callback=function()end}

    return main
end

return init
