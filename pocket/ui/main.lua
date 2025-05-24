--
-- Pocket GUI Root
--

local util        = require("scada-common.util")

local iocontrol   = require("pocket.iocontrol")
local pocket      = require("pocket.pocket")

local control_app = require("pocket.ui.apps.control")
local diag_apps   = require("pocket.ui.apps.diag_apps")
local dummy_app   = require("pocket.ui.apps.dummy_app")
local facil_app   = require("pocket.ui.apps.facility")
local guide_app   = require("pocket.ui.apps.guide")
local loader_app  = require("pocket.ui.apps.loader")
local process_app = require("pocket.ui.apps.process")
local rad_app     = require("pocket.ui.apps.radiation")
local sys_apps    = require("pocket.ui.apps.sys_apps")
local unit_app    = require("pocket.ui.apps.unit")
local waste_app   = require("pocket.ui.apps.waste")

local home_page   = require("pocket.ui.pages.home_page")

local style       = require("pocket.ui.style")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local WaitingAnim = require("graphics.elements.animations.Waiting")

local PushButton  = require("graphics.elements.controls.PushButton")
local Sidebar     = require("graphics.elements.controls.Sidebar")

local SignalBar   = require("graphics.elements.indicators.SignalBar")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

-- create new main view
---@param main DisplayBox main displaybox
local function init(main)
    local db = iocontrol.get_db()

    -- window header message and connection status
    TextBox{parent=main,y=1,text="                   S   C  ",fg_bg=style.header}
    local svr_conn = SignalBar{parent=main,y=1,x=22,compact=true,colors_low_med=cpair(colors.red,colors.yellow),disconnect_color=colors.lightGray,fg_bg=cpair(colors.green,colors.gray)}
    local crd_conn = SignalBar{parent=main,y=1,x=26,compact=true,colors_low_med=cpair(colors.red,colors.yellow),disconnect_color=colors.lightGray,fg_bg=cpair(colors.green,colors.gray)}

    db.ps.subscribe("svr_conn_quality", svr_conn.set_value)
    db.ps.subscribe("crd_conn_quality", crd_conn.set_value)

    local start_pane = Div{parent=main,x=1,y=2}
    local main_pane = Div{parent=main,x=1,y=2}

    WaitingAnim{parent=start_pane,x=12,y=7,fg_bg=cpair(colors.lightBlue,style.root.bkg)}
    TextBox{parent=start_pane,y=11,text="starting up...",alignment=ALIGN.CENTER,fg_bg=cpair(colors.lightGray,style.root.bkg)}

    local root_pane = MultiPane{parent=main,x=1,y=2,panes={start_pane,main_pane}}

    local page_div = Div{parent=main_pane,x=4,y=1}

    -- create all the apps & pages
    home_page(page_div)
    unit_app(page_div)
    facil_app(page_div)
    control_app(page_div)
    process_app(page_div)
    waste_app(page_div)
    guide_app(page_div)
    rad_app(page_div)
    loader_app(page_div)
    sys_apps(page_div)
    diag_apps(page_div)
    dummy_app(page_div)

    -- verify all apps were created
    assert(util.table_len(db.nav.get_containers()) == APP_ID.NUM_APPS, "app IDs were not sequential or some apps weren't registered")

    db.nav.set_pane(MultiPane{parent=page_div,x=1,y=1,panes=db.nav.get_containers()})
    db.nav.set_sidebar(Sidebar{parent=main_pane,x=1,y=1,height=18,fg_bg=cpair(colors.white,colors.gray)})

    PushButton{parent=main_pane,x=1,y=19,text="\x1b",min_width=3,fg_bg=cpair(colors.white,colors.gray),active_fg_bg=cpair(colors.gray,colors.black),callback=db.nav.nav_up}

    db.nav.go_home()

    -- done with initial render, lets go!
    root_pane.set_value(2)
end

return init
