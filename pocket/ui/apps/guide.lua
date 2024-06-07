--
-- System Guide
--

-- local util       = require("scada-common.util")
-- local log        = require("scada-common.log")

local iocontrol  = require("pocket.iocontrol")

local docs       = require("pocket.ui.docs")
local style      = require("pocket.ui.style")

local guide_section = require("pocket.ui.pages.guide_section")

local core       = require("graphics.core")

local Div        = require("graphics.elements.div")
local ListBox    = require("graphics.elements.listbox")
local MultiPane  = require("graphics.elements.multipane")
local TextBox    = require("graphics.elements.textbox")

local PushButton = require("graphics.elements.controls.push_button")

local ALIGN = core.ALIGN
local cpair = core.cpair

local label        = style.label
-- local lu_col       = style.label_unit_pair
local text_fg      = style.text_fg

-- new system guide view
---@param root graphics_element parent
local function new_view(root)
    local db = iocontrol.get_db()

    local main = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(iocontrol.APP_ID.GUIDE, main)

    TextBox{parent=main,y=2,text="Guide",height=1,alignment=ALIGN.CENTER}
    TextBox{parent=main,y=4,text="Loading...",height=1,alignment=ALIGN.CENTER}

    local btn_fg_bg = cpair(colors.cyan, colors.black)
    local btn_active = cpair(colors.white, colors.black)
    local btn_disable = cpair(colors.gray, colors.black)

    local list = {
        { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = function () db.nav.open_app(iocontrol.APP_ID.ROOT) end },
        { label = "Use", color = core.cpair(colors.black, colors.purple), callback = function () app.switcher(2) end },
        { label = "UIs", color = core.cpair(colors.black, colors.blue), callback = function () app.switcher(3) end },
        { label = "FPs", color = core.cpair(colors.black, colors.lightGray), callback = function () app.switcher(4) end }
    }

    app.set_sidebar(list)

    local function load()
        local page_div = Div{parent=main,y=2}
        local p_width = page_div.get_width() - 2

        local main_page = app.new_page(nil, 1)
        local use_page = app.new_page(main_page, 2)
        local uis_page = app.new_page(main_page, 3)
        local fps_page = app.new_page(main_page, 4)
        local gls_page = app.new_page(main_page, 5)

        local home = Div{parent=page_div,x=2,width=p_width}
        local use = Div{parent=page_div,x=2,width=p_width}
        local uis = Div{parent=page_div,x=2,width=p_width}
        local fps = Div{parent=page_div,x=2,width=p_width}
        local gls = Div{parent=page_div,x=2}
        local panes = { home, use, uis, fps, gls }

        local doc_map = {}
        local search_map = {}

        ---@class _guide_section_constructor_data
        local sect_construct_data = { app, page_div, panes, doc_map, search_map, btn_fg_bg, btn_active }

        TextBox{parent=home,y=1,text="cc-mek-scada Guide",height=1,alignment=ALIGN.CENTER}

        PushButton{parent=home,y=3,text="System Usage        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=use_page.nav_to}
        PushButton{parent=home,text="Operator UIs        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=uis_page.nav_to}
        PushButton{parent=home,text="Front Panels        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fps_page.nav_to}
        PushButton{parent=home,text="Glossary            >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=gls_page.nav_to}

        TextBox{parent=use,y=1,text="System Usage",height=1,alignment=ALIGN.CENTER}
        PushButton{parent=use,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        PushButton{parent=use,y=3,text="Configuring Devices >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()
        PushButton{parent=use,text="Connecting Devices  >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()
        PushButton{parent=use,text="Manual Control      >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()
        PushButton{parent=use,text="Automatic Control   >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()
        PushButton{parent=use,text="Waste Control       >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()

        TextBox{parent=uis,y=1,text="Operator UIs",height=1,alignment=ALIGN.CENTER}
        PushButton{parent=uis,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        local annunc_page = app.new_page(uis_page, #panes + 1)
        local annunc_div = Div{parent=page_div,x=2}
        table.insert(panes, annunc_div)

        local alarms_page = guide_section(sect_construct_data, uis_page, "Alarms", docs.alarms)

        PushButton{parent=uis,y=3,text="Alarms              >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=alarms_page.nav_to}
        PushButton{parent=uis,text="Annunciators        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=annunc_page.nav_to}
        PushButton{parent=uis,text="Pocket UI           >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()
        PushButton{parent=uis,text="Coordinator UI      >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()

        TextBox{parent=annunc_div,y=1,text="Annunciators",height=1,alignment=ALIGN.CENTER}
        PushButton{parent=annunc_div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=uis_page.nav_to}

        local unit_gen_page = guide_section(sect_construct_data, annunc_page, "Unit General", docs.annunc.unit.main_section)
        local unit_rps_page = guide_section(sect_construct_data, annunc_page, "Unit RPS", docs.annunc.unit.rps_section)
        local unit_rcs_page = guide_section(sect_construct_data, annunc_page, "Unit RCS", docs.annunc.unit.rcs_section)

        PushButton{parent=annunc_div,y=3,text="Unit General        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=unit_gen_page.nav_to}
        PushButton{parent=annunc_div,text="Unit RPS            >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=unit_rps_page.nav_to}
        PushButton{parent=annunc_div,text="Unit RCS            >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=unit_rcs_page.nav_to}
        PushButton{parent=annunc_div,text="Facility General    >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()
        PushButton{parent=annunc_div,text="Waste & Valves      >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()

        TextBox{parent=fps,y=1,text="Front Panels",height=1,alignment=ALIGN.CENTER}
        PushButton{parent=fps,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        PushButton{parent=fps,y=3,text="Common Items        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()
        PushButton{parent=fps,text="Reactor PLC         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()
        PushButton{parent=fps,text="RTU Gateway         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()
        PushButton{parent=fps,text="Supervisor          >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()
        PushButton{parent=fps,text="Coordinator         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()

        TextBox{parent=gls,y=1,text="Glossary",height=1,alignment=ALIGN.CENTER}
        PushButton{parent=gls,x=3,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        local gls_abbv_page = guide_section(sect_construct_data, gls_page, "Abbreviations", docs.glossary.abbvs)
        local gls_term_page = guide_section(sect_construct_data, gls_page, "Terminology", docs.glossary.terms)

        PushButton{parent=gls,y=3,text="Abbreviations       >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=gls_abbv_page.nav_to}
        PushButton{parent=gls,text="Terminology         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=gls_term_page.nav_to}

        -- setup multipane
        local u_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(u_pane)

        -- link help resources
        db.nav.link_help(doc_map)
    end

    app.set_on_load(load)

    return main
end

return new_view
