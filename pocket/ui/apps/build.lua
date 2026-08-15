--
-- About Page
--

local types         = require("scada-common.types")
local util          = require("scada-common.util")

local ioctl         = require("pocket.ioctl")
local pocket        = require("pocket.pocket")

local style         = require("pocket.ui.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local ListBox       = require("graphics.elements.ListBox")
local MultiPane     = require("graphics.elements.MultiPane")
local TextBox       = require("graphics.elements.TextBox")

local WaitingAnim   = require("graphics.elements.animations.Waiting")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")
local PushButton    = require("graphics.elements.controls.PushButton")

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

    local btn_fg_bg = cpair(colors.pink, colors.black)
    local btn_active = cpair(colors.white, colors.black)

    local page_div = nil ---@type Div|nil

    -- load the app (create the elements)
    local function load()
        local fac  = db.facility

        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {} ---@type Div[]

        -- refresh data callback, every 5s it will re-send the query
        local last_update = 0
        local function update()
            if util.time_ms() - last_update >= 5000 then
                db.api.get_build()
                last_update = util.time_ms()
            end
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
            local pane = Div{parent=page_div}
            local div = Div{parent=pane}
            table.insert(panes, div)

            local page = app.new_page(rct_page, #panes)
            page.tasks = { update }

            local u_ps = db.units[i].unit_ps

            PushButton{parent=rct_div,text="Unit "..i.." Reactor      >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=page.nav_to}

            TextBox{parent=div,y=1,text="Unit "..i.." Reactor",alignment=ALIGN.CENTER}
            PushButton{parent=div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=rct_page.nav_to}

            local list_box = ListBox{parent=div,x=2,y=3,scroll_height=48,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
            local list = Div{parent=list_box,y=2,width=main.get_width()-2,height=47}

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
            local ccool_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            ccool_cap.register(u_ps, "ccool_cap", ccool_cap.update)

            list.line_break()
            TextBox{parent=list,text="Heated Coolant Cap.",fg_bg=label_fg_bg}
            local hcool_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            hcool_cap.register(u_ps, "hcool_cap", hcool_cap.update)

            list.line_break()
            TextBox{parent=list,text="Heat Capacity",fg_bg=label_fg_bg}
            local heat_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="J",format="%d",value=0,width=20,fg_bg=text_fg}
            heat_cap.register(u_ps, "heat_cap", heat_cap.update)

            list.line_break()
            TextBox{parent=list,text="Maximum Operational Temp (Water Cooled)",fg_bg=label_fg_bg}
            local water_op = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="K",format="%.2f",value=0,width=20,fg_bg=text_fg}
            water_op.register(u_ps, "max_op_temp_H2O", water_op.update)

            list.line_break()
            TextBox{parent=list,text="Maximum Operational Temp (Sodium Cooled)",fg_bg=label_fg_bg}
            local sodium_op = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="K",format="%.2f",value=0,width=20,fg_bg=text_fg}
            sodium_op.register(u_ps, "max_op_temp_Na", sodium_op.update)

            list.line_break()
            TextBox{parent=list,text="Dimensions",fg_bg=label_fg_bg}
            local l = DataIndicator{parent=list,lu_colors=lu_col,label="Length:",format="%d",value=0,width=13,fg_bg=text_fg}
            local w = DataIndicator{parent=list,lu_colors=lu_col,label="Width: ",format="%d",value=0,width=13,fg_bg=text_fg}
            local h = DataIndicator{parent=list,lu_colors=lu_col,label="Height:",format="%d",value=0,width=13,fg_bg=text_fg}
            l.register(u_ps, "length", l.update)
            w.register(u_ps, "width", w.update)
            h.register(u_ps, "height", h.update)

            list.line_break()
            TextBox{parent=list,text="Minimum Position",fg_bg=label_fg_bg}
            local x1 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
            local y1 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
            local z1 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
            x1.register(u_ps, "min_pos", function (crd)
                x1.update(crd.x); y1.update(crd.y); z1.update(crd.z)
            end)

            list.line_break()
            TextBox{parent=list,text="Maximum Position",fg_bg=label_fg_bg}
            local x2 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
            local y2 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
            local z2 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
            x2.register(u_ps, "max_pos", function (crd)
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
                local pane = Div{parent=page_div}
                local div = Div{parent=pane}
                table.insert(panes, div)

                local page = app.new_page(blr_page, #panes)
                page.tasks = { update }

                local b_ps = u.boiler_ps_tbl[b]

                PushButton{parent=blr_div,text="Unit "..i.." Boiler "..b.."     >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=page.nav_to}

                TextBox{parent=div,y=1,text="Unit "..i.." Boiler "..b,alignment=ALIGN.CENTER}
                PushButton{parent=div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=blr_page.nav_to}

                local list_box = ListBox{parent=div,x=2,y=3,scroll_height=34,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
                local list = Div{parent=list_box,y=2,width=main.get_width()-2,height=33}

                TextBox{parent=list,text="Superheating Elements",fg_bg=label_fg_bg}
                local superheaters = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
                superheaters.register(b_ps, "superheaters", superheaters.update)

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
                local ccool_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
                ccool_cap.register(b_ps, "ccoolant_cap", ccool_cap.update)

                list.line_break()
                TextBox{parent=list,text="Heated Coolant Cap.",fg_bg=label_fg_bg}
                local hcool_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
                hcool_cap.register(b_ps, "hcoolant_cap", hcool_cap.update)

                list.line_break()
                TextBox{parent=list,text="Dimensions",fg_bg=label_fg_bg}
                local l = DataIndicator{parent=list,lu_colors=lu_col,label="Length:",format="%d",value=0,width=13,fg_bg=text_fg}
                local w = DataIndicator{parent=list,lu_colors=lu_col,label="Width: ",format="%d",value=0,width=13,fg_bg=text_fg}
                local h = DataIndicator{parent=list,lu_colors=lu_col,label="Height:",format="%d",value=0,width=13,fg_bg=text_fg}
                l.register(b_ps, "length", l.update)
                w.register(b_ps, "width", w.update)
                h.register(b_ps, "height", h.update)

                list.line_break()
                TextBox{parent=list,text="Minimum Position",fg_bg=label_fg_bg}
                local x1 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
                local y1 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
                local z1 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
                x1.register(b_ps, "min_pos", function (crd)
                    x1.update(crd.x); y1.update(crd.y); z1.update(crd.z)
                end)

                list.line_break()
                TextBox{parent=list,text="Maximum Position",fg_bg=label_fg_bg}
                local x2 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
                local y2 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
                local z2 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
                x2.register(b_ps, "max_pos", function (crd)
                    x2.update(crd.x); y2.update(crd.y); z2.update(crd.z)
                end)
            end
        end

        --#endregion

        --#region turbines

        local tbn_pane = Div{parent=page_div}
        local tbn_div = Div{parent=tbn_pane,x=2,width=main.get_width()-2}
        table.insert(panes, tbn_div)

        local tbn_page = app.new_page(nil, #panes)
        tbn_page.tasks = { update }

        TextBox{parent=tbn_div,y=1,height=2,text="Steam Turbines",alignment=ALIGN.CENTER}

        for i = 1, fac.num_units do
            local u = db.units[i]

            for t = 1, u.num_turbines do
                local pane = Div{parent=page_div}
                local div = Div{parent=pane}
                table.insert(panes, div)

                local page = app.new_page(tbn_page, #panes)
                page.tasks = { update }

                local t_ps = u.turbine_ps_tbl[t]

                PushButton{parent=tbn_div,text="Unit "..i.." Turbine "..t.."    >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=page.nav_to}

                TextBox{parent=div,y=1,text="Unit "..i.." Turbine "..t,alignment=ALIGN.CENTER}
                PushButton{parent=div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=tbn_page.nav_to}

                local list_box = ListBox{parent=div,x=2,y=3,scroll_height=55,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
                local list = Div{parent=list_box,y=2,width=main.get_width()-2,height=54}

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
                local max_energy = DataIndicator{parent=list,lu_colors=lu_col,label="",unit=db.energy_label,format="%d",value=0,width=20,fg_bg=text_fg}
                max_energy.register(t_ps, "max_energy", function (e) max_energy.update(db.energy_convert(e)) end)

                list.line_break()
                TextBox{parent=list,text="Max Production",fg_bg=label_fg_bg}
                local max_production = DataIndicator{parent=list,lu_colors=lu_col,label="",unit=db.energy_label.."/t",format="%d",value=0,width=20,fg_bg=text_fg}
                max_production.register(t_ps, "max_production", function (e) max_production.update(db.energy_convert(e)) end)

                list.line_break()
                TextBox{parent=list,text="Max Flow Rate",fg_bg=label_fg_bg}
                local max_flow_rate = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB/t",format="%d",value=0,width=20,fg_bg=text_fg}
                max_flow_rate.register(t_ps, "max_flow_rate", max_flow_rate.update)

                list.line_break()
                TextBox{parent=list,text="Max Water Return Rate",fg_bg=label_fg_bg}
                local max_water_output = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB/t",format="%d",value=0,width=20,fg_bg=text_fg}
                max_water_output.register(t_ps, "max_water_output", max_water_output.update)

                list.line_break()
                TextBox{parent=list,text="Flow Performance",fg_bg=label_fg_bg}
                local flow_perf = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%f",value=0,width=20,fg_bg=text_fg}
                flow_perf.register(t_ps, "flow_perf", flow_perf.update)

                list.line_break()
                TextBox{parent=list,text="Generator Efficiency",fg_bg=label_fg_bg}
                local gen_eff = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="%",format="%.2f",value=0,width=20,fg_bg=text_fg}
                gen_eff.register(t_ps, "gen_eff", function (eff) gen_eff.update(eff * 100.0) end)

                list.line_break()
                TextBox{parent=list,text="Generator Multiplier",fg_bg=label_fg_bg}
                local gen_mult = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%f",value=0,width=20,fg_bg=text_fg}
                gen_mult.register(t_ps, "gen_mult", gen_mult.update)

                list.line_break()
                TextBox{parent=list,text="Steam Capacity",fg_bg=label_fg_bg}
                local steam_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
                steam_cap.register(t_ps, "steam_cap", steam_cap.update)

                list.line_break()
                TextBox{parent=list,text="Dimensions",fg_bg=label_fg_bg}
                local l = DataIndicator{parent=list,lu_colors=lu_col,label="Length:",format="%d",value=0,width=13,fg_bg=text_fg}
                local w = DataIndicator{parent=list,lu_colors=lu_col,label="Width: ",format="%d",value=0,width=13,fg_bg=text_fg}
                local h = DataIndicator{parent=list,lu_colors=lu_col,label="Height:",format="%d",value=0,width=13,fg_bg=text_fg}
                l.register(t_ps, "length", l.update)
                w.register(t_ps, "width", w.update)
                h.register(t_ps, "height", h.update)

                list.line_break()
                TextBox{parent=list,text="Minimum Position",fg_bg=label_fg_bg}
                local x1 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
                local y1 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
                local z1 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
                x1.register(t_ps, "min_pos", function (crd)
                    x1.update(crd.x); y1.update(crd.y); z1.update(crd.z)
                end)

                list.line_break()
                TextBox{parent=list,text="Maximum Position",fg_bg=label_fg_bg}
                local x2 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
                local y2 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
                local z2 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
                x2.register(t_ps, "max_pos", function (crd)
                    x2.update(crd.x); y2.update(crd.y); z2.update(crd.z)
                end)
            end
        end

        --#endregion

        --#region dynamic tanks

        local tnk_pane = Div{parent=page_div}
        local tnk_div = Div{parent=tnk_pane,x=2,width=main.get_width()-2}
        table.insert(panes, tnk_div)

        local tnk_page = app.new_page(nil, #panes)
        tnk_page.tasks = { update }

        local tanks = {}

        TextBox{parent=tnk_div,y=1,height=2,text="Dynamic Tanks",alignment=ALIGN.CENTER}

        local f_tank_id = 1
        for t = 1, #fac.tank_list do
            if fac.tank_list[t] == 2 then
                table.insert(tanks, { "F-" .. t .. " Facility Tank", fac.tank_ps_tbl[f_tank_id] })
                f_tank_id = f_tank_id + 1
            end
        end

        for i = 1, fac.num_units do
            local u = db.units[i]
            if u.tank_data_tbl[1] then
                table.insert(tanks, { "U-" .. i .. " Unit Tank    ", u.tank_ps_tbl[1] })
            end
        end

        for t = 1, #tanks do
            local pane = Div{parent=page_div}
            local div = Div{parent=pane}
            table.insert(panes, div)

            local page = app.new_page(tnk_page, #panes)
            page.tasks = { update }

            local t_name, t_ps = tanks[t][1], tanks[t][2]

            PushButton{parent=tnk_div,text=t_name.."   >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=page.nav_to}

            TextBox{parent=div,y=1,text=t_name,alignment=ALIGN.CENTER}
            PushButton{parent=div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=tnk_page.nav_to}

            local list_box = ListBox{parent=div,x=2,y=3,scroll_height=22,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
            local list = Div{parent=list_box,y=2,width=main.get_width()-2,height=21}

            TextBox{parent=list,text="Fluid Capacity",fg_bg=label_fg_bg}
            local tank_capacity = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            tank_capacity.register(t_ps, "tank_capacity", tank_capacity.update)

            list.line_break()
            TextBox{parent=list,text="Chemical Capacity",fg_bg=label_fg_bg}
            local chem_tank_capacity = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            chem_tank_capacity.register(t_ps, "chem_tank_capacity", chem_tank_capacity.update)

            list.line_break()
            TextBox{parent=list,text="Dimensions",fg_bg=label_fg_bg}
            local l = DataIndicator{parent=list,lu_colors=lu_col,label="Length:",format="%d",value=0,width=13,fg_bg=text_fg}
            local w = DataIndicator{parent=list,lu_colors=lu_col,label="Width: ",format="%d",value=0,width=13,fg_bg=text_fg}
            local h = DataIndicator{parent=list,lu_colors=lu_col,label="Height:",format="%d",value=0,width=13,fg_bg=text_fg}
            l.register(t_ps, "length", l.update)
            w.register(t_ps, "width", w.update)
            h.register(t_ps, "height", h.update)

            list.line_break()
            TextBox{parent=list,text="Minimum Position",fg_bg=label_fg_bg}
            local x1 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
            local y1 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
            local z1 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
            x1.register(t_ps, "min_pos", function (crd)
                x1.update(crd.x); y1.update(crd.y); z1.update(crd.z)
            end)

            list.line_break()
            TextBox{parent=list,text="Maximum Position",fg_bg=label_fg_bg}
            local x2 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
            local y2 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
            local z2 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
            x2.register(t_ps, "max_pos", function (crd)
                x2.update(crd.x); y2.update(crd.y); z2.update(crd.z)
            end)
        end

        --#endregion

        --#region SPS

        local sps_pane = Div{parent=page_div}
        local sps_div = Div{parent=sps_pane,x=2,width=main.get_width()-2}
        table.insert(panes, sps_div)

        local sps_page = app.new_page(nil, #panes)
        sps_page.tasks = { update }

        TextBox{parent=sps_div,x=2,y=1,height=3,text="Supercritical Phase Shifters",alignment=ALIGN.CENTER}

        for s = 1, #fac.sps_data_tbl do
            local pane = Div{parent=page_div}
            local div = Div{parent=pane}
            table.insert(panes, div)

            local page = app.new_page(sps_page, #panes)
            page.tasks = { update }

            local s_ps = fac.sps_ps_tbl[s]

            PushButton{parent=sps_div,text="Facility SPS        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=page.nav_to}

            TextBox{parent=div,y=1,text="Facility SPS",alignment=ALIGN.CENTER}
            PushButton{parent=div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=sps_page.nav_to}

            local list_box = ListBox{parent=div,x=2,y=3,scroll_height=28,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
            local list = Div{parent=list_box,y=2,width=main.get_width()-2,height=27}

            TextBox{parent=list,text="Supercharged Coils",fg_bg=label_fg_bg}
            local coils = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
            coils.register(s_ps, "coils", coils.update)

            list.line_break()
            TextBox{parent=list,text="Input Capacity",fg_bg=label_fg_bg}
            local input_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            input_cap.register(s_ps, "input_cap", input_cap.update)

            list.line_break()
            TextBox{parent=list,text="Output Capacity",fg_bg=label_fg_bg}
            local output_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            output_cap.register(s_ps, "output_cap", output_cap.update)

            list.line_break()
            TextBox{parent=list,text="Maximum Energy",fg_bg=label_fg_bg}
            local max_energy = DataIndicator{parent=list,lu_colors=lu_col,label="",unit=db.energy_label,format="%d",value=0,width=20,fg_bg=text_fg}
            max_energy.register(s_ps, "max_energy", function (e) max_energy.update(db.energy_convert(e)) end)

            list.line_break()
            TextBox{parent=list,text="Dimensions",fg_bg=label_fg_bg}
            local l = DataIndicator{parent=list,lu_colors=lu_col,label="Length:",format="%d",value=0,width=13,fg_bg=text_fg}
            local w = DataIndicator{parent=list,lu_colors=lu_col,label="Width: ",format="%d",value=0,width=13,fg_bg=text_fg}
            local h = DataIndicator{parent=list,lu_colors=lu_col,label="Height:",format="%d",value=0,width=13,fg_bg=text_fg}
            l.register(s_ps, "length", l.update)
            w.register(s_ps, "width", w.update)
            h.register(s_ps, "height", h.update)

            list.line_break()
            TextBox{parent=list,text="Minimum Position",fg_bg=label_fg_bg}
            local x1 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
            local y1 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
            local z1 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
            x1.register(s_ps, "min_pos", function (crd)
                x1.update(crd.x); y1.update(crd.y); z1.update(crd.z)
            end)

            list.line_break()
            TextBox{parent=list,text="Maximum Position",fg_bg=label_fg_bg}
            local x2 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
            local y2 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
            local z2 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
            x2.register(s_ps, "max_pos", function (crd)
                x2.update(crd.x); y2.update(crd.y); z2.update(crd.z)
            end)
        end

        --#endregion

        --#region ESS

        local ess_pane = Div{parent=page_div}
        local ess_div = Div{parent=ess_pane,x=2,width=main.get_width()-2}
        table.insert(panes, ess_div)

        local ess_page = app.new_page(nil, #panes)
        ess_page.tasks = { update }

        TextBox{parent=ess_div,x=2,y=1,height=3,text="Energy Storage Systems",alignment=ALIGN.CENTER}

        if fac.ess_type == types.ESS.ENERGY_CORE then
            local pane = Div{parent=page_div}
            local div = Div{parent=pane}
            table.insert(panes, div)

            local page = app.new_page(ess_page, #panes)
            page.tasks = { update }

            local e_ps = fac.ecore_ps_tbl[1]

            PushButton{parent=ess_div,text="Energy Core         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=page.nav_to}

            TextBox{parent=div,y=1,text="Energy Core",alignment=ALIGN.CENTER}
            PushButton{parent=div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=ess_page.nav_to}

            local list_box = ListBox{parent=div,x=2,y=3,scroll_height=6,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
            local list = Div{parent=list_box,y=2,width=main.get_width()-2,height=5}

            TextBox{parent=list,text="Tier",fg_bg=label_fg_bg}
            local tier = TextBox{parent=list,text="Unknown",fg_bg=text_fg}
            tier.register(e_ps, "tier", tier.set_value)

            list.line_break()
            TextBox{parent=list,text="Maximum Energy ("..db.energy_label..")",fg_bg=label_fg_bg}
            local max_energy = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
            max_energy.register(e_ps, "max_energy", function (e) max_energy.update(db.energy_convert_from_fe(e)) end)
        elseif fac.ess_type == types.ESS.INDUCTION_MATRIX then
            local pane = Div{parent=page_div}
            local div = Div{parent=pane}
            table.insert(panes, div)

            local page = app.new_page(ess_page, #panes)
            page.tasks = { update }

            local i_ps = fac.induction_ps_tbl[1]

            PushButton{parent=ess_div,text="Induction Matrix    >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=page.nav_to}

            TextBox{parent=div,y=1,text="Induction Matrix",alignment=ALIGN.CENTER}
            PushButton{parent=div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=ess_page.nav_to}

            local list_box = ListBox{parent=div,x=2,y=3,scroll_height=28,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
            local list = Div{parent=list_box,y=2,width=main.get_width()-2,height=27}

            TextBox{parent=list,text="Induction Cells",fg_bg=label_fg_bg}
            local cells = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
            cells.register(i_ps, "cells", cells.update)

            list.line_break()
            TextBox{parent=list,text="Induction Providers",fg_bg=label_fg_bg}
            local providers = DataIndicator{parent=list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
            providers.register(i_ps, "providers", providers.update)

            list.line_break()
            TextBox{parent=list,text="Maximum Energy",fg_bg=label_fg_bg}
            local max_energy = DataIndicator{parent=list,lu_colors=lu_col,label="",unit=db.energy_label,format="%d",value=0,width=20,fg_bg=text_fg}
            max_energy.register(i_ps, "max_energy", function (e) max_energy.update(db.energy_convert(e)) end)

            list.line_break()
            TextBox{parent=list,text="Transfer Capacity",fg_bg=label_fg_bg}
            local transfer_cap = DataIndicator{parent=list,lu_colors=lu_col,label="",unit=db.energy_label.."/t",format="%d",value=0,width=20,fg_bg=text_fg}
            transfer_cap.register(i_ps, "transfer_cap", function (e) transfer_cap.update(db.energy_convert(e)) end)

            list.line_break()
            TextBox{parent=list,text="Dimensions",fg_bg=label_fg_bg}
            local l = DataIndicator{parent=list,lu_colors=lu_col,label="Length:",format="%d",value=0,width=13,fg_bg=text_fg}
            local w = DataIndicator{parent=list,lu_colors=lu_col,label="Width: ",format="%d",value=0,width=13,fg_bg=text_fg}
            local h = DataIndicator{parent=list,lu_colors=lu_col,label="Height:",format="%d",value=0,width=13,fg_bg=text_fg}
            l.register(i_ps, "length", l.update)
            w.register(i_ps, "width", w.update)
            h.register(i_ps, "height", h.update)

            list.line_break()
            TextBox{parent=list,text="Minimum Position",fg_bg=label_fg_bg}
            local x1 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
            local y1 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
            local z1 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
            x1.register(i_ps, "min_pos", function (crd)
                x1.update(crd.x); y1.update(crd.y); z1.update(crd.z)
            end)

            list.line_break()
            TextBox{parent=list,text="Maximum Position",fg_bg=label_fg_bg}
            local x2 = DataIndicator{parent=list,lu_colors=lu_col,label="X:",format="%d",value=0,width=13,fg_bg=text_fg}
            local y2 = DataIndicator{parent=list,lu_colors=lu_col,label="Y:",format="%d",value=0,width=13,fg_bg=text_fg}
            local z2 = DataIndicator{parent=list,lu_colors=lu_col,label="Z:",format="%d",value=0,width=13,fg_bg=text_fg}
            x2.register(i_ps, "max_pos", function (crd)
                x2.update(crd.x); y2.update(crd.y); z2.update(crd.z)
            end)
        end

        --#endregion

        -- setup multipane
        local f_pane = MultiPane{parent=page_div,y=1,panes=panes}
        app.set_root_pane(f_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = " \x08 ", color = core.cpair(colors.black, colors.lightGray), callback = main_page.nav_to },
            { label = "RCT", color = core.cpair(colors.black, colors.white), callback = rct_page.nav_to },
            { label = "BLR", color = core.cpair(colors.black, colors.white), callback = blr_page.nav_to },
            { label = "TBN", color = core.cpair(colors.black, colors.white), callback = tbn_page.nav_to },
            { label = "TNK", color = core.cpair(colors.black, colors.white), callback = tnk_page.nav_to },
            { label = "SPS", color = core.cpair(colors.black, colors.white), callback = sps_page.nav_to },
            { label = "ESS", color = core.cpair(colors.black, colors.white), callback = ess_page.nav_to }
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
