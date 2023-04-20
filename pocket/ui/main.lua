--
-- Pocket GUI Root
--

local coreio        = require("pocket.coreio")

local style         = require("pocket.ui.style")

local conn_waiting  = require("pocket.ui.components.conn_waiting")

local home_page     = require("pocket.ui.components.home_page")
local unit_page     = require("pocket.ui.components.unit_page")
local reactor_page  = require("pocket.ui.components.reactor_page")
local boiler_page   = require("pocket.ui.components.boiler_page")
local turbine_page  = require("pocket.ui.components.turbine_page")

local core          = require("graphics.core")

local DisplayBox    = require("graphics.elements.displaybox")
local Div           = require("graphics.elements.div")
local MultiPane     = require("graphics.elements.multipane")
local TextBox       = require("graphics.elements.textbox")

local Sidebar       = require("graphics.elements.controls.sidebar")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair

-- create new main view
---@param monitor table main viewscreen
local function init(monitor)
    local main = DisplayBox{window=monitor,fg_bg=style.root}

    -- window header message
    TextBox{parent=main,y=1,text="",alignment=TEXT_ALIGN.LEFT,height=1,fg_bg=style.header}

    --
    -- root panel panes (connection screens + main screen)
    --

    local root_pane_div = Div{parent=main,x=1,y=2}

    local conn_sv_wait = conn_waiting(root_pane_div, 6, false)
    local conn_api_wait = conn_waiting(root_pane_div, 6, true)
    local main_pane = Div{parent=main,x=1,y=2}
    local root_panes = { conn_sv_wait, conn_api_wait, main_pane }

    local root_pane = MultiPane{parent=root_pane_div,x=1,y=1,panes=root_panes}

    coreio.core_ps().subscribe("link_state", function (state)
        if state == coreio.LINK_STATE.UNLINKED or state == coreio.LINK_STATE.API_LINK_ONLY then
            root_pane.set_value(1)
        elseif state == coreio.LINK_STATE.SV_LINK_ONLY then
            root_pane.set_value(2)
        else
            root_pane.set_value(3)
        end
    end)

    --
    -- main page panel panes & sidebar
    --

    local page_div = Div{parent=main_pane,x=4,y=1}

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

    local pane_1 = home_page(page_div)
    local pane_2 = unit_page(page_div)
    local pane_3 = reactor_page(page_div)
    local pane_4 = boiler_page(page_div)
    local pane_5 = turbine_page(page_div)
    local panes = { pane_1, pane_2, pane_3, pane_4, pane_5 }

    local page_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}

    Sidebar{parent=main_pane,x=1,y=1,tabs=sidebar_tabs,fg_bg=cpair(colors.white,colors.gray),callback=page_pane.set_value}

    return main
end

return init
