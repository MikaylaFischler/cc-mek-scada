--
-- About Page
--

local comms      = require("scada-common.comms")
local util       = require("scada-common.util")

local ioctl      = require("pocket.ioctl")
local pocket     = require("pocket.pocket")

local style      = require("pocket.ui.style")

local core       = require("graphics.core")

local Div        = require("graphics.elements.Div")
local ListBox    = require("graphics.elements.ListBox")
local MultiPane  = require("graphics.elements.MultiPane")
local TextBox    = require("graphics.elements.TextBox")

local WaitingAnim = require("graphics.elements.animations.Waiting")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")
local PushButton = require("graphics.elements.controls.PushButton")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

local label_fg_bg  = style.label
local lu_col       = style.label_unit_pair
local text_fg      = style.text_fg

-- create build page view
---@param root Container parent
local function new_view(root)
    local db = ioctl.get_db()

    local frame = Div{parent=root,y=1}

    local app = db.nav.register_app(APP_ID.BUILD, frame, nil, false, true)

    local load_div = Div{parent=frame,y=1}
    local main = Div{parent=frame,y=1}

    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.pink,colors._INHERIT)}

    local load_pane = MultiPane{parent=main,y=1,panes={load_div,main}}

    app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })

    local btn_fg_bg = cpair(colors.lightBlue, colors.black)
    local btn_active = cpair(colors.white, colors.black)

    local page_div = nil ---@type Div|nil

    -- load the app (create the elements)
    local function load()
        local fac  = db.facility
        local f_ps = fac.ps

        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {} ---@type Div[]

        -- refresh data callback, every 5s it will re-send the query
        local last_update = 0
        local function update()
            -- if util.time_ms() - last_update >= 5000 then
            --     db.api.get_fac()
            --     last_update = util.time_ms()
            -- end
        end

        local main_pane = Div{parent=page_div}
        local main_div = Div{parent=main_pane,x=2,width=main.get_width()-2}
        table.insert(panes, main_div)

        local main_page = app.new_page(nil, #panes)
        main_page.tasks = { update }

        TextBox{parent=main_div,y=1,text="Facility Construction",alignment=ALIGN.CENTER}
        TextBox{parent=main_div,y=3,text="Select a class of device from the left to view the build properties of those devices currently connected.",fg_bg=label_fg_bg}

        --#region reactors

        local rct_pane = Div{parent=page_div}
        local rct_div = Div{parent=rct_pane,x=2,width=main.get_width()-2}
        table.insert(panes, rct_div)

        local rct_page = app.new_page(nil, #panes)
        rct_page.tasks = { update }

        TextBox{parent=rct_div,y=1,height=2,text="Fission Reactors",alignment=ALIGN.CENTER}

        for i = 1, fac.num_units do
            local u_pane = Div{parent=page_div}
            local u_div = Div{parent=u_pane}
            table.insert(panes, u_div)

            local u_page = app.new_page(rct_page, #panes)
            u_page.tasks = { update }

            local u_ps = db.units[i].unit_ps

            PushButton{parent=rct_div,text="Unit "..i.." Reactor      >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=u_page.nav_to}

            TextBox{parent=u_div,y=1,text="Unit "..i.." Reactor",alignment=ALIGN.CENTER}

            local list_box = ListBox{parent=u_div,x=2,y=3,scroll_height=40,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
            local list = Div{parent=list_box,y=2,width=main.get_width()-2,height=39}

            TextBox{parent=list,text="Maximum Burn Rate",fg_bg=label_fg_bg}
            local max_burn = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
            max_burn.register(u_ps, "max_burn", max_burn.update)

            list.line_break()
            TextBox{parent=list,text="Fuel Assemblies",fg_bg=label_fg_bg}
            local fuel_asm = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
            fuel_asm.register(u_ps, "fuel_asm", fuel_asm.update)

            list.line_break()
            TextBox{parent=list,text="Fuel Surface Area",fg_bg=label_fg_bg}
            local fuel_sa = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="m\xb2",format="%d",value=0,width=20,fg_bg=text_fg}
            fuel_sa.register(u_ps, "fuel_sa", fuel_sa.update)

            list.line_break()
            TextBox{parent=list,text="Fuel Capacity",fg_bg=label_fg_bg}
            local fuel_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            fuel_cap.register(u_ps, "fuel_cap", fuel_cap.update)

            list.line_break()
            TextBox{parent=list,text="Waste Capacity",fg_bg=label_fg_bg}
            local waste_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            waste_cap.register(u_ps, "waste_cap", waste_cap.update)

            list.line_break()
            TextBox{parent=list,text="Cooled Coolant Cap.",fg_bg=label_fg_bg}
            local cool_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            cool_cap.register(u_ps, "cool_cap", cool_cap.update)

            list.line_break()
            TextBox{parent=list,text="Heated Coolant Cap.",fg_bg=label_fg_bg}
            local hcool_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            hcool_cap.register(u_ps, "hcool_cap", hcool_cap.update)

            list.line_break()
            TextBox{parent=list,text="Heat Capacity",fg_bg=label_fg_bg}
            local heat_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="J",format="%d",value=0,width=20,fg_bg=text_fg}
            heat_cap.register(u_ps, "heat_cap", heat_cap.update)

            list.line_break()
            TextBox{parent=list,text="Dimensions",fg_bg=label_fg_bg}
            local l = DataIndicator{parent=list,lu_colors=lu_col,label="Length:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local w = DataIndicator{parent=list,lu_colors=lu_col,label="Width: ",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local h = DataIndicator{parent=list,lu_colors=lu_col,label="Height:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            l.register(u_ps, "length", l.update)
            w.register(u_ps, "width", w.update)
            h.register(u_ps, "height", h.update)

            list.line_break()
            TextBox{parent=list,text="Minimum Position",fg_bg=label_fg_bg}
            local x1 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local y1 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local z1 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            x1.register(u_ps, "min_pos", function (crd)
                x1.update(crd.x); y1.update(crd.y); z1.update(crd.z)
            end)

            list.line_break()
            TextBox{parent=list,text="Maximum Position",fg_bg=label_fg_bg}
            local x2 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local y2 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local z2 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            x2.register(u_ps, "min_pos", function (crd)
                x2.update(crd.x); y2.update(crd.y); z2.update(crd.z)
            end)
        end

        --#endregion

        --#region boilers

        local blr_pane = Div{parent=page_div}
        local blr_div = Div{parent=blr_pane,x=2,width=main.get_width()-2}
        table.insert(panes, blr_div)

        local blr_page = app.new_page(nil, #panes)
        blr_page.tasks = { update }

        TextBox{parent=blr_div,y=1,height=2,text="Sodium Boilers",alignment=ALIGN.CENTER}

        for i = 1, fac.num_units do
            local u = db.units[i]

            for b = 1, u.num_boilers do
                local u_pane = Div{parent=page_div}
                local u_div = Div{parent=u_pane}
                table.insert(panes, u_div)

                local u_page = app.new_page(blr_page, #panes)
                u_page.tasks = { update }

                local b_ps = u.boiler_ps_tbl[b]

                PushButton{parent=blr_div,text="Unit "..i.." Boiler "..b.."     >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=u_page.nav_to}

                TextBox{parent=u_div,y=1,text="Unit "..i.." Boiler "..b,alignment=ALIGN.CENTER}

                local list_box = ListBox{parent=u_div,x=2,y=3,scroll_height=37,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
                local list = Div{parent=list_box,y=2,width=main.get_width()-2,height=36}

                TextBox{parent=list,text="Superheating Elements",fg_bg=label_fg_bg}
                local superheaters = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
                superheaters.register(b_ps, "superheaters", superheaters.update)

                list.line_break()
                TextBox{parent=list,text="Max Boil Rate",fg_bg=label_fg_bg}
                local max_boil_rate = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB/t",format="%d",value=0,width=20,fg_bg=text_fg}
                max_boil_rate.register(b_ps, "max_boil_rate", max_boil_rate.update)

                list.line_break()
                TextBox{parent=list,text="Boil Capacity",fg_bg=label_fg_bg}
                local boil_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB/t",format="%d",value=0,width=20,fg_bg=text_fg}
                boil_cap.register(b_ps, "boil_cap", boil_cap.update)

                list.line_break()
                TextBox{parent=list,text="Steam Capacity",fg_bg=label_fg_bg}
                local steam_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
                steam_cap.register(b_ps, "steam_cap", steam_cap.update)

                list.line_break()
                TextBox{parent=list,text="Water Capacity",fg_bg=label_fg_bg}
                local water_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
                water_cap.register(b_ps, "water_cap", water_cap.update)

                list.line_break()
                TextBox{parent=list,text="Cooled Coolant Cap.",fg_bg=label_fg_bg}
                local cool_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
                cool_cap.register(b_ps, "cool_cap", cool_cap.update)

                list.line_break()
                TextBox{parent=list,text="Heated Coolant Cap.",fg_bg=label_fg_bg}
                local hcool_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
                hcool_cap.register(b_ps, "hcool_cap", hcool_cap.update)

                list.line_break()
                TextBox{parent=list,text="Dimensions",fg_bg=label_fg_bg}
                local l = DataIndicator{parent=list,lu_colors=lu_col,label="Length:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local w = DataIndicator{parent=list,lu_colors=lu_col,label="Width: ",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local h = DataIndicator{parent=list,lu_colors=lu_col,label="Height:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                l.register(b_ps, "length", l.update)
                w.register(b_ps, "width", w.update)
                h.register(b_ps, "height", h.update)

                list.line_break()
                TextBox{parent=list,text="Minimum Position",fg_bg=label_fg_bg}
                local x1 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local y1 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local z1 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                x1.register(b_ps, "min_pos", function (crd)
                    x1.update(crd.x); y1.update(crd.y); z1.update(crd.z)
                end)

                list.line_break()
                TextBox{parent=list,text="Maximum Position",fg_bg=label_fg_bg}
                local x2 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local y2 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local z2 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                x2.register(b_ps, "min_pos", function (crd)
                    x2.update(crd.x); y2.update(crd.y); z2.update(crd.z)
                end)
            end
        end

        --#endregion

        --#region boilers

        local trb_pane = Div{parent=page_div}
        local trb_div = Div{parent=trb_pane,x=2,width=main.get_width()-2}
        table.insert(panes, trb_div)

        local trb_page = app.new_page(nil, #panes)
        trb_page.tasks = { update }

        TextBox{parent=trb_div,y=1,height=2,text="Steam Turbines",alignment=ALIGN.CENTER}

        for i = 1, fac.num_units do
            local u = db.units[i]

            for t = 1, u.num_turbines do
                local pane = Div{parent=page_div}
                local div = Div{parent=pane}
                table.insert(panes, div)

                local page = app.new_page(trb_page, #panes)
                page.tasks = { update }

                local t_ps = u.turbine_ps_tbl[t]

                PushButton{parent=trb_div,text="Unit "..i.." Turbine "..t.."    >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=page.nav_to}

                TextBox{parent=div,y=1,text="Unit "..i.." Turbine "..t,alignment=ALIGN.CENTER}

                local list_box = ListBox{parent=div,x=2,y=3,scroll_height=52,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
                local list = Div{parent=list_box,y=2,width=main.get_width()-2,height=51}

                TextBox{parent=list,text="Blades",fg_bg=label_fg_bg}
                local blades = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
                blades.register(t_ps, "blades", blades.update)

                list.line_break()
                TextBox{parent=list,text="Coils",fg_bg=label_fg_bg}
                local coils = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
                coils.register(t_ps, "coils", coils.update)

                list.line_break()
                TextBox{parent=list,text="Vents",fg_bg=label_fg_bg}
                local vents = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
                vents.register(t_ps, "vents", vents.update)

                list.line_break()
                TextBox{parent=list,text="Dispersers",fg_bg=label_fg_bg}
                local dispersers = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
                dispersers.register(t_ps, "dispersers", dispersers.update)

                list.line_break()
                TextBox{parent=list,text="Condensers",fg_bg=label_fg_bg}
                local condensers = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
                condensers.register(t_ps, "condensers", condensers.update)

                list.line_break()
                TextBox{parent=list,text="Max Energy",fg_bg=label_fg_bg}
                local max_energy = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="FE",format="%d",value=0,width=20,fg_bg=text_fg}
                max_energy.register(t_ps, "max_energy", max_energy.update)

                list.line_break()
                TextBox{parent=list,text="Max Production",fg_bg=label_fg_bg}
                local max_production = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="FE/t",format="%d",value=0,width=20,fg_bg=text_fg}
                max_production.register(t_ps, "max_production", max_production.update)

                list.line_break()
                TextBox{parent=list,text="Max Flow Rate",fg_bg=label_fg_bg}
                local max_flow_rate = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB/t",format="%d",value=0,width=20,fg_bg=text_fg}
                max_flow_rate.register(t_ps, "max_flow_rate", max_flow_rate.update)

                list.line_break()
                TextBox{parent=list,text="Max Water Return Rate",fg_bg=label_fg_bg}
                local max_water_output = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB/t",format="%d",value=0,width=20,fg_bg=text_fg}
                max_water_output.register(t_ps, "max_water_output", max_water_output.update)

                list.line_break()
                TextBox{parent=list,text="Generator Efficiency",fg_bg=label_fg_bg}
                local gen_eff = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="%",format="%.6f",value=0,width=20,fg_bg=text_fg}
                gen_eff.register(t_ps, "max_production", function (prod) gen_eff.update((prod / u.turbine_data_tbl[t].build.max_flow_rate) / 4.0 * 100.0) end)
                gen_eff.register(t_ps, "max_flow_rate", function (flow) gen_eff.update((u.turbine_data_tbl[t].build.max_production / flow) / 4.0 * 100.0) end)

                list.line_break()
                TextBox{parent=list,text="Generator Multiplier",fg_bg=label_fg_bg}
                local gen_mult = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%.6f",value=0,width=20,fg_bg=text_fg}
                gen_mult.register(t_ps, "max_production", function (prod) gen_mult.update(prod / u.turbine_data_tbl[t].build.max_flow_rate) end)
                gen_mult.register(t_ps, "max_flow_rate", function (flow) gen_mult.update(u.turbine_data_tbl[t].build.max_production / flow) end)

                list.line_break()
                TextBox{parent=list,text="Steam Capacity",fg_bg=label_fg_bg}
                local steam_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
                steam_cap.register(t_ps, "steam_cap", steam_cap.update)

                list.line_break()
                TextBox{parent=list,text="Dimensions",fg_bg=label_fg_bg}
                local l = DataIndicator{parent=list,lu_colors=lu_col,label="Length:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local w = DataIndicator{parent=list,lu_colors=lu_col,label="Width: ",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local h = DataIndicator{parent=list,lu_colors=lu_col,label="Height:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                l.register(t_ps, "length", l.update)
                w.register(t_ps, "width", w.update)
                h.register(t_ps, "height", h.update)

                list.line_break()
                TextBox{parent=list,text="Minimum Position",fg_bg=label_fg_bg}
                local x1 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local y1 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local z1 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                x1.register(t_ps, "min_pos", function (crd)
                    x1.update(crd.x); y1.update(crd.y); z1.update(crd.z)
                end)

                list.line_break()
                TextBox{parent=list,text="Maximum Position",fg_bg=label_fg_bg}
                local x2 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local y2 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                local z2 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
                x2.register(t_ps, "min_pos", function (crd)
                    x2.update(crd.x); y2.update(crd.y); z2.update(crd.z)
                end)
            end
        end

        --#endregion

        local tnk_page = app.new_page(nil, 5)
        local sps_page = app.new_page(nil, 6)
        local ess_page = app.new_page(nil, 7)

        -- setup multipane
        local f_pane = MultiPane{parent=page_div,y=1,panes=panes}
        app.set_root_pane(f_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = " \x08 ", color = core.cpair(colors.black, colors.lightGray), callback = main_page.nav_to },
            { label = "RCT", color = core.cpair(colors.black, colors.cyan), callback = rct_page.nav_to },
            { label = "BLR", color = core.cpair(colors.black, colors.orange), callback = blr_page.nav_to },
            { label = "TRB", color = core.cpair(colors.black, colors.white), callback = trb_page.nav_to },
            { label = "TNK", color = core.cpair(colors.black, colors.blue), callback = tnk_page.nav_to },
            { label = "SPS", color = core.cpair(colors.black, colors.purple), callback = sps_page.nav_to },
            { label = "ESS", color = core.cpair(colors.black, colors.green), callback = ess_page.nav_to }
        }

        app.set_sidebar(list)

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
