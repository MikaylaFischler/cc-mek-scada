--
-- Pocket GUI Root
--

local iocontrol    = require("pocket.iocontrol")

local diag_apps    = require("pocket.ui.apps.diag_apps")
local dummy_app    = require("pocket.ui.apps.dummy_app")
local sys_apps     = require("pocket.ui.apps.sys_apps")

local conn_waiting = require("pocket.ui.components.conn_waiting")

local home_page    = require("pocket.ui.pages.home_page")
local unit_page    = require("pocket.ui.pages.unit_page")

local style        = require("pocket.ui.style")

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
    TextBox{parent=main,y=1,text="DEV ALPHA APP      S   C   ",alignment=ALIGN.LEFT,height=1,fg_bg=style.header}
    local svr_conn = SignalBar{parent=main,y=1,x=22,compact=true,colors_low_med=cpair(colors.red,colors.yellow),disconnect_color=colors.lightGray,fg_bg=cpair(colors.green,colors.gray)}
    local crd_conn = SignalBar{parent=main,y=1,x=26,compact=true,colors_low_med=cpair(colors.red,colors.yellow),disconnect_color=colors.lightGray,fg_bg=cpair(colors.green,colors.gray)}

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
        { char = "#", color = cpair(colors.black, colors.green) }
    }

    home_page(page_div)
    unit_page(page_div)

    diag_apps(page_div)
    sys_apps(page_div)
    dummy_app(page_div)

    assert(#db.nav.get_containers() == iocontrol.APP_ID.NUM_APPS, "app IDs were not sequential or some apps weren't registered")

    local page_pane = MultiPane{parent=page_div,x=1,y=1,panes=db.nav.get_containers()}
    db.nav.set_pane(page_pane)

    Sidebar{parent=main_pane,x=1,y=1,tabs=sidebar_tabs,fg_bg=cpair(colors.white,colors.gray),callback=db.nav.open_app}

    PushButton{parent=main_pane,x=1,y=19,text="\x1b",min_width=3,fg_bg=cpair(colors.white,colors.gray),active_fg_bg=cpair(colors.gray,colors.black),callback=db.nav.nav_up}

    --#endregion
end

return init
