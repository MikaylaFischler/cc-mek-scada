--
-- Process Control App
--

local types         = require("scada-common.types")
local util          = require("scada-common.util")

local iocontrol     = require("pocket.iocontrol")
local pocket        = require("pocket.pocket")
local process       = require("pocket.process")

local style         = require("pocket.ui.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local MultiPane     = require("graphics.elements.MultiPane")
local Rectangle     = require("graphics.elements.Rectangle")
local TextBox       = require("graphics.elements.TextBox")

local WaitingAnim   = require("graphics.elements.animations.Waiting")

local HazardButton  = require("graphics.elements.controls.HazardButton")
local RadioButton   = require("graphics.elements.controls.RadioButton")

local NumberField   = require("graphics.elements.form.NumberField")

local IconIndicator = require("graphics.elements.indicators.IconIndicator")

local ALIGN  = core.ALIGN
local cpair  = core.cpair
local border = core.border

local APP_ID = pocket.APP_ID

local label_fg_bg     = style.label
local text_fg         = style.text_fg

local field_fg_bg     = style.field
local field_dis_fg_bg = style.field_disable

local red_ind_s       = style.icon_states.red_ind_s
local yel_ind_s       = style.icon_states.yel_ind_s
local grn_ind_s       = style.icon_states.grn_ind_s
local wht_ind_s       = style.icon_states.wht_ind_s

local hzd_fg_bg       = style.hzd_fg_bg
local dis_colors      = cpair(colors.white, colors.lightGray)

-- new process control page view
---@param root Container parent
local function new_view(root)
    local db = iocontrol.get_db()

    local frame = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(APP_ID.PROCESS, frame, nil, false, true)

    local load_div = Div{parent=frame,x=1,y=1}
    local main = Div{parent=frame,x=1,y=1}

    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.purple,colors._INHERIT)}

    local load_pane = MultiPane{parent=main,x=1,y=1,panes={load_div,main}}

    app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })

    local page_div = nil ---@type Div|nil

    -- load the app (create the elements)
    local function load()
        local f_ps = db.facility.ps

        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {} ---@type Div[]

        -- create all page divs
        for _ = 1, db.facility.num_units + 3 do
            local div = Div{parent=page_div}
            table.insert(panes, div)
        end

        local last_update = 0
        -- refresh data callback, every 500ms it will re-send the query
        local function update()
            if util.time_ms() - last_update >= 500 then
                db.api.get_proc()
                last_update = util.time_ms()
            end
        end

        --#region unit settings/status

        local rate_limits = {}  ---@type NumberField[]

        for i = 1, db.facility.num_units do
            local u_pane = panes[i]
            local u_div = Div{parent=u_pane,x=2,width=main.get_width()-2}
            local unit = db.units[i]
            local u_ps = unit.unit_ps

            local u_page = app.new_page(nil, i)
            u_page.tasks = { update }

            TextBox{parent=u_div,y=1,text="Reactor Unit #"..i,alignment=ALIGN.CENTER}

            TextBox{parent=u_div,y=3,text="Auto Rate Limit",fg_bg=label_fg_bg}
            rate_limits[i] = NumberField{parent=u_div,x=1,y=4,width=16,default=0.01,min=0.01,max_frac_digits=2,max_chars=8,allow_decimal=true,align_right=true,fg_bg=field_fg_bg,dis_fg_bg=field_dis_fg_bg}
            TextBox{parent=u_div,x=18,y=4,text="mB/t",width=4,fg_bg=label_fg_bg}

            rate_limits[i].register(unit.unit_ps, "max_burn", rate_limits[i].set_max)
            rate_limits[i].register(unit.unit_ps, "burn_limit", rate_limits[i].set_value)

            local ready    = IconIndicator{parent=u_div,y=6,label="Auto Ready",states=grn_ind_s}
            local a_stb    = IconIndicator{parent=u_div,label="Auto Standby",states=wht_ind_s}
            local degraded = IconIndicator{parent=u_div,label="Unit Degraded",states=red_ind_s}

            ready.register(u_ps, "U_AutoReady", ready.update)
            degraded.register(u_ps, "U_AutoDegraded", degraded.update)

            -- update standby indicator
            a_stb.register(u_ps, "status", function (active)
                a_stb.update(unit.annunciator.AutoControl and (not active))
            end)
            a_stb.register(u_ps, "AutoControl", function (auto_active)
                if auto_active then
                    a_stb.update(unit.reactor_data.mek_status.status == false)
                else a_stb.update(false) end
            end)

            local function _set_group(value) process.set_group(i, value - 1) end

            local group = RadioButton{parent=u_div,y=10,options=types.AUTO_GROUP_NAMES,callback=_set_group,radio_colors=cpair(colors.lightGray,colors.gray),select_color=colors.purple,dis_fg_bg=style.btn_disable}

            -- can't change group if auto is engaged regardless of if this unit is part of auto control
            group.register(f_ps, "auto_active", function (auto_active)
                if auto_active then group.disable() else group.enable() end
            end)

            group.register(u_ps, "auto_group_id", function (gid) group.set_value(gid + 1) end)

            TextBox{parent=u_div,y=16,text="Assigned Group",fg_bg=style.label}
            local auto_grp = TextBox{parent=u_div,text="Manual",width=11,fg_bg=text_fg}

            auto_grp.register(u_ps, "auto_group", auto_grp.set_value)

            util.nop()
        end

        --#endregion

        --#region process control options page

        local o_pane = panes[db.facility.num_units + 2]
        local o_div = Div{parent=o_pane,x=2,width=main.get_width()-2}

        local opt_page = app.new_page(nil, db.facility.num_units + 2)
        opt_page.tasks = { update }

        TextBox{parent=o_div,y=1,text="Process Options",alignment=ALIGN.CENTER}

        local ctl_opts = { "Monitored Max Burn", "Combined Burn Rate", "Charge Level", "Generation Rate" }
        local mode = RadioButton{parent=o_div,x=1,y=3,options=ctl_opts,callback=function()end,radio_colors=cpair(colors.lightGray,colors.gray),select_color=colors.purple,dis_fg_bg=style.btn_disable}

        mode.register(f_ps, "process_mode", mode.set_value)

        TextBox{parent=o_div,y=9,text="Burn Rate Target",fg_bg=label_fg_bg}
        local b_target = NumberField{parent=o_div,x=1,y=10,width=15,default=0.01,min=0.01,max_frac_digits=2,max_chars=8,allow_decimal=true,align_right=true,fg_bg=field_fg_bg,dis_fg_bg=field_dis_fg_bg}
        TextBox{parent=o_div,x=17,y=10,text="mB/t",fg_bg=label_fg_bg}

        TextBox{parent=o_div,y=12,text="Charge Level Target",fg_bg=label_fg_bg}
        local c_target = NumberField{parent=o_div,x=1,y=13,width=15,default=0,min=0,max_chars=16,align_right=true,fg_bg=field_fg_bg,dis_fg_bg=field_dis_fg_bg}
        TextBox{parent=o_div,x=17,y=13,text="M"..db.energy_label,fg_bg=label_fg_bg}

        TextBox{parent=o_div,y=15,text="Generation Target",fg_bg=label_fg_bg}
        local g_target = NumberField{parent=o_div,x=1,y=16,width=15,default=0,min=0,max_chars=16,align_right=true,fg_bg=field_fg_bg,dis_fg_bg=field_dis_fg_bg}
        TextBox{parent=o_div,x=17,y=16,text="k"..db.energy_label.."/t",fg_bg=label_fg_bg}

        b_target.register(f_ps, "process_burn_target", b_target.set_value)
        c_target.register(f_ps, "process_charge_target", c_target.set_value)
        g_target.register(f_ps, "process_gen_target", g_target.set_value)

        --#endregion

        --#region process control page

        local c_pane = panes[db.facility.num_units + 1]
        local c_div = Div{parent=c_pane,x=2,width=main.get_width()-2}

        local proc_ctrl = app.new_page(nil, db.facility.num_units + 1)
        proc_ctrl.tasks = { update }

        TextBox{parent=c_div,y=1,text="Process Control",alignment=ALIGN.CENTER}

        local u_stat = Rectangle{parent=c_div,border=border(1,colors.gray,true),thin=true,width=21,height=5,x=1,y=3,fg_bg=cpair(colors.black,colors.lightGray)}
        local stat_line_1 = TextBox{parent=u_stat,x=1,y=1,text="UNKNOWN",alignment=ALIGN.CENTER}
        local stat_line_2 = TextBox{parent=u_stat,x=1,y=2,text="awaiting data...",height=2,alignment=ALIGN.CENTER,trim_whitespace=true,fg_bg=cpair(colors.gray,colors.lightGray)}

        stat_line_1.register(f_ps, "status_line_1", stat_line_1.set_value)
        stat_line_2.register(f_ps, "status_line_2", stat_line_2.set_value)

        local function _start_auto()
            local limits = {}
            for i = 1, #rate_limits do limits[i] = rate_limits[i].get_numeric() end

            process.process_start(mode.get_value(), b_target.get_numeric(), db.energy_convert_to_fe(c_target.get_numeric()),
                                  db.energy_convert_to_fe(g_target.get_numeric()), limits)
        end

        local start = HazardButton{parent=c_div,x=2,y=9,text="START",accent=colors.lightBlue,callback=_start_auto,timeout=3,fg_bg=hzd_fg_bg,dis_colors=dis_colors}
        local stop = HazardButton{parent=c_div,x=13,y=9,text="STOP",accent=colors.red,callback=process.process_stop,timeout=3,fg_bg=hzd_fg_bg,dis_colors=dis_colors}

        db.facility.start_ack = start.on_response
        db.facility.stop_ack = stop.on_response

        start.register(f_ps, "auto_ready", function (ready)
            if ready and (not db.facility.auto_active) then start.enable() else start.disable() end
        end)

        local auto_ready = IconIndicator{parent=c_div,y=14,label="Units Ready",states=grn_ind_s}
        local auto_act   = IconIndicator{parent=c_div,label="Process Active",states=grn_ind_s}
        local auto_ramp  = IconIndicator{parent=c_div,label="Process Ramping",states=wht_ind_s}
        local auto_sat   = IconIndicator{parent=c_div,label="Min/Max Burn Rate",states=yel_ind_s}

        auto_ready.register(f_ps, "auto_ready", auto_ready.update)
        auto_act.register(f_ps, "auto_active", auto_act.update)
        auto_ramp.register(f_ps, "auto_ramping", auto_ramp.update)
        auto_sat.register(f_ps, "auto_saturated", auto_sat.update)

        -- REGISTER_NOTE: for optimization/brevity, due to not deleting anything but the whole element tree
        -- when it comes to unloading the process app, child elements will not directly be registered here
        -- (preventing garbage collection until the parent 'page_div' is deleted)
        page_div.register(f_ps, "auto_active", function (active)
            if active then
                b_target.disable()
                c_target.disable()
                g_target.disable()

                mode.disable()
                start.disable()

                for i = 1, #rate_limits do rate_limits[i].disable() end
            else
                b_target.enable()
                c_target.enable()
                g_target.enable()

                mode.enable()
                if db.facility.auto_ready then start.enable() end

                for i = 1, #rate_limits do rate_limits[i].enable() end
            end
        end)

        --#endregion

        --#region auto-SCRAM annunciator page

        local a_pane = panes[db.facility.num_units + 3]
        local a_div = Div{parent=a_pane,x=2,width=main.get_width()-2}

        local annunc_page = app.new_page(nil, db.facility.num_units + 3)
        annunc_page.tasks = { update }

        TextBox{parent=a_div,y=1,text="Automatic SCRAM",alignment=ALIGN.CENTER}

        local auto_scram = IconIndicator{parent=a_div,y=3,label="Automatic SCRAM",states=red_ind_s}

        TextBox{parent=a_div,y=5,text="Induction Matrix",fg_bg=label_fg_bg}
        local matrix_flt  = IconIndicator{parent=a_div,label="Matrix Fault",states=yel_ind_s}
        local matrix_fill = IconIndicator{parent=a_div,label="Charge High",states=red_ind_s}

        TextBox{parent=a_div,y=9,text="Assigned Units",fg_bg=label_fg_bg}
        local unit_crit = IconIndicator{parent=a_div,label="Critical Alarm",states=red_ind_s}

        TextBox{parent=a_div,y=12,text="Facility",fg_bg=label_fg_bg}
        local fac_rad_h = IconIndicator{parent=a_div,label="Radiation High",states=red_ind_s}

        TextBox{parent=a_div,y=15,text="Generation Rate Mode",fg_bg=label_fg_bg}
        local gen_fault = IconIndicator{parent=a_div,label="Control Fault",states=yel_ind_s}

        auto_scram.register(f_ps, "auto_scram", auto_scram.update)
        matrix_flt.register(f_ps, "as_matrix_fault", matrix_flt.update)
        matrix_fill.register(f_ps, "as_matrix_fill", matrix_fill.update)
        unit_crit.register(f_ps, "as_crit_alarm", unit_crit.update)
        fac_rad_h.register(f_ps, "as_radiation", fac_rad_h.update)
        gen_fault.register(f_ps, "as_gen_fault", gen_fault.update)

        --#endregion

        -- setup multipane
        local u_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(u_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = " \x17 ", color = core.cpair(colors.black, colors.purple), callback = proc_ctrl.nav_to },
            { label = " \x13 ", color = core.cpair(colors.black, colors.red), callback = annunc_page.nav_to },
            { label = "OPT", color = core.cpair(colors.black, colors.yellow), callback = opt_page.nav_to }
        }

        for i = 1, db.facility.num_units do
            table.insert(list, { label = "U-" .. i, color = core.cpair(colors.black, colors.lightGray), callback = function () app.switcher(i) end })
        end

        app.set_sidebar(list)

        -- done, show the app
        proc_ctrl.nav_to()
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
