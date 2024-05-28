--
-- Unit Overview Page
--

local types     = require("scada-common.types")
local util      = require("scada-common.util")
-- local log       = require("scada-common.log")

local iocontrol = require("pocket.iocontrol")

local core      = require("graphics.core")

local Div       = require("graphics.elements.div")
local ListBox   = require("graphics.elements.listbox")
local MultiPane = require("graphics.elements.multipane")
local TextBox   = require("graphics.elements.textbox")

local DataIndicator     = require("graphics.elements.indicators.data")
local IconIndicator     = require("graphics.elements.indicators.icon")
-- local RadIndicator      = require("graphics.elements.indicators.rad")
local VerticalBar       = require("graphics.elements.indicators.vbar")

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
    local label = cpair(colors.lightGray, colors.black)

    local nav_links = {}

    local function set_sidebar(id)
        -- local unit = db.units[id] ---@type pioctl_unit

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = function () db.nav.open_app(iocontrol.APP_ID.ROOT) end },
            { label = "U-" .. id, color = core.cpair(colors.black, colors.yellow), callback = function () app.switcher(id) end },
            { label = " \x13 ", color = core.cpair(colors.black, colors.red), callback = nav_links[id].alarm },
            { label = "RPS", tall = true, color = core.cpair(colors.black, colors.cyan), callback = nav_links[id].rps },
            { label = " R ", color = core.cpair(colors.black, colors.lightGray), callback = nav_links[id].reactor  },
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
        local page_div = Div{parent=main,y=2,width=main.get_width()}

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
            local u_pane = panes[i]
            local u_div = Div{parent=u_pane,x=2,width=main.get_width()-2}
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

            --#region Alarms Tab

            local alm_div = Div{parent=page_div}
            table.insert(panes, alm_div)

            local alm_page = app.new_page(u_page, #panes)
            alm_page.tasks = { update }
            nav_links[i].alarm = alm_page.nav_to

            TextBox{parent=alm_div,y=1,text="Status Info Display",height=1,alignment=ALIGN.CENTER}

            local ecam_disp = ListBox{parent=alm_div,x=2,y=3,scroll_height=100,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}

            ecam_disp.register(u_ps, "U_ECAM", function (data)
                local ecam = textutils.unserialize(data)

                ecam_disp.remove_all()
                for _, entry in ipairs(ecam) do
                    local div = Div{parent=ecam_disp,height=1+#entry.items,fg_bg=cpair(entry.color,colors.black)}
                    local text = TextBox{parent=div,height=1,text=entry.text}

                    if entry.help then
                        PushButton{parent=div,x=21,y=text.get_y(),text="?",callback=function()db.nav.open_help(entry.help)end,fg_bg=cpair(colors.gray,colors.black)}
                    end

                    for _, item in ipairs(entry.items) do
                        local fg_bg = nil
                        if item.color then fg_bg = cpair(item.color, colors.black) end

                        text = TextBox{parent=div,x=3,height=1,text=item.text,fg_bg=fg_bg}

                        if item.help then
                            PushButton{parent=div,x=21,y=text.get_y(),text="?",callback=function()db.nav.open_help(item.help)end,fg_bg=cpair(colors.gray,colors.black)}
                        end
                    end

                    ecam_disp.line_break()
                end
            end)

            --#endregion

            --#region RPS Tab

            local rps_pane = Div{parent=page_div}
            local rps_div = Div{parent=rps_pane,x=2,width=main.get_width()-2}
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

            --#region Reactor Tab

            local rct_pane = Div{parent=page_div}
            local rct_div = Div{parent=rct_pane,x=2,width=main.get_width()-2}
            table.insert(panes, rct_div)

            local rct_page = app.new_page(u_page, #panes)
            rct_page.tasks = { update }
            nav_links[i].reactor = rct_page.nav_to

            TextBox{parent=rct_div,y=1,text="Fission Reactor",height=1,alignment=ALIGN.CENTER}

            local fuel  = VerticalBar{parent=rct_div,x=1,y=4,fg_bg=cpair(colors.lightGray,colors.gray),height=5,width=1}
            local ccool = VerticalBar{parent=rct_div,x=3,y=4,fg_bg=cpair(colors.blue,colors.gray),height=5,width=1}
            local hcool = VerticalBar{parent=rct_div,x=19,y=4,fg_bg=cpair(colors.white,colors.gray),height=5,width=1}
            local waste = VerticalBar{parent=rct_div,x=21,y=4,fg_bg=cpair(colors.brown,colors.gray),height=5,width=1}

            TextBox{parent=rct_div,text="F",x=1,y=3,width=1,height=1,fg_bg=label}
            TextBox{parent=rct_div,text="C",x=3,y=3,width=1,height=1,fg_bg=label}
            TextBox{parent=rct_div,text="H",x=19,y=3,width=1,height=1,fg_bg=label}
            TextBox{parent=rct_div,text="W",x=21,y=3,width=1,height=1,fg_bg=label}

            fuel.register(u_ps, "fuel_fill", fuel.update)
            ccool.register(u_ps, "ccool_fill", ccool.update)
            hcool.register(u_ps, "hcool_fill", hcool.update)
            waste.register(u_ps, "waste_fill", waste.update)

            ccool.register(u_ps, "ccool_type", function (type)
                if type == types.FLUID.SODIUM then
                    ccool.recolor(cpair(colors.lightBlue, colors.gray))
                else
                    ccool.recolor(cpair(colors.blue, colors.gray))
                end
            end)

            hcool.register(u_ps, "hcool_type", function (type)
                if type == types.FLUID.SUPERHEATED_SODIUM then
                    hcool.recolor(cpair(colors.orange, colors.gray))
                else
                    hcool.recolor(cpair(colors.white, colors.gray))
                end
            end)

            TextBox{parent=rct_div,text="Burn Rate",x=5,y=5,width=13,height=1,fg_bg=label}
            local burn_rate = DataIndicator{parent=rct_div,x=5,y=6,lu_colors=lu_col,label="",unit="mB/t",format="%8.2f",value=1024.99,commas=true,width=13,fg_bg=text_fg}
            TextBox{parent=rct_div,text="Temperature",x=5,y=7,width=13,height=1,fg_bg=label}
            local t_prec = util.trinary(db.temp_label == types.TEMP_SCALE_UNITS[types.TEMP_SCALE.KELVIN], 11, 10)
            local core_temp = DataIndicator{parent=rct_div,x=5,y=8,lu_colors=lu_col,label="",unit=db.temp_label,format="%"..t_prec..".2f",value=17802.03,commas=true,width=13,fg_bg=text_fg}

            local r_state = IconIndicator{parent=rct_div,x=7,y=3,label="State",states=mode_states}

            burn_rate.register(u_ps, "act_burn_rate", burn_rate.update)
            core_temp.register(u_ps, "temp", function (t) core_temp.update(db.temp_convert(t)) end)
            r_state.register(u_ps, "U_ControlStatus", r_state.update)

            local r_temp = IconIndicator{parent=rct_div,y=10,label="Reactor Temp. Hi",states=red_ind_s}
            local r_rhdt = IconIndicator{parent=rct_div,label="Hi Delta Temp.",states=yel_ind_s}
            local r_firl = IconIndicator{parent=rct_div,label="Fuel Rate Lo",states=yel_ind_s}
            local r_wloc = IconIndicator{parent=rct_div,label="Waste Line Occl.",states=yel_ind_s}
            local r_hsrt = IconIndicator{parent=rct_div,label="Hi Startup Rate",states=yel_ind_s}

            r_temp.register(u_ps, "ReactorTempHigh", r_temp.update)
            r_rhdt.register(u_ps, "ReactorHighDeltaT", r_rhdt.update)
            r_firl.register(u_ps, "FuelInputRateLow", r_firl.update)
            r_wloc.register(u_ps, "WasteLineOcclusion", r_wloc.update)
            r_hsrt.register(u_ps, "HighStartupRate", r_hsrt.update)

            TextBox{parent=rct_div,text="HR",x=1,y=16,width=4,height=1,fg_bg=label}
            local heating_r = DataIndicator{parent=rct_div,x=6,y=16,lu_colors=lu_col,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=text_fg}
            TextBox{parent=rct_div,text="DMG",x=1,y=17,width=4,height=1,fg_bg=label}
            local damage_p = DataIndicator{parent=rct_div,x=6,y=17,lu_colors=lu_col,label="",unit="%",format="%11.2f",value=0,width=16,fg_bg=text_fg}

            heating_r.register(u_ps, "heating_rate", heating_r.update)
            damage_p.register(u_ps, "damage", damage_p.update)

            local rct_ext_div = Div{parent=rct_pane,x=2,width=main.get_width()-2}
            table.insert(panes, rct_ext_div)

            local rct_ext_page = app.new_page(rct_page, #panes)
            rct_ext_page.tasks = { update }

            PushButton{parent=rct_div,x=9,y=18,text="MORE",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=rct_ext_page.nav_to}
            PushButton{parent=rct_ext_div,x=9,y=18,text="BACK",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=rct_page.nav_to}

            TextBox{parent=rct_ext_div,y=1,text="More Reactor Info",height=1,alignment=ALIGN.CENTER}

            TextBox{parent=rct_ext_div,text="Fuel Tank",x=1,y=3,width=9,height=1,fg_bg=label}
            local fuel_p = DataIndicator{parent=rct_ext_div,x=14,y=3,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
            local fuel_amnt = DataIndicator{parent=rct_ext_div,x=1,y=4,lu_colors=lu_col,label="",unit="mB/t",format="%16.0f",value=0,commas=true,width=21,fg_bg=text_fg}

            fuel_p.register(u_ps, "fuel_fill", function (x) fuel_p.update(x * 100) end)
            fuel_amnt.register(u_ps, "fuel", fuel_amnt.update)

            TextBox{parent=rct_ext_div,text="Cool Coolant",x=1,y=6,width=12,height=1,fg_bg=label}
            local cooled_p = DataIndicator{parent=rct_ext_div,x=14,y=6,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
            local ccool_amnt = DataIndicator{parent=rct_ext_div,x=1,y=7,lu_colors=lu_col,label="",unit="mB/t",format="%16.0f",value=0,commas=true,width=21,fg_bg=text_fg}

            cooled_p.register(u_ps, "ccool_fill", function (x) cooled_p.update(x * 100) end)
            ccool_amnt.register(u_ps, "ccool_amnt", ccool_amnt.update)

            TextBox{parent=rct_ext_div,text="Hot Coolant",x=1,y=9,width=12,height=1,fg_bg=label}
            local heated_p = DataIndicator{parent=rct_ext_div,x=14,y=9,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
            local hcool_amnt = DataIndicator{parent=rct_ext_div,x=1,y=10,lu_colors=lu_col,label="",unit="mB/t",format="%16.0f",value=0,commas=true,width=21,fg_bg=text_fg}

            heated_p.register(u_ps, "hcool_fill", function (x) heated_p.update(x * 100) end)
            hcool_amnt.register(u_ps, "hcool_amnt", hcool_amnt.update)

            TextBox{parent=rct_ext_div,text="Waste Tank",x=1,y=12,width=10,height=1,fg_bg=label}
            local waste_p = DataIndicator{parent=rct_ext_div,x=14,y=12,lu_colors=lu_col,label="",unit="%",format="%6.2f",value=0,width=8,fg_bg=text_fg}
            local waste_amnt = DataIndicator{parent=rct_ext_div,x=1,y=13,lu_colors=lu_col,label="",unit="mB/t",format="%16.0f",value=0,commas=true,width=21,fg_bg=text_fg}

            waste_p.register(u_ps, "waste_fill", function (x) waste_p.update(x * 100) end)
            waste_amnt.register(u_ps, "waste", waste_amnt.update)

            TextBox{parent=rct_ext_div,text="Boil Eff.",x=1,y=15,width=9,height=1,fg_bg=label}
            TextBox{parent=rct_ext_div,text="Env. Loss",x=1,y=16,width=9,height=1,fg_bg=label}
            local boil_eff = DataIndicator{parent=rct_ext_div,x=11,y=15,lu_colors=lu_col,label="",unit="%",format="%9.2f",value=0,width=11,fg_bg=text_fg}
            local env_loss = DataIndicator{parent=rct_ext_div,x=11,y=16,lu_colors=lu_col,label="",unit="",format="%11.8f",value=0,width=11,fg_bg=text_fg}

            boil_eff.register(u_ps, "boil_eff", function (x) boil_eff.update(x * 100) end)
            env_loss.register(u_ps, "env_loss", env_loss.update)

            --#endregion

            --#region RCS Tab

            local rcs_pane = Div{parent=page_div}
            local rcs_div = Div{parent=rcs_pane,x=2,width=main.get_width()-2}
            table.insert(panes, rcs_pane)

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
