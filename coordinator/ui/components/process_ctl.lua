local tcd               = require("scada-common.tcd")
local util              = require("scada-common.util")

local iocontrol         = require("coordinator.iocontrol")
local process           = require("coordinator.process")

local style             = require("coordinator.ui.style")

local core              = require("graphics.core")

local Div               = require("graphics.elements.div")
local Rectangle         = require("graphics.elements.rectangle")
local TextBox           = require("graphics.elements.textbox")

local DataIndicator     = require("graphics.elements.indicators.data")
local IndicatorLight    = require("graphics.elements.indicators.light")
local RadIndicator      = require("graphics.elements.indicators.rad")
local StateIndicator    = require("graphics.elements.indicators.state")
local TriIndicatorLight = require("graphics.elements.indicators.trilight")

local Checkbox          = require("graphics.elements.controls.checkbox")
local HazardButton      = require("graphics.elements.controls.hazard_button")
local RadioButton       = require("graphics.elements.controls.radio_button")
local SpinboxNumeric    = require("graphics.elements.controls.spinbox_numeric")

local ALIGN = core.ALIGN

local cpair = core.cpair
local border = core.border

local bw_fg_bg = style.bw_fg_bg

local period = core.flasher.PERIOD

-- new process control view
---@param root graphics_element parent
---@param x integer top left x
---@param y integer top left y
local function new_view(root, x, y)
    local s_hi_box = style.theme.highlight_box
    local s_field = style.theme.field_box

    local lu_cpair = style.lu_colors
    local hzd_fg_bg  = style.hzd_fg_bg
    local dis_colors = style.dis_colors
    local arrow_fg_bg = cpair(style.theme.label, s_hi_box.bkg)

    local ind_grn = style.ind_grn
    local ind_yel = style.ind_yel
    local ind_red = style.ind_red
    local ind_wht = style.ind_wht

    assert(root.get_height() >= (y + 24), "main display not of sufficient vertical resolution (add an additional row of monitors)")

    local black = cpair(colors.black, colors.black)
    local blk_brn = cpair(colors.black, colors.brown)
    local blk_pur = cpair(colors.black, colors.purple)

    local facility = iocontrol.get_db().facility
    local units = iocontrol.get_db().units

    local main = Div{parent=root,width=128,height=24,x=x,y=y}

    local scram = HazardButton{parent=main,x=1,y=1,text="FAC SCRAM",accent=colors.yellow,dis_colors=dis_colors,callback=process.fac_scram,fg_bg=hzd_fg_bg}
    local ack_a = HazardButton{parent=main,x=16,y=1,text="ACK \x13",accent=colors.orange,dis_colors=dis_colors,callback=process.fac_ack_alarms,fg_bg=hzd_fg_bg}

    facility.scram_ack = scram.on_response
    facility.ack_alarms_ack = ack_a.on_response

    local all_ok  = IndicatorLight{parent=main,y=5,label="Unit Systems Online",colors=ind_grn}
    local rad_mon = TriIndicatorLight{parent=main,label="Radiation Monitor",c1=style.ind_bkg,c2=ind_yel.fgd,c3=ind_grn.fgd}
    local ind_mat = IndicatorLight{parent=main,label="Induction Matrix",colors=ind_grn}
    local sps     = IndicatorLight{parent=main,label="SPS Connected",colors=ind_grn}

    all_ok.register(facility.ps, "all_sys_ok", all_ok.update)
    rad_mon.register(facility.ps, "rad_computed_status", rad_mon.update)
    ind_mat.register(facility.induction_ps_tbl[1], "computed_status", function (status) ind_mat.update(status > 1) end)
    sps.register(facility.sps_ps_tbl[1], "computed_status", function (status) sps.update(status > 1) end)

    main.line_break()

    local auto_ready = IndicatorLight{parent=main,label="Configured Units Ready",colors=ind_grn}
    local auto_act   = IndicatorLight{parent=main,label="Process Active",colors=ind_grn}
    local auto_ramp  = IndicatorLight{parent=main,label="Process Ramping",colors=ind_wht,flash=true,period=period.BLINK_250_MS}
    local auto_sat   = IndicatorLight{parent=main,label="Min/Max Burn Rate",colors=ind_yel}

    auto_ready.register(facility.ps, "auto_ready", auto_ready.update)
    auto_act.register(facility.ps, "auto_active", auto_act.update)
    auto_ramp.register(facility.ps, "auto_ramping", auto_ramp.update)
    auto_sat.register(facility.ps, "auto_saturated", auto_sat.update)

    main.line_break()

    local auto_scram  = IndicatorLight{parent=main,label="Automatic SCRAM",colors=ind_red,flash=true,period=period.BLINK_250_MS}
    local matrix_dc   = IndicatorLight{parent=main,label="Matrix Disconnected",colors=ind_yel,flash=true,period=period.BLINK_500_MS}
    local matrix_fill = IndicatorLight{parent=main,label="Matrix Charge High",colors=ind_red,flash=true,period=period.BLINK_500_MS}
    local unit_crit   = IndicatorLight{parent=main,label="Unit Critical Alarm",colors=ind_red,flash=true,period=period.BLINK_250_MS}
    local fac_rad_h   = IndicatorLight{parent=main,label="Facility Radiation High",colors=ind_red,flash=true,period=period.BLINK_250_MS}
    local gen_fault   = IndicatorLight{parent=main,label="Gen. Control Fault",colors=ind_yel,flash=true,period=period.BLINK_500_MS}

    auto_scram.register(facility.ps, "auto_scram", auto_scram.update)
    matrix_dc.register(facility.ps, "as_matrix_dc", matrix_dc.update)
    matrix_fill.register(facility.ps, "as_matrix_fill", matrix_fill.update)
    unit_crit.register(facility.ps, "as_crit_alarm", unit_crit.update)
    fac_rad_h.register(facility.ps, "as_radiation", fac_rad_h.update)
    gen_fault.register(facility.ps, "as_gen_fault", gen_fault.update)

    TextBox{parent=main,y=23,text="Radiation",height=1,width=13,fg_bg=style.label}
    local radiation = RadIndicator{parent=main,label="",format="%9.3f",lu_colors=lu_cpair,width=13,fg_bg=s_field}
    radiation.register(facility.ps, "radiation", radiation.update)

    TextBox{parent=main,x=15,y=23,text="Linked RTUs",height=1,width=11,fg_bg=style.label}
    local rtu_count = DataIndicator{parent=main,x=15,y=24,label="",format="%11d",value=0,lu_colors=lu_cpair,width=11,fg_bg=s_field}
    rtu_count.register(facility.ps, "rtu_count", rtu_count.update)

    ---------------------
    -- process control --
    ---------------------

    local proc = Div{parent=main,width=103,height=24,x=27,y=1}

    -----------------------------
    -- process control targets --
    -----------------------------

    local targets = Div{parent=proc,width=31,height=24,x=1,y=1}

    local burn_tag = Div{parent=targets,x=1,y=1,width=8,height=4,fg_bg=blk_pur}
    TextBox{parent=burn_tag,x=2,y=2,text="Burn Target",width=7,height=2}

    local burn_target = Div{parent=targets,x=9,y=1,width=23,height=3,fg_bg=s_hi_box}
    local b_target = SpinboxNumeric{parent=burn_target,x=11,y=1,whole_num_precision=4,fractional_precision=1,min=0.1,arrow_fg_bg=arrow_fg_bg,arrow_disable=style.theme.disabled}
    TextBox{parent=burn_target,x=18,y=2,text="mB/t",fg_bg=style.theme.label_fg}
    local burn_sum = DataIndicator{parent=targets,x=9,y=4,label="",format="%18.1f",value=0,unit="mB/t",commas=true,lu_colors=black,width=23,fg_bg=blk_brn}

    b_target.register(facility.ps, "process_burn_target", b_target.set_value)
    burn_sum.register(facility.ps, "burn_sum", burn_sum.update)

    local chg_tag = Div{parent=targets,x=1,y=6,width=8,height=4,fg_bg=blk_pur}
    TextBox{parent=chg_tag,x=2,y=2,text="Charge Target",width=7,height=2}

    local chg_target = Div{parent=targets,x=9,y=6,width=23,height=3,fg_bg=s_hi_box}
    local c_target = SpinboxNumeric{parent=chg_target,x=2,y=1,whole_num_precision=15,fractional_precision=0,min=0,arrow_fg_bg=arrow_fg_bg,arrow_disable=style.theme.disabled}
    TextBox{parent=chg_target,x=18,y=2,text="MFE",fg_bg=style.theme.label_fg}
    local cur_charge = DataIndicator{parent=targets,x=9,y=9,label="",format="%19d",value=0,unit="MFE",commas=true,lu_colors=black,width=23,fg_bg=blk_brn}

    c_target.register(facility.ps, "process_charge_target", c_target.set_value)
    cur_charge.register(facility.induction_ps_tbl[1], "avg_charge", function (fe) cur_charge.update(fe / 1000000) end)

    local gen_tag = Div{parent=targets,x=1,y=11,width=8,height=4,fg_bg=blk_pur}
    TextBox{parent=gen_tag,x=2,y=2,text="Gen. Target",width=7,height=2}

    local gen_target = Div{parent=targets,x=9,y=11,width=23,height=3,fg_bg=s_hi_box}
    local g_target = SpinboxNumeric{parent=gen_target,x=8,y=1,whole_num_precision=9,fractional_precision=0,min=0,arrow_fg_bg=arrow_fg_bg,arrow_disable=style.theme.disabled}
    TextBox{parent=gen_target,x=18,y=2,text="kFE/t",fg_bg=style.theme.label_fg}
    local cur_gen = DataIndicator{parent=targets,x=9,y=14,label="",format="%17d",value=0,unit="kFE/t",commas=true,lu_colors=black,width=23,fg_bg=blk_brn}

    g_target.register(facility.ps, "process_gen_target", g_target.set_value)
    cur_gen.register(facility.induction_ps_tbl[1], "last_input", function (j) cur_gen.update(util.round(util.joules_to_fe(j) / 1000)) end)

    -----------------
    -- unit limits --
    -----------------

    local limit_div = Div{parent=proc,width=21,height=19,x=34,y=6}

    local rate_limits = {}

    for i = 1, 4 do
        local unit
        local tag_fg_bg = cpair(style.theme.disabled, s_hi_box.bkg)
        local lim_fg_bg = cpair(style.theme.disabled, s_hi_box.bkg)
        local label_fg  = style.theme.disabled_fg
        local cur_fg_bg = cpair(style.theme.disabled, s_hi_box.bkg)
        local cur_lu    = style.theme.disabled

        if i <= facility.num_units then
            unit = units[i]   ---@type ioctl_unit
            tag_fg_bg = cpair(colors.black, colors.lightBlue)
            lim_fg_bg = s_hi_box
            label_fg  = style.theme.label_fg
            cur_fg_bg = blk_brn
            cur_lu    = colors.black
        end

        local _y = ((i - 1) * 5) + 1

        local unit_tag = Div{parent=limit_div,x=1,y=_y,width=8,height=4,fg_bg=tag_fg_bg}
        TextBox{parent=unit_tag,x=2,y=2,text="Unit "..i.." Limit",width=7,height=2}

        local lim_ctl = Div{parent=limit_div,x=9,y=_y,width=14,height=3,fg_bg=s_hi_box}
        local lim = SpinboxNumeric{parent=lim_ctl,x=2,y=1,whole_num_precision=4,fractional_precision=1,min=0.1,arrow_fg_bg=arrow_fg_bg,arrow_disable=style.theme.disabled,fg_bg=lim_fg_bg}
        TextBox{parent=lim_ctl,x=9,y=2,text="mB/t",width=4,height=1,fg_bg=label_fg}

        local cur_burn = DataIndicator{parent=limit_div,x=9,y=_y+3,label="",format="%7.1f",value=0,unit="mB/t",commas=false,lu_colors=cpair(cur_lu,cur_lu),width=14,fg_bg=cur_fg_bg}

        if i <= facility.num_units then
            rate_limits[i] = lim
            rate_limits[i].register(unit.unit_ps, "max_burn", rate_limits[i].set_max)
            rate_limits[i].register(unit.unit_ps, "burn_limit", rate_limits[i].set_value)

            cur_burn.register(unit.unit_ps, "act_burn_rate", cur_burn.update)
        else
            lim.disable()
        end
    end

    -------------------
    -- unit statuses --
    -------------------

    local stat_div = Div{parent=proc,width=22,height=24,x=57,y=6}

    for i = 1, 4 do
        local tag_fg_bg = cpair(style.theme.disabled, s_hi_box.bkg)
        local ind_fg_bg = cpair(style.theme.disabled, s_hi_box.bkg)
        local ind_off = style.theme.disabled

        if i <= facility.num_units then
            tag_fg_bg = cpair(colors.black, colors.cyan)
            ind_fg_bg = cpair(style.theme.text, s_hi_box.bkg)
            ind_off = style.ind_hi_box_bg
        end

        local _y = ((i - 1) * 5) + 1

        local unit_tag = Div{parent=stat_div,x=1,y=_y,width=8,height=4,fg_bg=tag_fg_bg}
        TextBox{parent=unit_tag,x=2,y=2,text="Unit "..i.." Status",width=7,height=2}

        local lights   = Div{parent=stat_div,x=9,y=_y,width=14,height=4,fg_bg=ind_fg_bg}
        local ready    = IndicatorLight{parent=lights,x=2,y=2,label="Ready",colors=cpair(ind_grn.fgd,ind_off)}
        local degraded = IndicatorLight{parent=lights,x=2,y=3,label="Degraded",colors=cpair(ind_red.fgd,ind_off),flash=true,period=period.BLINK_250_MS}

        if i <= facility.num_units then
            local unit = units[i]   ---@type ioctl_unit

            ready.register(unit.unit_ps, "U_AutoReady", ready.update)
            degraded.register(unit.unit_ps, "U_AutoDegraded", degraded.update)
        end
    end

    -------------------------
    -- controls and status --
    -------------------------

    local ctl_opts = { "Monitored Max Burn", "Combined Burn Rate", "Charge Level", "Generation Rate" }
    local mode = RadioButton{parent=proc,x=34,y=1,options=ctl_opts,callback=function()end,radio_colors=cpair(style.theme.accent_dark,style.theme.accent_light),select_color=colors.purple}

    mode.register(facility.ps, "process_mode", mode.set_value)

    local u_stat = Rectangle{parent=proc,border=border(1,colors.gray,true),thin=true,width=31,height=4,x=1,y=16,fg_bg=bw_fg_bg}
    local stat_line_1 = TextBox{parent=u_stat,x=1,y=1,text="UNKNOWN",width=31,height=1,alignment=ALIGN.CENTER,fg_bg=bw_fg_bg}
    local stat_line_2 = TextBox{parent=u_stat,x=1,y=2,text="awaiting data...",width=31,height=1,alignment=ALIGN.CENTER,fg_bg=cpair(colors.gray,colors.white)}

    stat_line_1.register(facility.ps, "status_line_1", stat_line_1.set_value)
    stat_line_2.register(facility.ps, "status_line_2", stat_line_2.set_value)

    local auto_controls = Div{parent=proc,x=1,y=20,width=31,height=5,fg_bg=s_hi_box}

    -- save the automatic process control configuration without starting
    local function _save_cfg()
        local limits = {}
        for i = 1, #rate_limits do limits[i] = rate_limits[i].get_value() end

        process.save(mode.get_value(), b_target.get_value(), c_target.get_value(), g_target.get_value(), limits)
    end

    -- start automatic control after saving process control settings
    local function _start_auto()
        _save_cfg()
        process.start_auto()
    end

    local save  = HazardButton{parent=auto_controls,x=2,y=2,text="SAVE",accent=colors.purple,dis_colors=dis_colors,callback=_save_cfg,fg_bg=hzd_fg_bg}
    local start = HazardButton{parent=auto_controls,x=13,y=2,text="START",accent=colors.lightBlue,dis_colors=dis_colors,callback=_start_auto,fg_bg=hzd_fg_bg}
    local stop  = HazardButton{parent=auto_controls,x=23,y=2,text="STOP",accent=colors.red,dis_colors=dis_colors,callback=process.stop_auto,fg_bg=hzd_fg_bg}

    facility.start_ack = start.on_response
    facility.stop_ack = stop.on_response

    function facility.save_cfg_ack(ack)
        tcd.dispatch(0.2, function () save.on_response(ack) end)
    end

    start.register(facility.ps, "auto_ready", function (ready)
        if ready and (not facility.auto_active) then start.enable() else start.disable() end
    end)

    -- REGISTER_NOTE: for optimization/brevity, due to not deleting anything but the whole element tree when it comes
    -- to the process control display and coordinator GUI as a whole, child elements will not directly be registered here
    -- (preventing garbage collection until the parent 'proc' is deleted)
    proc.register(facility.ps, "auto_active", function (active)
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
            if facility.auto_ready then start.enable() end

            for i = 1, #rate_limits do rate_limits[i].enable() end
        end
    end)

    ------------------------------
    -- waste production control --
    ------------------------------

    local waste_status = Div{parent=proc,width=24,height=4,x=57,y=1,}

    for i = 1, facility.num_units do
        local unit = units[i]   ---@type ioctl_unit

        TextBox{parent=waste_status,y=i,text="U"..i.." Waste",width=8,height=1}
        local a_waste = IndicatorLight{parent=waste_status,x=10,y=i,label="Auto",colors=ind_wht}
        local waste_m = StateIndicator{parent=waste_status,x=17,y=i,states=style.waste.states_abbrv,value=1,min_width=6}

        a_waste.register(unit.unit_ps, "U_AutoWaste", a_waste.update)
        waste_m.register(unit.unit_ps, "U_WasteProduct", waste_m.update)
    end

    local waste_sel = Div{parent=proc,width=21,height=24,x=81,y=1}

    local cutout_fg_bg = cpair(style.theme.bg, colors.brown)

    TextBox{parent=waste_sel,text=" ",width=21,height=1,x=1,y=1,fg_bg=cutout_fg_bg}
    TextBox{parent=waste_sel,text="WASTE PRODUCTION",alignment=ALIGN.CENTER,width=21,height=1,x=1,y=2,fg_bg=cutout_fg_bg}

    local rect   = Rectangle{parent=waste_sel,border=border(1,colors.brown,true),width=21,height=22,x=1,y=3}
    local status = StateIndicator{parent=rect,x=2,y=1,states=style.waste.states,value=1,min_width=17}

    status.register(facility.ps, "current_waste_product", status.update)

    local waste_prod = RadioButton{parent=rect,x=2,y=3,options=style.waste.options,callback=process.set_process_waste,radio_colors=cpair(style.theme.accent_dark,style.theme.accent_light),select_color=colors.brown}

    waste_prod.register(facility.ps, "process_waste_product", waste_prod.set_value)

    local fb_active = IndicatorLight{parent=rect,x=2,y=7,label="Fallback Active",colors=ind_wht}
    local sps_disabled  = IndicatorLight{parent=rect,x=2,y=8,label="SPS Disabled LC",colors=ind_yel}

    fb_active.register(facility.ps, "pu_fallback_active", fb_active.update)
    sps_disabled.register(facility.ps, "sps_disabled_low_power", sps_disabled.update)

    local pu_fallback = Checkbox{parent=rect,x=2,y=10,label="Pu Fallback",callback=process.set_pu_fallback,box_fg_bg=cpair(colors.brown,style.theme.checkbox_bg)}

    TextBox{parent=rect,x=2,y=12,height=3,text="Switch to Pu when SNAs cannot keep up with waste.",fg_bg=style.label}

    local lc_sps = Checkbox{parent=rect,x=2,y=16,label="Low Charge SPS",callback=process.set_sps_low_power,box_fg_bg=cpair(colors.brown,style.theme.checkbox_bg)}

    TextBox{parent=rect,x=2,y=18,height=3,text="Use SPS at low charge, otherwise switches to Po.",fg_bg=style.label}

    pu_fallback.register(facility.ps, "process_pu_fallback", pu_fallback.set_value)
    lc_sps.register(facility.ps, "process_sps_low_power", lc_sps.set_value)
end

return new_view
