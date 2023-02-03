local tcd               = require("scada-common.tcallbackdsp")
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
local TriIndicatorLight = require("graphics.elements.indicators.trilight")
local VerticalBar       = require("graphics.elements.indicators.vbar")

local HazardButton      = require("graphics.elements.controls.hazard_button")
local MultiButton       = require("graphics.elements.controls.multi_button")
local PushButton        = require("graphics.elements.controls.push_button")
local RadioButton       = require("graphics.elements.controls.radio_button")
local SpinboxNumeric    = require("graphics.elements.controls.spinbox_numeric")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border

local period = core.flasher.PERIOD

-- new process control view
---@param root graphics_element parent
---@param x integer top left x
---@param y integer top left y
local function new_view(root, x, y)
    local facility = iocontrol.get_db().facility
    local units = iocontrol.get_db().units

    local bw_fg_bg   = cpair(colors.black, colors.white)
    local hzd_fg_bg  = cpair(colors.white, colors.gray)
    local dis_colors = cpair(colors.white, colors.lightGray)

    local main = Div{parent=root,width=80,height=24,x=x,y=y}

    local scram = HazardButton{parent=main,x=1,y=1,text="FAC SCRAM",accent=colors.yellow,dis_colors=dis_colors,callback=process.fac_scram,fg_bg=hzd_fg_bg}

    facility.scram_ack = scram.on_response

    local auto_act   = IndicatorLight{parent=main,y=5,label="Auto Active",colors=cpair(colors.green,colors.gray)}
    local auto_ramp  = IndicatorLight{parent=main,label="Auto Ramping",colors=cpair(colors.white,colors.gray),flash=true,period=period.BLINK_250_MS}
    local auto_scram = IndicatorLight{parent=main,label="Auto SCRAM",colors=cpair(colors.red,colors.gray),flash=true,period=period.BLINK_250_MS}

    facility.ps.subscribe("auto_active", auto_act.update)
    facility.ps.subscribe("auto_ramping", auto_ramp.update)
    facility.ps.subscribe("auto_scram", auto_scram.update)

    main.line_break()

    local _ = IndicatorLight{parent=main,label="Unit Off-line",colors=cpair(colors.yellow,colors.gray),flash=true,period=period.BLINK_1000_MS}
    local _ = IndicatorLight{parent=main,label="Unit RPS Trip",colors=cpair(colors.red,colors.gray),flash=true,period=period.BLINK_250_MS}
    local _ = IndicatorLight{parent=main,label="Unit Critical Alarm",colors=cpair(colors.red,colors.gray),flash=true,period=period.BLINK_250_MS}
    local _ = IndicatorLight{parent=main,label="High Charge Level",colors=cpair(colors.red,colors.gray),flash=true,period=period.BLINK_250_MS}


    ---------------------
    -- process control --
    ---------------------

    local proc = Div{parent=main,width=54,height=24,x=27,y=1}

    -----------------------------
    -- process control targets --
    -----------------------------

    local targets = Div{parent=proc,width=31,height=24,x=1,y=1}

    local burn_tag = Div{parent=targets,x=1,y=1,width=8,height=4,fg_bg=cpair(colors.black,colors.purple)}
    TextBox{parent=burn_tag,x=2,y=2,text="Burn Target",width=7,height=2}

    local burn_target = Div{parent=targets,x=9,y=1,width=23,height=3,fg_bg=cpair(colors.gray,colors.white)}
    local b_target = SpinboxNumeric{parent=burn_target,x=11,y=1,whole_num_precision=4,fractional_precision=1,min=0.1,arrow_fg_bg=cpair(colors.gray,colors.white),fg_bg=bw_fg_bg}
    TextBox{parent=burn_target,x=18,y=2,text="mB/t"}
    local burn_sum = DataIndicator{parent=targets,x=9,y=4,label="",format="%18.1f",value=0,unit="mB/t",commas=true,lu_colors=cpair(colors.black,colors.black),width=23,fg_bg=cpair(colors.black,colors.brown)}

    facility.ps.subscribe("process_burn_target", b_target.set_value)
    facility.ps.subscribe("burn_sum", burn_sum.update)

    local chg_tag = Div{parent=targets,x=1,y=6,width=8,height=4,fg_bg=cpair(colors.black,colors.purple)}
    TextBox{parent=chg_tag,x=2,y=2,text="Charge Target",width=7,height=2}

    local chg_target = Div{parent=targets,x=9,y=6,width=23,height=3,fg_bg=cpair(colors.gray,colors.white)}
    local c_target = SpinboxNumeric{parent=chg_target,x=2,y=1,whole_num_precision=15,fractional_precision=0,min=0,arrow_fg_bg=cpair(colors.gray,colors.white),fg_bg=bw_fg_bg}
    TextBox{parent=chg_target,x=18,y=2,text="kFE"}
    local cur_charge = DataIndicator{parent=targets,x=9,y=9,label="",format="%19d",value=0,unit="kFE",commas=true,lu_colors=cpair(colors.black,colors.black),width=23,fg_bg=cpair(colors.black,colors.brown)}

    facility.ps.subscribe("process_charge_target", c_target.set_value)
    facility.induction_ps_tbl[1].subscribe("energy", function (j) cur_charge.update(util.joules_to_fe(j) / 1000) end)

    local gen_tag = Div{parent=targets,x=1,y=11,width=8,height=4,fg_bg=cpair(colors.black,colors.purple)}
    TextBox{parent=gen_tag,x=2,y=2,text="Gen. Target",width=7,height=2}

    local gen_target = Div{parent=targets,x=9,y=11,width=23,height=3,fg_bg=cpair(colors.gray,colors.white)}
    local g_target = SpinboxNumeric{parent=gen_target,x=8,y=1,whole_num_precision=9,fractional_precision=0,min=0,arrow_fg_bg=cpair(colors.gray,colors.white),fg_bg=bw_fg_bg}
    TextBox{parent=gen_target,x=18,y=2,text="kFE/t"}
    local cur_gen = DataIndicator{parent=targets,x=9,y=14,label="",format="%17d",value=0,unit="kFE/t",commas=true,lu_colors=cpair(colors.black,colors.black),width=23,fg_bg=cpair(colors.black,colors.brown)}

    facility.ps.subscribe("process_gen_target", g_target.set_value)
    facility.induction_ps_tbl[1].subscribe("last_input", function (j) cur_gen.update(util.joules_to_fe(j) / 1000) end)

    -----------------
    -- unit limits --
    -----------------

    local limit_div = Div{parent=proc,width=40,height=19,x=34,y=6}

    local rate_limits = {}

    for i = 1, facility.num_units do
        local unit = units[i]   ---@type ioctl_unit

        local _y = ((i - 1) * 5) + 1

        local unit_tag = Div{parent=limit_div,x=1,y=_y,width=8,height=4,fg_bg=cpair(colors.black,colors.lightBlue)}
        TextBox{parent=unit_tag,x=2,y=2,text="Unit "..i.." Limit",width=7,height=2}

        local lim_ctl = Div{parent=limit_div,x=9,y=_y,width=14,height=3,fg_bg=cpair(colors.gray,colors.white)}
        rate_limits[i] = SpinboxNumeric{parent=lim_ctl,x=2,y=1,whole_num_precision=4,fractional_precision=1,min=0.1,arrow_fg_bg=cpair(colors.gray,colors.white),fg_bg=bw_fg_bg}
        TextBox{parent=lim_ctl,x=9,y=2,text="mB/t"}

        unit.unit_ps.subscribe("max_burn", rate_limits[i].set_max)
        unit.unit_ps.subscribe("burn_limit", rate_limits[i].set_value)

        local cur_burn = DataIndicator{parent=limit_div,x=9,y=_y+3,label="",format="%7.1f",value=0,unit="mB/t",commas=false,lu_colors=cpair(colors.black,colors.black),width=14,fg_bg=cpair(colors.black,colors.brown)}

        unit.unit_ps.subscribe("act_burn_rate", cur_burn.update)
    end

    -------------------------
    -- controls and status --
    -------------------------

    local ctl_opts = { "Regulated", "Burn Rate", "Charge Level", "Generation Rate" }
    local mode = RadioButton{parent=proc,x=34,y=1,options=ctl_opts,callback=function()end,radio_colors=cpair(colors.purple,colors.black),radio_bg=colors.gray}

    facility.ps.subscribe("process_mode", mode.set_value)

    local u_stat = Rectangle{parent=proc,border=border(1,colors.gray,true),thin=true,width=31,height=4,x=1,y=16,fg_bg=bw_fg_bg}
    local stat_line_1 = TextBox{parent=u_stat,x=1,y=1,text="UNKNOWN",width=31,height=1,alignment=TEXT_ALIGN.CENTER,fg_bg=bw_fg_bg}
    local stat_line_2 = TextBox{parent=u_stat,x=1,y=2,text="awaiting data",width=31,height=1,alignment=TEXT_ALIGN.CENTER,fg_bg=cpair(colors.gray, colors.white)}

    facility.ps.subscribe("status_line_1", stat_line_1.set_value)
    facility.ps.subscribe("status_line_2", stat_line_2.set_value)

    local auto_controls = Div{parent=proc,x=1,y=20,width=31,height=5,fg_bg=cpair(colors.gray,colors.white)}

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
    local stop  = HazardButton{parent=auto_controls,x=23,y=2,text="STOP",accent=colors.orange,dis_colors=dis_colors,callback=process.stop_auto,fg_bg=hzd_fg_bg}

    facility.start_ack = start.on_response
    facility.stop_ack = stop.on_response

    function facility.save_cfg_ack(ack)
        tcd.dispatch(0.2, function () save.on_response(ack) end)
    end

    facility.ps.subscribe("auto_ready", function (ready)
        if ready and (not facility.auto_active) then start.enable() else start.disable() end
    end)

    facility.ps.subscribe("auto_active", function (active)
        if active then
            b_target.disable()
            c_target.disable()
            g_target.disable()

            mode.disable()
            start.disable()

            for i = 1, #rate_limits do
                rate_limits[i].disable()
            end
        else
            b_target.enable()
            c_target.enable()
            g_target.enable()

            mode.enable()
            if facility.auto_ready then start.enable() end

            for i = 1, #rate_limits do
                rate_limits[i].enable()
            end
        end
    end)
end

return new_view
