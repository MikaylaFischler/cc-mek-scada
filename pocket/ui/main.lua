--
-- Pocket GUI Root
--

local iocontrol    = require("pocket.iocontrol")

local style        = require("pocket.ui.style")

local conn_waiting = require("pocket.ui.components.conn_waiting")

local boiler_page  = require("pocket.ui.pages.boiler_page")
local diag_page    = require("pocket.ui.pages.diag_page")
local home_page    = require("pocket.ui.pages.home_page")
local reactor_page = require("pocket.ui.pages.reactor_page")
local turbine_page = require("pocket.ui.pages.turbine_page")
local unit_page    = require("pocket.ui.pages.unit_page")

local core         = require("graphics.core")

local Div          = require("graphics.elements.div")
local MultiPane    = require("graphics.elements.multipane")
local TextBox      = require("graphics.elements.textbox")

local Sidebar      = require("graphics.elements.controls.sidebar")

local LINK_STATE = iocontrol.LINK_STATE
local NAV_PAGE   = iocontrol.NAV_PAGE

local TEXT_ALIGN = core.TEXT_ALIGN

local cpair = core.cpair

-- create new main view
---@param main graphics_element main displaybox
local function init(main)
    local nav = iocontrol.get_db().nav
    local ps  = iocontrol.get_db().ps

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

    root_pane.register(ps, "link_state", function (state)
        if state == LINK_STATE.UNLINKED or state == LINK_STATE.API_LINK_ONLY then
            root_pane.set_value(1)
        elseif state == LINK_STATE.SV_LINK_ONLY then
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
        },
        {
            char = "D",
            color = cpair(colors.black,colors.orange)
        }
    }

    local panes = { home_page(page_div), unit_page(page_div), reactor_page(page_div),  boiler_page(page_div), turbine_page(page_div), diag_page(page_div) }

    local page_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}

    local function navigate_sidebar(page)
        if page == 1 then
            nav.page = nav.sub_pages[NAV_PAGE.HOME]
        elseif page == 2 then
            nav.page = nav.sub_pages[NAV_PAGE.UNITS]
        elseif page == 3 then
            nav.page = nav.sub_pages[NAV_PAGE.REACTORS]
        elseif page == 4 then
            nav.page = nav.sub_pages[NAV_PAGE.BOILERS]
        elseif page == 5 then
            nav.page = nav.sub_pages[NAV_PAGE.TURBINES]
        elseif page == 6 then
            nav.page = nav.sub_pages[NAV_PAGE.DIAG]
        end

        page_pane.set_value(page)
    end

    Sidebar{parent=main_pane,x=1,y=1,tabs=sidebar_tabs,fg_bg=cpair(colors.white,colors.gray),callback=navigate_sidebar}
end

return init
