--
-- Unit Overview Page
--

local util      = require("scada-common.util")
-- local log       = require("scada-common.log")

local iocontrol = require("pocket.iocontrol")

local core      = require("graphics.core")

local Div       = require("graphics.elements.div")
local MultiPane = require("graphics.elements.multipane")
local TextBox   = require("graphics.elements.textbox")

local DataIndicator     = require("graphics.elements.indicators.data")
local IconIndicator     = require("graphics.elements.indicators.icon")
-- local RadIndicator      = require("graphics.elements.indicators.rad")
-- local VerticalBar       = require("graphics.elements.indicators.vbar")

local PushButton        = require("graphics.elements.controls.push_button")

local ALIGN = core.ALIGN
local cpair = core.cpair

local basic_states = {
    { color = cpair(colors.black, colors.lightGray), symbol = "\x07" },
    { color = cpair(colors.black, colors.red), symbol = "-" },
    { color = cpair(colors.black, colors.yellow), symbol = "\x1e" },
    { color = cpair(colors.black, colors.green), symbol = "+" }
}

local mode_states = {
    { color = cpair(colors.black, colors.lightGray), symbol = "\x07" },
    { color = cpair(colors.black, colors.red), symbol = "-" },
    { color = cpair(colors.black, colors.green), symbol = "+" },
    { color = cpair(colors.black, colors.purple), symbol = "A" }
}

local emc_ind_s = {
    { color = cpair(colors.black, colors.gray), symbol = "-" },
    { color = cpair(colors.black, colors.white), symbol = "\x07" },
    { color = cpair(colors.black, colors.green), symbol = "+" }
}

local red_ind_s = {
    { color = cpair(colors.black, colors.lightGray), symbol = "+" },
    { color = cpair(colors.black, colors.red), symbol = "-" }
}

local yel_ind_s = {
    { color = cpair(colors.black, colors.lightGray), symbol = "+" },
    { color = cpair(colors.black, colors.yellow), symbol = "-" }
}

