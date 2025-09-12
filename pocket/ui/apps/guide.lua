--
-- System Guide
--

local util          = require("scada-common.util")
local log           = require("scada-common.log")

local iocontrol     = require("pocket.iocontrol")
local pocket        = require("pocket.pocket")

local docs          = require("pocket.ui.docs")
-- local style         = require("pocket.ui.style")

local guide_section = require("pocket.ui.pages.guide_section")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local ListBox       = require("graphics.elements.ListBox")
local MultiPane     = require("graphics.elements.MultiPane")
local TextBox       = require("graphics.elements.TextBox")

local WaitingAnim   = require("graphics.elements.animations.Waiting")

local PushButton    = require("graphics.elements.controls.PushButton")

local TextField     = require("graphics.elements.form.TextField")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

-- local label   = style.label
-- local lu_col  = style.label_unit_pair
-- local text_fg = style.text_fg

-- new system guide view
---@param root Container parent
local function new_view(root)
    local db = iocontrol.get_db()

    local frame = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(APP_ID.GUIDE, frame)

    local load_div = Div{parent=frame,x=1,y=1}
    local main = Div{parent=frame,x=1,y=1}

    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.cyan,colors._INHERIT)}
    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    local load_text_1 = TextBox{parent=load_div,y=14,text="",alignment=ALIGN.CENTER,fg_bg=cpair(colors.lightGray,colors._INHERIT)}
    local load_text_2 = TextBox{parent=load_div,y=15,text="",alignment=ALIGN.CENTER,fg_bg=cpair(colors.lightGray,colors._INHERIT)}

    -- give more detailed information so the user doesn't give up
    local function load_text(a, b)
        if a then load_text_1.set_value(a) end
        load_text_2.set_value(b or "")
    end

    local load_pane = MultiPane{parent=main,x=1,y=1,panes={load_div,main}}

    local btn_fg_bg = cpair(colors.cyan, colors.black)
    local btn_active = cpair(colors.white, colors.black)

    app.set_sidebar({{ label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home }})

    local page_div = nil ---@type Div|nil

    -- load the app (create the elements)
    local function load()
        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = " \x14 ", color = core.cpair(colors.black, colors.cyan), callback = function () app.switcher(1) end },
            { label = "__?", color = core.cpair(colors.black, colors.lightGray), callback = function () app.switcher(2) end }
        }

        app.set_sidebar(list)

        page_div = Div{parent=main,y=2}
        local p_width = page_div.get_width() - 1

        local main_page = app.new_page(nil, 1)
        local search_page = app.new_page(main_page, 2)
        local use_page = app.new_page(main_page, 3)
        local uis_page = app.new_page(main_page, 4)
        local fps_page = app.new_page(main_page, 5)
        local gls_page = app.new_page(main_page, 6)
        local lnk_page = app.new_page(main_page, 7)

        local home = Div{parent=page_div,x=2}
        local search = Div{parent=page_div,x=2}
        local use = Div{parent=page_div,x=2,width=p_width}
        local uis = Div{parent=page_div,x=2,width=p_width}
        local fps = Div{parent=page_div,x=2,width=p_width}
        local gls = Div{parent=page_div,x=2,width=p_width}
        local lnk = Div{parent=page_div,x=2,width=p_width}
        local panes = { home, search, use, uis, fps, gls, lnk } ---@type Div[]

        local doc_map = {}   ---@type { [string]: function }
        local search_db = {} ---@type [ string, string, string, function ][]

        local sect_construct_data = { app, page_div, panes, doc_map, search_db, btn_fg_bg, btn_active }

        TextBox{parent=home,y=1,text="cc-mek-scada Guide",alignment=ALIGN.CENTER}

        PushButton{parent=home,y=3,text="Search              >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=search_page.nav_to}
        PushButton{parent=home,y=5,text="System Usage        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=use_page.nav_to}
        PushButton{parent=home,text="Operator UIs        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=uis_page.nav_to}
        PushButton{parent=home,text="Front Panels        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fps_page.nav_to}
        PushButton{parent=home,text="Glossary            >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=gls_page.nav_to}
        PushButton{parent=home,y=10,text="Wiki and Discord    >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=lnk_page.nav_to}

        load_text("Search")

        TextBox{parent=search,y=1,text="Search",alignment=ALIGN.CENTER}

        local query_field = TextField{parent=search,x=1,y=3,width=18,fg_bg=cpair(colors.white,colors.gray)}

        local func_ref = {}

        PushButton{parent=search,x=20,y=3,text="GO",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()func_ref.run_search()end}

        local search_results = ListBox{parent=search,x=1,y=5,scroll_height=200,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}

        function func_ref.run_search()
            local query = string.lower(query_field.get_value())
            local s_results = { {}, {}, {}, {} } ---@type [ string, string, string, function ][][]

            search_results.remove_all()

            if string.len(query) < 2 then
                TextBox{parent=search_results,text="Search requires at least 2 characters."}
                return
            end

            local start = util.time_ms()

            for _, entry in ipairs(search_db) do
                local s_start, s_end = string.find(entry[1], query, 1, true)

                if s_start == nil then
                elseif s_start == 1 then
                    if s_end == string.len(entry[1]) then
                        -- best match: full match
                        table.insert(s_results[1], entry)
                    else
                        -- very good match, start of key
                        table.insert(s_results[2], entry)
                    end
                elseif string.sub(query, s_start - 1, s_start) == " " then
                    -- start of word, good match
                    table.insert(s_results[3], entry)
                else
                    -- basic match in content
                    table.insert(s_results[4], entry)
                end
            end

            local empty = true

            for tier = 1, 4 do
                for idx = 1, #s_results[tier] do
                    local entry = s_results[tier][idx]
                    TextBox{parent=search_results,text=entry[3].." >",fg_bg=cpair(colors.gray,colors.black)}
                    PushButton{parent=search_results,text=entry[2],alignment=ALIGN.LEFT,fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=entry[4]}

                    empty = false
                end
            end

            log.debug("App.Guide: search for \"" .. query .. "\" completed in " .. (util.time_ms() - start) .. "ms")

            if empty then
                TextBox{parent=search_results,text="No results found."}
            end
        end

        TextBox{parent=search_results,text="Click 'GO' to search..."}

        util.nop()

        load_text("System Usage")

        TextBox{parent=use,y=1,text="System Usage",alignment=ALIGN.CENTER}
        PushButton{parent=use,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        load_text(false, "Connecting Devices")
        local conn_dev_page = guide_section(sect_construct_data, use_page, "Connecting Devs", docs.usage.conn, 110)
        load_text(false, "Configuring Devices")
        local config_dev_page = guide_section(sect_construct_data, use_page, "Configuring Devs", docs.usage.config, 350)
        load_text(false, "Manual Control")
        local man_ctrl_page = guide_section(sect_construct_data, use_page, "Manual Control", docs.usage.manual, 100)
        load_text(false, "Auto Control")
        local auto_ctrl_page = guide_section(sect_construct_data, use_page, "Auto Control", docs.usage.auto, 200)
        load_text(false, "Waste Control")
        local waste_ctrl_page = guide_section(sect_construct_data, use_page, "Waste Control", docs.usage.waste, 120)

        PushButton{parent=use,y=3,text="Connecting Devices  >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=conn_dev_page.nav_to}
        PushButton{parent=use,text="Configuring Devices >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=config_dev_page.nav_to}
        PushButton{parent=use,text="Manual Control      >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=man_ctrl_page.nav_to}
        PushButton{parent=use,text="Automatic Control   >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=auto_ctrl_page.nav_to}
        PushButton{parent=use,text="Waste Control       >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=waste_ctrl_page.nav_to}

        load_text("Operator UIs")

        TextBox{parent=uis,y=1,text="Operator UIs",alignment=ALIGN.CENTER}
        PushButton{parent=uis,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        local annunc_page = app.new_page(uis_page, #panes + 1)
        local annunc_div = Div{parent=page_div,x=2}
        table.insert(panes, annunc_div)

        local coord_page = app.new_page(uis_page, #panes + 1)
        local coord_div = Div{parent=page_div,x=2}
        table.insert(panes, coord_div)

        load_text(false, "Alarms")

        local alarms_page = guide_section(sect_construct_data, uis_page, "Alarms", docs.alarms, 100)

        PushButton{parent=uis,y=3,text="Alarms              >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=alarms_page.nav_to}
        PushButton{parent=uis,text="Annunciators        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=annunc_page.nav_to}
        PushButton{parent=uis,text="Coordinator UI      >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=coord_page.nav_to}

        load_text(false, "Annunciators")

        TextBox{parent=annunc_div,y=1,text="Annunciators",alignment=ALIGN.CENTER}
        PushButton{parent=annunc_div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=uis_page.nav_to}

        local fac_annunc_page = guide_section(sect_construct_data, annunc_page, "Facility", docs.annunc.facility.main_section, 110)
        local unit_gen_page = guide_section(sect_construct_data, annunc_page, "Unit General", docs.annunc.unit.main_section, 170)
        local unit_rps_page = guide_section(sect_construct_data, annunc_page, "Unit RPS", docs.annunc.unit.rps_section, 100)
        local unit_rcs_page = guide_section(sect_construct_data, annunc_page, "Unit RCS", docs.annunc.unit.rcs_section, 170)

        PushButton{parent=annunc_div,y=3,text="Facility General    >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fac_annunc_page.nav_to}
        PushButton{parent=annunc_div,text="Unit General        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=unit_gen_page.nav_to}
        PushButton{parent=annunc_div,text="Unit RPS            >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=unit_rps_page.nav_to}
        PushButton{parent=annunc_div,text="Unit RCS            >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=unit_rcs_page.nav_to}

        load_text(false, "Coordinator UI")

        TextBox{parent=coord_div,y=1,text="Coordinator UI",alignment=ALIGN.CENTER}
        PushButton{parent=coord_div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=uis_page.nav_to}

        load_text(false, "Main Display")
        local main_disp_page = guide_section(sect_construct_data, coord_page, "Main Display", docs.c_ui.main, 300)
        load_text(false, "Flow Display")
        local flow_disp_page = guide_section(sect_construct_data, coord_page, "Flow Display", docs.c_ui.flow, 210)
        load_text(false, "Unit Displays")
        local unit_disp_page = guide_section(sect_construct_data, coord_page, "Unit Displays", docs.c_ui.unit, 150)

        PushButton{parent=coord_div,y=3,text="Main Display        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_disp_page.nav_to}
        PushButton{parent=coord_div,text="Flow Display        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=flow_disp_page.nav_to}
        PushButton{parent=coord_div,text="Unit Displays       >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=unit_disp_page.nav_to}

        load_text("Front Panels")

        TextBox{parent=fps,y=1,text="Front Panels",alignment=ALIGN.CENTER}
        PushButton{parent=fps,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        load_text(false, "Common Items")
        local fp_common_page = guide_section(sect_construct_data, fps_page, "Common Items", docs.fp.common, 100)
        load_text(false, "Reactor PLC")
        local fp_rplc_page = guide_section(sect_construct_data, fps_page, "Reactor PLC", docs.fp.r_plc, 190)
        load_text(false, "RTU Gateway")
        local fp_rtu_page = guide_section(sect_construct_data, fps_page, "RTU Gateway", docs.fp.rtu_gw, 100)
        load_text(false, "Supervisor")
        local fp_supervisor_page = guide_section(sect_construct_data, fps_page, "Supervisor", docs.fp.supervisor, 160)
        load_text(false, "Coordinator")
        local fp_coordinator_page = guide_section(sect_construct_data, fps_page, "Coordinator", docs.fp.coordinator, 80)

        PushButton{parent=fps,y=3,text="Common Items        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fp_common_page.nav_to}
        PushButton{parent=fps,text="Reactor PLC         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fp_rplc_page.nav_to}
        PushButton{parent=fps,text="RTU Gateway         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fp_rtu_page.nav_to}
        PushButton{parent=fps,text="Supervisor          >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fp_supervisor_page.nav_to}
        PushButton{parent=fps,text="Coordinator         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fp_coordinator_page.nav_to}

        load_text("Glossary")

        TextBox{parent=gls,y=1,text="Glossary",alignment=ALIGN.CENTER}
        PushButton{parent=gls,x=3,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        local gls_abbv_page = guide_section(sect_construct_data, gls_page, "Abbreviations", docs.glossary.abbvs, 140)
        local gls_term_page = guide_section(sect_construct_data, gls_page, "Terminology", docs.glossary.terms, 100)

        PushButton{parent=gls,y=3,text="Abbreviations       >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=gls_abbv_page.nav_to}
        PushButton{parent=gls,text="Terminology         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=gls_term_page.nav_to}

        load_text("Links")

        TextBox{parent=lnk,y=1,text="Wiki and Discord",alignment=ALIGN.CENTER}
        PushButton{parent=lnk,x=1,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        lnk.line_break()
        TextBox{parent=lnk,text="GitHub",fg_bg=cpair(colors.lightGray,colors.black)}
        TextBox{parent=lnk,text="https://github.com/MikaylaFischler/cc-mek-scada"}
        lnk.line_break()
        TextBox{parent=lnk,text="Wiki",fg_bg=cpair(colors.lightGray,colors.black)}
        TextBox{parent=lnk,text="https://github.com/MikaylaFischler/cc-mek-scada/wiki"}
        lnk.line_break()
        TextBox{parent=lnk,text="Discord",fg_bg=cpair(colors.lightGray,colors.black)}
        TextBox{parent=lnk,text="discord.gg/R9NSCkhcwt"}

        -- setup multipane
        local u_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(u_pane)

        -- link help resources
        db.nav.link_help(doc_map)

        -- done, show the app
        load_pane.set_value(2)
    end

    -- delete the elements and switch back to the loading screen
    local function unload()
        if page_div then
            page_div.delete()
            page_div = nil
        end

        app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })
        app.delete_pages()

        -- show loading screen
        load_pane.set_value(1)
    end

    app.set_load(load)
    app.set_unload(unload)

    return main
end

return new_view
