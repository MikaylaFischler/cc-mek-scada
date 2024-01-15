--
-- Pocket GUI Root
--

local iocontrol    = require("pocket.iocontrol")

local style        = require("pocket.ui.style")

local conn_waiting = require("pocket.ui.components.conn_waiting")

local boiler_page  = require("pocket.ui.pages.boiler_page")
local home_page    = require("pocket.ui.pages.home_page")
local reactor_page = require("pocket.ui.pages.reactor_page")
local turbine_page = require("pocket.ui.pages.turbine_page")
local unit_page    = require("pocket.ui.pages.unit_page")

local core         = require("graphics.core")

local Div          = require("graphics.elements.div")
local MultiPane    = require("graphics.elements.multipane")
local TextBox      = require("graphics.elements.textbox")

local PushButton   = require("graphics.elements.controls.push_button")
local Sidebar      = require("graphics.elements.controls.sidebar")

local SignalBar    = require("graphics.elements.indicators.signal")

local LINK_STATE = iocontrol.LINK_STATE

local ALIGN = core.ALIGN

local cpair = core.cpair

-- create new main view
---@param main graphics_element main displaybox
local function init(main)
    local db = iocontrol.get_db()

    -- window header message
    TextBox{parent=main,y=1,text="DEV ALPHA APP     S   C   ",alignment=ALIGN.LEFT,height=1,fg_bg=style.header}
    local svr_conn = SignalBar{parent=main,y=1,x=20,colors_low_med=cpair(colors.red,colors.yellow),disconnect_color=colors.lightGray,fg_bg=cpair(colors.white,colors.gray)}
    local crd_conn = SignalBar{parent=main,y=1,x=24,colors_low_med=cpair(colors.red,colors.yellow),disconnect_color=colors.lightGray,fg_bg=cpair(colors.white,colors.gray)}

    db.ps.subscribe("svr_conn_quality", svr_conn.set_value)
    db.ps.subscribe("crd_conn_quality", crd_conn.set_value)

    --#region root panel panes (connection screens + main screen)

    local root_pane_div = Div{parent=main,x=1,y=2}

    local conn_sv_wait = conn_waiting(root_pane_div, 6, false)
    local conn_api_wait = conn_waiting(root_pane_div, 6, true)
    local main_pane = Div{parent=main,x=1,y=2}

    local root_pane = MultiPane{parent=root_pane_div,x=1,y=1,panes={conn_sv_wait,conn_api_wait,main_pane}}

    root_pane.register(db.ps, "link_state", function (state)
        if state == LINK_STATE.UNLINKED or state == LINK_STATE.API_LINK_ONLY then
            root_pane.set_value(1)
        elseif state == LINK_STATE.SV_LINK_ONLY then
            root_pane.set_value(2)
        else
            root_pane.set_value(3)
        end
    end)

    --#endregion

    --#region main page panel panes & sidebar

    local page_div = Div{parent=main_pane,x=4,y=1}

    local sidebar_tabs = {
        { char = "#", color = cpair(colors.black,colors.green) },
        { char = "U", color = cpair(colors.black,colors.yellow) },
        { char = "R", color = cpair(colors.black,colors.cyan) },
        { char = "B", color = cpair(colors.black,colors.lightGray) },
        { char = "T", color = cpair(colors.black,colors.white) }
    }

    local page_pane = MultiPane{parent=page_div,x=1,y=1,panes={home_page(page_div),unit_page(page_div),reactor_page(page_div),boiler_page(page_div),turbine_page(page_div)}}

    local base = iocontrol.init_nav(page_pane)

    Sidebar{parent=main_pane,x=1,y=1,tabs=sidebar_tabs,fg_bg=cpair(colors.white,colors.gray),callback=base.switcher}

    PushButton{parent=main_pane,x=1,y=19,text="\x1b",min_width=3,fg_bg=cpair(colors.white,colors.gray),active_fg_bg=cpair(colors.gray,colors.black),callback=db.nav.nav_up}

    --#endregion
end

return init