-- new unit page view
---@param root graphics_element parent
local function new_view(root)
    local db = iocontrol.get_db()

    local main = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(iocontrol.APP_ID.UNITS, main)

    TextBox{parent=main,y=2,text="Units App",height=1,alignment=ALIGN.CENTER}

    TextBox{parent=main,y=4,text="Loading...",height=1,alignment=ALIGN.CENTER}

    local btn_fg_bg = cpair(colors.yellow, colors.black)
    local btn_active = cpair(colors.white, colors.black)
    -- local label = cpair(colors.lightGray, colors.black)

    local nav_links = {}

    local function set_sidebar(id)
        -- local unit = db.units[id] ---@type pioctl_unit

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = function () db.nav.open_app(iocontrol.APP_ID.ROOT) end },
            { label = "U-" .. id, color = core.cpair(colors.black, colors.yellow), callback = function () app.switcher(id) end },
            { label = " \x13 ", color = core.cpair(colors.black, colors.red), callback = nav_links[id].alarm },
            { label = "RPS", tall = true, color = core.cpair(colors.black, colors.cyan), callback = nav_links[id].rps },
            -- { label = " R ", color = core.cpair(colors.black, colors.lightGray), callback = function () end },
            { label = "RCS", tall = true, color = core.cpair(colors.black, colors.blue), callback = nav_links[id].rcs },
        }

        -- for i = 1, unit.num_boilers do
        --     table.insert(list, { label = "B-" .. i, color = core.cpair(colors.black, colors.lightBlue), callback = function () end })
        -- end

        -- for i = 1, unit.num_turbines do
        --     table.insert(list, { label = "T-" .. i, color = core.cpair(colors.black, colors.white), callback = function () end })
        -- end

        app.set_sidebar(list)
    end

    local function load()
        local page_div = Div{parent=main,x=2,y=2,width=main.get_width()-2}

        local panes = {}

        local active_unit = 1

        -- create all page divs
        for _ = 1, db.facility.num_units do
            local div = Div{parent=page_div}
            table.insert(panes, div)
            table.insert(nav_links, {})
        end

        -- previous unit
        local function prev(x)
            active_unit = util.trinary(x == 1, db.facility.num_units, x - 1)
            app.switcher(active_unit)
            set_sidebar(active_unit)
        end

        -- next unit
        local function next(x)
            active_unit = util.trinary(x == db.facility.num_units, 1, x + 1)
            app.switcher(active_unit)
            set_sidebar(active_unit)
        end

        for i = 1, db.facility.num_units do
            local u_div = panes[i] ---@type graphics_element
            local unit = db.units[i] ---@type pioctl_unit
            local u_ps = unit.unit_ps

            -- refresh data callback, every 500ms it will re-send the query
            local last_update = 0
            local function update()
                if util.time_ms() - last_update >= 500 then
                    db.api.get_unit(i)
                    last_update = util.time_ms()
                end
            end

            --#region Main Unit Overview

            local u_page = app.new_page(nil, i)
            u_page.tasks = { update }

            TextBox{parent=u_div,y=1,text="Reactor Unit #"..i,height=1,alignment=ALIGN.CENTER}
            PushButton{parent=u_div,x=1,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()prev(i)end}
            PushButton{parent=u_div,x=21,y=1,text=">",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()next(i)end}

            local type = util.trinary(unit.num_boilers > 0, "Sodium Cooled Reactor", "Boiling Water Reactor")
            TextBox{parent=u_div,y=3,text=type,height=1,alignment=ALIGN.CENTER,fg_bg=cpair(colors.gray,colors.black)}

            local lu_col = cpair(colors.lightGray, colors.lightGray)
            local text_fg = cpair(colors.white, colors._INHERIT)

            local rate = DataIndicator{parent=u_div,y=5,lu_colors=lu_col,label="Rate",unit="mB/t",format="%10.2f",value=0,commas=true,width=26,fg_bg=text_fg}
            local temp = DataIndicator{parent=u_div,lu_colors=lu_col,label="Temp",unit="K",format="%10.2f",value=0,commas=true,width=26,fg_bg=text_fg}

            local ctrl = IconIndicator{parent=u_div,x=1,y=8,label="Control State",states=mode_states}

            rate.register(u_ps, "act_burn_rate", rate.update)
            temp.register(u_ps, "temp", temp.update)
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

            --#region Alarms Tab

            local alm_div = Div{parent=page_div}
            table.insert(panes, alm_div)

            local alm_page = app.new_page(u_page, #panes)
            alm_page.tasks = { update }

            nav_links[i].alarm = alm_page.nav_to

            TextBox{parent=alm_div,y=1,text="Unit Alarms",height=1,alignment=ALIGN.CENTER}

            TextBox{parent=alm_div,y=3,text="work in progress",height=1,alignment=ALIGN.CENTER,fg_bg=cpair(colors.gray,colors.black)}

            --#endregion

            --#region RPS Tab

            local rps_div = Div{parent=page_div}
            table.insert(panes, rps_div)

            local rps_page = app.new_page(u_page, #panes)
            rps_page.tasks = { update }

            nav_links[i].rps = rps_page.nav_to

            TextBox{parent=rps_div,y=1,text="Protection System",height=1,alignment=ALIGN.CENTER}

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

            --#region RCS Tab

            local rcs_div = Div{parent=page_div}
            table.insert(panes, rcs_div)

            local rcs_page = app.new_page(u_page, #panes)
            rcs_page.tasks = { update }

            nav_links[i].rcs = rcs_page.nav_to

            TextBox{parent=rcs_div,y=1,text="Coolant System",height=1,alignment=ALIGN.CENTER}

            local r_rtrip = IconIndicator{parent=rcs_div,y=3,label="RCP Trip",states=red_ind_s}
            local r_cflow = IconIndicator{parent=rcs_div,label="RCS Flow Lo",states=yel_ind_s}
            local r_clow  = IconIndicator{parent=rcs_div,label="Coolant Level Lo",states=yel_ind_s}

            r_rtrip.register(u_ps, "RCPTrip", r_rtrip.update)
            r_cflow.register(u_ps, "RCSFlowLow", r_cflow.update)
            r_clow.register(u_ps, "CoolantLevelLow", r_clow.update)

            local c_flt  = IconIndicator{parent=rcs_div,label="RCS HW Fault",states=yel_ind_s}
            local c_emg  = IconIndicator{parent=rcs_div,label="Emergency Coolant",states=emc_ind_s}
            local c_mwrf = IconIndicator{parent=rcs_div,label="Max Water Return",states=yel_ind_s}

            c_flt.register(u_ps, "RCSFault", c_flt.update)
            c_emg.register(u_ps, "EmergencyCoolant", c_emg.update)
            c_mwrf.register(u_ps, "MaxWaterReturnFeed", c_mwrf.update)

            -- rcs_div.line_break()
            -- TextBox{parent=rcs_div,text="Mismatches",height=1,alignment=ALIGN.CENTER,fg_bg=label}
            local c_cfm = IconIndicator{parent=rcs_div,label="Coolant Feed",states=yel_ind_s}
            local c_brm = IconIndicator{parent=rcs_div,label="Boil Rate",states=yel_ind_s}
            local c_sfm = IconIndicator{parent=rcs_div,label="Steam Feed",states=yel_ind_s}

            c_cfm.register(u_ps, "CoolantFeedMismatch", c_cfm.update)
            c_brm.register(u_ps, "BoilRateMismatch", c_brm.update)
            c_sfm.register(u_ps, "SteamFeedMismatch", c_sfm.update)

            rcs_div.line_break()
            -- TextBox{parent=rcs_div,text="Aggregate Checks",height=1,alignment=ALIGN.CENTER,fg_bg=label}

            if unit.num_boilers > 0 then
                local wll = IconIndicator{parent=rcs_div,label="Boiler Water Lo",states=red_ind_s}
                local hrl = IconIndicator{parent=rcs_div,label="Heating Rate Lo",states=yel_ind_s}

                wll.register(u_ps, "U_WaterLevelLow", wll.update)
                hrl.register(u_ps, "U_HeatingRateLow", hrl.update)
            end

            local tospd = IconIndicator{parent=rcs_div,label="TRB Over Speed",states=red_ind_s}
            local gtrip = IconIndicator{parent=rcs_div,label="Generator Trip",states=yel_ind_s}
            local ttrip = IconIndicator{parent=rcs_div,label="Turbine Trip",states=red_ind_s}

            tospd.register(u_ps, "U_TurbineOverSpeed", tospd.update)
            gtrip.register(u_ps, "U_GeneratorTrip", gtrip.update)
            ttrip.register(u_ps, "U_TurbineTrip", ttrip.update)

            --#endregion
        end

        -- setup multipane
        local u_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(u_pane)

        set_sidebar(active_unit)
    end

    app.set_on_load(load)

    return main
end

return new_view
