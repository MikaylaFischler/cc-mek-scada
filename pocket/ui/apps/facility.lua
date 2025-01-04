--
-- Facility Overview App
--

local util          = require("scada-common.util")

local iocontrol     = require("pocket.iocontrol")
local pocket        = require("pocket.pocket")

local style         = require("pocket.ui.style")

local dyn_tank      = require("pocket.ui.pages.dynamic_tank")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local ListBox       = require("graphics.elements.ListBox")
local MultiPane     = require("graphics.elements.MultiPane")
local TextBox       = require("graphics.elements.TextBox")

local WaitingAnim   = require("graphics.elements.animations.Waiting")

local PushButton    = require("graphics.elements.controls.PushButton")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")
local IconIndicator = require("graphics.elements.indicators.IconIndicator")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

-- local label        = style.label
local lu_col       = style.label_unit_pair
local text_fg      = style.text_fg
local basic_states = style.icon_states.basic_states
local mode_states  = style.icon_states.mode_states
local red_ind_s    = style.icon_states.red_ind_s
local yel_ind_s    = style.icon_states.yel_ind_s

-- new unit page view
---@param root Container parent
local function new_view(root)
    local db  = iocontrol.get_db()
    local fac = db.facility

    local frame = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(APP_ID.FACILITY, frame, nil, false, true)

    local load_div = Div{parent=frame,x=1,y=1}
    local main = Div{parent=frame,x=1,y=1}

    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.orange,colors._INHERIT)}

    local load_pane = MultiPane{parent=main,x=1,y=1,panes={load_div,main}}

    app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })

    local btn_fg_bg = cpair(colors.orange, colors.black)
    local btn_active = cpair(colors.white, colors.black)

    local tank_pages = {}
    local page_div = nil ---@type Div|nil

    -- load the app (create the elements)
    local function load()
        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {} ---@type Div[]

        -- refresh data callback, every 500ms it will re-send the query
        local last_update = 0
        local function update()
            if util.time_ms() - last_update >= 500 then
                -- db.api.get_fac()
                last_update = util.time_ms()
            end
        end

        for i = 1, db.facility.num_units do
            local u_pane = panes[i]
            local u_div = Div{parent=u_pane,x=2,width=main.get_width()-2}
            local unit = db.units[i]
            local u_ps = unit.unit_ps

            --#region Main Unit Overview

            local f_page = app.new_page(nil, i)
            f_page.tasks = { update }

            TextBox{parent=u_div,y=1,text="Reactor Unit #"..i,alignment=ALIGN.CENTER}
            PushButton{parent=u_div,x=1,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()prev(i)end}
            PushButton{parent=u_div,x=21,y=1,text=">",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()next(i)end}

            local type = util.trinary(unit.num_boilers > 0, "Sodium Cooled Reactor", "Boiling Water Reactor")
            TextBox{parent=u_div,y=3,text=type,alignment=ALIGN.CENTER,fg_bg=cpair(colors.gray,colors.black)}

            local rate = DataIndicator{parent=u_div,y=5,lu_colors=lu_col,label="Burn",unit="mB/t",format="%10.2f",value=0,commas=true,width=26,fg_bg=text_fg}
            local temp = DataIndicator{parent=u_div,lu_colors=lu_col,label="Temp",unit=db.temp_label,format="%10.2f",value=0,commas=true,width=26,fg_bg=text_fg}

            local ctrl = IconIndicator{parent=u_div,x=1,y=8,label="Control State",states=mode_states}

            rate.register(u_ps, "act_burn_rate", rate.update)
            temp.register(u_ps, "temp", function (t) temp.update(db.temp_convert(t)) end)
            ctrl.register(u_ps, "U_ControlStatus", ctrl.update)

            u_div.line_break()

            local rct = IconIndicator{parent=u_div,x=1,label="Fission Reactor",states=basic_states}
            local rps = IconIndicator{parent=u_div,x=1,label="Protection System",states=basic_states}

            rct.register(u_ps, "U_ReactorStatus", rct.update)
            rps.register(u_ps, "U_RPS", rps.update)

            u_div.line_break()

            local rcs = IconIndicator{parent=u_div,x=1,label="Coolant System",states=basic_states}
            rcs.register(u_ps, "U_RCS", rcs.update)

            for b = 1, unit.num_boilers do
                local blr = IconIndicator{parent=u_div,x=1,label="Boiler "..b,states=basic_states}
                blr.register(unit.boiler_ps_tbl[b], "BoilerStatus", blr.update)
            end

            for t = 1, unit.num_turbines do
                local tbn = IconIndicator{parent=u_div,x=1,label="Turbine "..t,states=basic_states}
                tbn.register(unit.turbine_ps_tbl[t], "TurbineStatus", tbn.update)
            end

            --#endregion

            util.nop()

            --#region RPS Tab

            local rps_pane = Div{parent=page_div}
            local rps_div = Div{parent=rps_pane,x=2,width=main.get_width()-2}
            table.insert(panes, rps_div)

            local rps_page = app.new_page(f_page, #panes)
            rps_page.tasks = { update }
            nav_links[i].rps = rps_page.nav_to

            TextBox{parent=rps_div,y=1,text="Protection System",alignment=ALIGN.CENTER}

            local r_trip = IconIndicator{parent=rps_div,y=3,label="RPS Trip",states=basic_states}
            r_trip.register(u_ps, "U_RPS", r_trip.update)

            local r_mscrm = IconIndicator{parent=rps_div,y=5,label="Manual SCRAM",states=red_ind_s}
            local r_ascrm = IconIndicator{parent=rps_div,label="Automatic SCRAM",states=red_ind_s}
            local rps_tmo = IconIndicator{parent=rps_div,label="Timeout",states=yel_ind_s}
            local rps_flt = IconIndicator{parent=rps_div,label="PPM Fault",states=yel_ind_s}
            local rps_sfl = IconIndicator{parent=rps_div,label="Not Formed",states=red_ind_s}

            r_mscrm.register(u_ps, "manual", r_mscrm.update)
            r_ascrm.register(u_ps, "automatic", r_ascrm.update)
            rps_tmo.register(u_ps, "timeout", rps_tmo.update)
            rps_flt.register(u_ps, "fault", rps_flt.update)
            rps_sfl.register(u_ps, "sys_fail", rps_sfl.update)

            rps_div.line_break()
            local rps_dmg = IconIndicator{parent=rps_div,label="Reactor Damage Hi",states=red_ind_s}
            local rps_tmp = IconIndicator{parent=rps_div,label="Temp. Critical",states=red_ind_s}
            local rps_nof = IconIndicator{parent=rps_div,label="Fuel Level Lo",states=yel_ind_s}
            local rps_exw = IconIndicator{parent=rps_div,label="Waste Level Hi",states=yel_ind_s}
            local rps_loc = IconIndicator{parent=rps_div,label="Coolant Lo Lo",states=yel_ind_s}
            local rps_exh = IconIndicator{parent=rps_div,label="Heated Coolant Hi",states=yel_ind_s}

            rps_dmg.register(u_ps, "high_dmg", rps_dmg.update)
            rps_tmp.register(u_ps, "high_temp", rps_tmp.update)
            rps_nof.register(u_ps, "no_fuel", rps_nof.update)
            rps_exw.register(u_ps, "ex_waste", rps_exw.update)
            rps_loc.register(u_ps, "low_cool", rps_loc.update)
            rps_exh.register(u_ps, "ex_hcool", rps_exh.update)

            --#endregion

            --#region Dynamic Tank Tabs

            local next_tank = 1

            for id = 1, #fac.tank_list do
                if fac.tank_list[id] == 2 then
                    local tank_pane = Div{parent=page_div}
                    tank_pages[next_tank] = dyn_tank(app, f_page, panes, tank_pane, id, fac.tank_ps_tbl[next_tank], update)
                    next_tank = next_tank + 1
                end
            end

            --#endregion

            util.nop()
        end

        -- setup multipane
        local f_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(f_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = "FAC", color = core.cpair(colors.black, colors.orange), callback = f_annunc.nav_to },
            { label = "MTX", color = core.cpair(colors.black, colors.white), callback = mtx_page.nav_to },
            { label = "SPS", color = core.cpair(colors.black, colors.purple), callback = sps_page.nav_to },
            { label = "TNK", tall = true, color = core.cpair(colors.white, colors.gray), callback = tank_page.nav_to }
        }

        for i = 1, #fac.tank_data_tbl do
            table.insert(list, { label = "F-" .. i, color = core.cpair(colors.black, colors.lightGray), callback = tank_pages[i] })
        end

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
