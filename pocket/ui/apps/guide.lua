--
-- System Guide
--

local util          = require("scada-common.util")
-- local log        = require("scada-common.log")

local iocontrol     = require("pocket.iocontrol")
local TextField     = require("graphics.elements.form.text_field")

local docs          = require("pocket.ui.docs")
local style         = require("pocket.ui.style")

local guide_section = require("pocket.ui.pages.guide_section")

local core          = require("graphics.core")

local Div           = require("graphics.elements.div")
local ListBox       = require("graphics.elements.listbox")
local MultiPane     = require("graphics.elements.multipane")
local TextBox       = require("graphics.elements.textbox")

local PushButton    = require("graphics.elements.controls.push_button")

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
        { label = " \x14 ", color = core.cpair(colors.black, colors.cyan), callback = function () app.switcher(1) end },
        { label = "__?", color = core.cpair(colors.black, colors.lightGray), callback = function () app.switcher(2) end }
    }

    app.set_sidebar(list)

    local function load()
        local page_div = Div{parent=main,y=2}
        local p_width = page_div.get_width() - 2

        local main_page = app.new_page(nil, 1)
        local search_page = app.new_page(main_page, 2)
        local use_page = app.new_page(main_page, 3)
        local uis_page = app.new_page(main_page, 4)
        local fps_page = app.new_page(main_page, 5)
        local gls_page = app.new_page(main_page, 6)

        local home = Div{parent=page_div,x=2}
        local search = Div{parent=page_div,x=2}
        local use = Div{parent=page_div,x=2,width=p_width}
        local uis = Div{parent=page_div,x=2,width=p_width}
        local fps = Div{parent=page_div,x=2,width=p_width}
        local gls = Div{parent=page_div,x=2}
        local panes = { home, search, use, uis, fps, gls }

        local doc_map = {}
        local search_db = {}

        ---@class _guide_section_constructor_data
        local sect_construct_data = { app, page_div, panes, doc_map, search_db, btn_fg_bg, btn_active }

        TextBox{parent=home,y=1,text="cc-mek-scada Guide",height=1,alignment=ALIGN.CENTER}

        PushButton{parent=home,y=3,text="Search              >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=search_page.nav_to}
        PushButton{parent=home,y=5,text="System Usage        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=use_page.nav_to}
        PushButton{parent=home,text="Operator UIs        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=uis_page.nav_to}
        PushButton{parent=home,text="Front Panels        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fps_page.nav_to}
        PushButton{parent=home,text="Glossary            >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=gls_page.nav_to}

        TextBox{parent=search,y=1,text="Search",height=1,alignment=ALIGN.CENTER}

        local query_field = TextField{parent=search,x=1,y=3,width=18,fg_bg=cpair(colors.white,colors.gray)}

        local func_ref = {}

        PushButton{parent=search,x=20,y=3,text="GO",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()func_ref.run_search()end}

        local search_results = ListBox{parent=search,x=1,y=5,scroll_height=200,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}

        function func_ref.run_search()
            local query = string.lower(query_field.get_value())
            local s_results = { {}, {}, {} }

            search_results.remove_all()

            if string.len(query) < 3 then
                TextBox{parent=search_results,text=util.trinary(string.len(query)==0,"Click 'GO' to search...","Search requires at least 3 characters.")}
                return
            end

            for _, entry in ipairs(search_db) do
                local s_start, _ = string.find(entry[1], query, 1, true)

                if s_start == nil then
                elseif s_start == 1 then
                    -- best match, start of key
                    table.insert(s_results[1], entry)
                elseif string.sub(query, s_start - 1, s_start) == " " then
                    -- start of word, good match
                    table.insert(s_results[2], entry)
                else
                    -- basic match in content
                    table.insert(s_results[3], entry)
                end
            end

            local empty = true

            for tier = 1, 3 do
                for idx = 1, #s_results[tier] do
                    local entry = s_results[tier][idx]
                    TextBox{parent=search_results,text=entry[3].." >",fg_bg=cpair(colors.gray,colors.black)}
                    PushButton{parent=search_results,text=entry[2],alignment=ALIGN.LEFT,fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=entry[4]}

                    empty = false
                end
            end

            if empty then
                TextBox{parent=search_results,text="No results found."}
            end
        end

        TextBox{parent=search_results,text="Click 'GO' to search..."}

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

        local alarms_page = guide_section(sect_construct_data, uis_page, "Alarms", docs.alarms, 100)

        PushButton{parent=uis,y=3,text="Alarms              >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=alarms_page.nav_to}
        PushButton{parent=uis,text="Annunciators        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=annunc_page.nav_to}
        PushButton{parent=uis,text="Pocket UI           >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()
        PushButton{parent=uis,text="Coordinator UI      >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,dis_fg_bg=btn_disable,callback=function()end}.disable()

        TextBox{parent=annunc_div,y=1,text="Annunciators",height=1,alignment=ALIGN.CENTER}
        PushButton{parent=annunc_div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=uis_page.nav_to}

        local unit_gen_page = guide_section(sect_construct_data, annunc_page, "Unit General", docs.annunc.unit.main_section, 200)
        local unit_rps_page = guide_section(sect_construct_data, annunc_page, "Unit RPS", docs.annunc.unit.rps_section, 100)
        local unit_rcs_page = guide_section(sect_construct_data, annunc_page, "Unit RCS", docs.annunc.unit.rcs_section, 100)

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

        local gls_abbv_page = guide_section(sect_construct_data, gls_page, "Abbreviations", docs.glossary.abbvs, 120)
        local gls_term_page = guide_section(sect_construct_data, gls_page, "Terminology", docs.glossary.terms, 100)

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
