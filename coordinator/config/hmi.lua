local ppm         = require("scada-common.ppm")
local types       = require("scada-common.types")
local util        = require("scada-common.util")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local Checkbox    = require("graphics.elements.controls.Checkbox")
local PushButton  = require("graphics.elements.controls.PushButton")
local RadioButton = require("graphics.elements.controls.RadioButton")

local NumberField = require("graphics.elements.form.NumberField")

local cpair = core.cpair

local self = {
    apply_mon = nil,    ---@type PushButton

    edit_monitor = nil, ---@type function

    mon_iface = "",
    mon_expect = {}     ---@type integer[]
}

local hmi = {}

-- create the HMI (human machine interface) configuration view
---@param tool_ctl _crd_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ crd_config, crd_config, crd_config, { [1]: string, [2]: string, [3]: any }[], function ]
---@param divs Div[]
---@param style { [string]: cpair }
---@return MultiPane mon_pane
function hmi.create(tool_ctl, main_pane, cfg_sys, divs, style)
    local _, ini_cfg, tmp_cfg, _, _ = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]
    local mon_cfg, spkr_cfg, crd_cfg = divs[1], divs[2], divs[3]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    --#region Monitors

    local mon_c_1 = Div{parent=mon_cfg,x=2,y=4,width=49}
    local mon_c_2 = Div{parent=mon_cfg,x=2,y=4,width=49}
    local mon_c_3 = Div{parent=mon_cfg,x=2,y=4,width=49}
    local mon_c_4 = Div{parent=mon_cfg,x=2,y=4,width=49}

    local mon_pane = MultiPane{parent=mon_cfg,x=1,y=4,panes={mon_c_1,mon_c_2,mon_c_3,mon_c_4}}

    TextBox{parent=mon_cfg,x=1,y=2,text=" Monitor Configuration",fg_bg=cpair(colors.black,colors.blue)}

    TextBox{parent=mon_c_1,x=1,y=1,height=5,text="Your configuration requires the following monitors. The main and flow monitors' heights are dependent on your unit count and cooling setup. If you manually entered the unit count, a * will be shown on potentially inaccurate calculations."}
    local mon_reqs = ListBox{parent=mon_c_1,x=1,y=7,height=6,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function next_from_reqs()
        -- unassign unit monitors above the unit count
        for i = tmp_cfg.UnitCount + 1, 4 do tmp_cfg.UnitDisplays[i] = nil end

        tool_ctl.gen_mon_list()
        mon_pane.set_value(2)
    end

    PushButton{parent=mon_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mon_c_1,x=8,y=14,text="Legacy Options",min_width=16,callback=function()mon_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mon_c_1,x=44,y=14,text="Next \x1a",callback=next_from_reqs,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=mon_c_2,x=1,y=1,height=5,text="Please configure your monitors below. You can go back to the prior page without losing progress to double check what you need. All of those monitors must be assigned before you can proceed."}

    local mon_list = ListBox{parent=mon_c_2,x=1,y=6,height=7,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local assign_err = TextBox{parent=mon_c_2,x=8,y=14,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_monitors()
        if tmp_cfg.MainDisplay == nil then
            assign_err.set_value("Please assign the main monitor.")
        elseif tmp_cfg.FlowDisplay == nil and not tmp_cfg.DisableFlowView then
            assign_err.set_value("Please assign the flow monitor.")
        elseif util.table_len(tmp_cfg.UnitDisplays) ~= tmp_cfg.UnitCount then
            for i = 1, tmp_cfg.UnitCount do
                if tmp_cfg.UnitDisplays[i] == nil then
                    assign_err.set_value("Please assign the unit " .. i .. " monitor.")
                    break
                end
            end
        else
            assign_err.hide(true)
            main_pane.set_value(5)
            return
        end

        assign_err.show()
    end

    PushButton{parent=mon_c_2,x=1,y=14,text="\x1b Back",callback=function()mon_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mon_c_2,x=44,y=14,text="Next \x1a",callback=submit_monitors,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    local mon_desc = TextBox{parent=mon_c_3,x=1,y=1,height=4,text=""}

    local mon_unit_l, mon_unit = nil, nil ---@type TextBox, NumberField

    local mon_warn = TextBox{parent=mon_c_3,x=1,y=11,height=2,text="",fg_bg=cpair(colors.red,colors.lightGray)}

    ---@param val integer assignment type
    local function on_assign_mon(val)
        if val == 2 and tmp_cfg.DisableFlowView then
            self.apply_mon.disable()
            mon_warn.set_value("You disabled having a flow view monitor. It can't be set unless you go back and enable it.")
            mon_warn.show()
        elseif not util.table_contains(self.mon_expect, val) then
            self.apply_mon.disable()
            mon_warn.set_value("That assignment doesn't fit monitor dimensions. You'll need to resize the monitor for it to work.")
            mon_warn.show()
        else
            self.apply_mon.enable()
            mon_warn.hide(true)
        end

        if val == 3 then
            mon_unit_l.show()
            mon_unit.show()
        else
            mon_unit_l.hide(true)
            mon_unit.hide(true)
        end

        local value = mon_unit.get_value()
        mon_unit.set_max(tmp_cfg.UnitCount)
        if value == "0" or value == nil then mon_unit.set_value(0) end
    end

    TextBox{parent=mon_c_3,x=1,y=6,width=10,text="Assignment"}
    local mon_assign = RadioButton{parent=mon_c_3,x=1,y=7,default=1,options={"Main Monitor","Flow Monitor","Unit Monitor"},callback=on_assign_mon,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.blue}

    mon_unit_l = TextBox{parent=mon_c_3,x=18,y=6,width=7,text="Unit ID"}
    mon_unit = NumberField{parent=mon_c_3,x=18,y=7,width=10,max_chars=2,min=1,max=4,fg_bg=bw_fg_bg}

    local mon_u_err = TextBox{parent=mon_c_3,x=8,y=14,width=35,text="Please provide a unit ID.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    -- purge all assignments for a given monitor
    ---@param iface string
    local function purge_assignments(iface)
        if tmp_cfg.MainDisplay == iface then
            tmp_cfg.MainDisplay = nil
        elseif tmp_cfg.FlowDisplay == iface then
            tmp_cfg.FlowDisplay = nil
        else
            for i = 1, tmp_cfg.UnitCount do
                if tmp_cfg.UnitDisplays[i] == iface then tmp_cfg.UnitDisplays[i] = nil end
            end
        end
    end

    local function apply_monitor()
        local iface = self.mon_iface
        local type = mon_assign.get_value()
        local u_id = tonumber(mon_unit.get_value())

        if type == 1 then
            purge_assignments(iface)
            tmp_cfg.MainDisplay = iface
        elseif type == 2 then
            purge_assignments(iface)
            tmp_cfg.FlowDisplay = iface
        elseif u_id and u_id > 0 then
            purge_assignments(iface)
            tmp_cfg.UnitDisplays[u_id] = iface
        else
            mon_u_err.show()
            return
        end

        tool_ctl.gen_mon_list()
        mon_u_err.hide(true)
        mon_pane.set_value(2)
    end

    PushButton{parent=mon_c_3,x=1,y=14,text="\x1b Back",callback=function()mon_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    self.apply_mon = PushButton{parent=mon_c_3,x=43,y=14,min_width=7,text="Apply",callback=apply_monitor,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}

    TextBox{parent=mon_c_4,x=1,y=1,height=3,text="For legacy compatibility with facilities built without space for a flow monitor, you can disable the flow monitor requirement here."}
    TextBox{parent=mon_c_4,x=1,y=5,height=3,text="Please be aware that THIS OPTION WILL BE REMOVED ON RELEASE. Disabling it will only be available for the remainder of the beta."}

    tool_ctl.dis_flow_view = Checkbox{parent=mon_c_4,x=1,y=9,default=ini_cfg.DisableFlowView,label="Disable Flow View Monitor",box_fg_bg=cpair(colors.blue,colors.black)}

    local function back_from_legacy()
        tmp_cfg.DisableFlowView = tool_ctl.dis_flow_view.get_value()
        tool_ctl.update_mon_reqs()
        mon_pane.set_value(1)
    end

    PushButton{parent=mon_c_4,x=44,y=14,min_width=6,text="Done",callback=back_from_legacy,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Speaker

    local spkr_c = Div{parent=spkr_cfg,x=2,y=4,width=49}

    TextBox{parent=spkr_cfg,x=1,y=2,text=" Speaker Configuration",fg_bg=cpair(colors.black,colors.cyan)}

    TextBox{parent=spkr_c,x=1,y=1,height=2,text="The coordinator uses a speaker to play alarm sounds."}
    TextBox{parent=spkr_c,x=1,y=4,height=3,text="You can change the speaker audio volume from the default. The range is 0.0 to 3.0, where 1.0 is standard volume."}

    tool_ctl.s_vol = NumberField{parent=spkr_c,x=1,y=8,width=9,max_chars=7,allow_decimal=true,default=ini_cfg.SpeakerVolume,min=0,max=3,fg_bg=bw_fg_bg}

    TextBox{parent=spkr_c,x=1,y=10,height=3,text="Note: alarm sine waves are at half scale so that multiple will be required to reach full scale.",fg_bg=g_lg_fg_bg}

    local s_vol_err = TextBox{parent=spkr_c,x=8,y=14,width=35,text="Please set a volume.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_vol()
        local vol = tonumber(tool_ctl.s_vol.get_value())
        if vol ~= nil then
            s_vol_err.hide(true)
            tmp_cfg.SpeakerVolume = vol
            main_pane.set_value(6)
        else s_vol_err.show() end
    end

    PushButton{parent=spkr_c,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=spkr_c,x=44,y=14,text="Next \x1a",callback=submit_vol,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Coordinator UI

    local crd_c_1 = Div{parent=crd_cfg,x=2,y=4,width=49}

    TextBox{parent=crd_cfg,x=1,y=2,text=" Coordinator UI Configuration",fg_bg=cpair(colors.black,colors.lime)}

    TextBox{parent=crd_c_1,x=1,y=1,height=2,text="You can customize the UI with the interface options below."}

    TextBox{parent=crd_c_1,x=1,y=4,text="Clock Time Format"}
    tool_ctl.clock_fmt = RadioButton{parent=crd_c_1,x=1,y=5,default=util.trinary(ini_cfg.Time24Hour,1,2),options={"24-Hour","12-Hour"},callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lime}

    TextBox{parent=crd_c_1,x=20,y=4,text="Po/Pu Pellet Color"}
    TextBox{parent=crd_c_1,x=39,y=4,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision
    tool_ctl.pellet_color = RadioButton{parent=crd_c_1,x=20,y=5,default=util.trinary(ini_cfg.GreenPuPellet,1,2),options={"Green Pu/Cyan Po","Cyan Pu/Green Po (Mek 10.4+)"},callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lime}

    TextBox{parent=crd_c_1,x=1,y=8,text="Temperature Scale"}
    tool_ctl.temp_scale = RadioButton{parent=crd_c_1,x=1,y=9,default=ini_cfg.TempScale,options=types.TEMP_SCALE_NAMES,callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lime}

    TextBox{parent=crd_c_1,x=20,y=8,text="Energy Scale"}
    tool_ctl.energy_scale = RadioButton{parent=crd_c_1,x=20,y=9,default=ini_cfg.EnergyScale,options=types.ENERGY_SCALE_NAMES,callback=function()end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.lime}

    local function submit_ui_opts()
        tmp_cfg.Time24Hour = tool_ctl.clock_fmt.get_value() == 1
        tmp_cfg.GreenPuPellet = tool_ctl.pellet_color.get_value() == 1
        tmp_cfg.TempScale = tool_ctl.temp_scale.get_value()
        tmp_cfg.EnergyScale = tool_ctl.energy_scale.get_value()
        main_pane.set_value(7)
    end

    PushButton{parent=crd_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(5)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=crd_c_1,x=44,y=14,text="Next \x1a",callback=submit_ui_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Tool and Helper Functions

    -- update list of monitor requirements
    function tool_ctl.update_mon_reqs()
        local plural = tmp_cfg.UnitCount > 1

        if tool_ctl.sv_cool_conf ~= nil then
            local cnf = tool_ctl.sv_cool_conf

            local row1_tall = cnf[1][1] > 1 or cnf[1][2] > 2 or (cnf[2] and (cnf[2][1] > 1 or cnf[2][2] > 2))
            local row1_short = (cnf[1][1] == 0 and cnf[1][2] == 1) and (cnf[2] == nil or (cnf[2][1] == 0 and cnf[2][2] == 1))
            local row2_tall = (cnf[3] and (cnf[3][1] > 1 or cnf[3][2] > 2)) or (cnf[4] and (cnf[4][1] > 1 or cnf[4][2] > 2))
            local row2_short = (cnf[3] == nil or (cnf[3][1] == 0 and cnf[3][2] == 1)) and (cnf[4] == nil or (cnf[4][1] == 0 and cnf[4][2] == 1))

            if tmp_cfg.UnitCount <= 2 then
                tool_ctl.main_mon_h = util.trinary(row1_tall, 5, 4)
            else
                -- is only one tall and the other short, or are both tall? -> 5 or 6; are neither tall? -> 5
                if row1_tall or row2_tall then
                    tool_ctl.main_mon_h = util.trinary((row1_short and row2_tall) or (row1_tall and row2_short), 5, 6)
                else tool_ctl.main_mon_h = 5 end
            end
        else
            tool_ctl.main_mon_h = util.trinary(tmp_cfg.UnitCount <= 2, 4, 5)
        end

        tool_ctl.flow_mon_h = 2 + tmp_cfg.UnitCount

        local asterisk = util.trinary(tool_ctl.sv_cool_conf == nil, "*", "")
        local m_at_least = util.trinary(tool_ctl.main_mon_h < 6, "at least ", "")
        local f_at_least = util.trinary(tool_ctl.flow_mon_h < 6, "at least ", "")

        mon_reqs.remove_all()

        TextBox{parent=mon_reqs,x=1,y=1,text="\x1a "..tmp_cfg.UnitCount.." Unit View Monitor"..util.trinary(plural,"s","")}
        TextBox{parent=mon_reqs,x=1,y=1,text="  "..util.trinary(plural,"each ","").."must be 4 blocks wide by 4 tall",fg_bg=cpair(colors.gray,colors.white)}
        TextBox{parent=mon_reqs,x=1,y=1,text="\x1a 1 Main View Monitor"}
        TextBox{parent=mon_reqs,x=1,y=1,text="  must be 8 blocks wide by "..m_at_least..tool_ctl.main_mon_h..asterisk.." tall",fg_bg=cpair(colors.gray,colors.white)}
        if not tmp_cfg.DisableFlowView then
            TextBox{parent=mon_reqs,x=1,y=1,text="\x1a 1 Flow View Monitor"}
            TextBox{parent=mon_reqs,x=1,y=1,text="  must be 8 blocks wide by "..f_at_least..tool_ctl.flow_mon_h.." tall",fg_bg=cpair(colors.gray,colors.white)}
        end
    end

    -- set/edit a monitor's assignment
    ---@param iface string
    ---@param device ppm_entry
    function self.edit_monitor(iface, device)
        self.mon_iface = iface

        local dev = device.dev
        local w, h = ppm.monitor_block_size(dev.getSize())

        local msg = "This size doesn't match a required screen. Please go back and resize it, or configure below at the risk of it not working."

        self.mon_expect = {}
        mon_assign.set_value(1)
        mon_unit.set_value(0)

        if w == 4 and h == 4 then
            msg = "This could work as a unit display. Please configure below."
            self.mon_expect = { 3 }
            mon_assign.set_value(3)
        elseif w == 8 then
            if h >= tool_ctl.main_mon_h and h >= tool_ctl.flow_mon_h then
                msg = "This could work as either your main monitor or flow monitor. Please configure below."
                self.mon_expect = { 1, 2 }
                if tmp_cfg.MainDisplay then mon_assign.set_value(2) end
            elseif h >= tool_ctl.main_mon_h then
                msg = "This could work as your main monitor. Please configure below."
                self.mon_expect = { 1 }
            elseif h >= tool_ctl.flow_mon_h then
                msg = "This could work as your flow monitor. Please configure below."
                self.mon_expect = { 2 }
                mon_assign.set_value(2)
            end
        end

        -- override if a config exists
        if tmp_cfg.MainDisplay == iface then
            mon_assign.set_value(1)
        elseif tmp_cfg.FlowDisplay == iface then
            mon_assign.set_value(2)
        else
            for i = 1, tmp_cfg.UnitCount do
                if tmp_cfg.UnitDisplays[i] == iface then
                    mon_assign.set_value(3)
                    mon_unit.set_value(i)
                    break
                end
            end
        end

        on_assign_mon(mon_assign.get_value())

        mon_desc.set_value(util.c("You have selected '", iface, "', which has a block size of ", w, " wide by ", h, " tall. ", msg))
        mon_pane.set_value(3)
    end

    -- generate the list of available monitors
    function tool_ctl.gen_mon_list()
        mon_list.remove_all()

        local missing = { main = tmp_cfg.MainDisplay ~= nil, flow = tmp_cfg.FlowDisplay ~= nil, unit = {} }
        for i = 1, tmp_cfg.UnitCount do missing.unit[i] = tmp_cfg.UnitDisplays[i] ~= nil end

        -- list connected monitors
        local monitors = ppm.get_monitor_list()
        for iface, device in pairs(monitors) do
            local dev = device.dev  ---@type Monitor

            dev.setTextScale(0.5)
            dev.setTextColor(colors.white)
            dev.setBackgroundColor(colors.black)
            dev.clear()
            dev.setCursorPos(1, 1)
            dev.setTextColor(colors.magenta)
            dev.write("This is monitor")
            dev.setCursorPos(1, 2)
            dev.setTextColor(colors.white)
            dev.write(iface)

            local assignment = "Unused"

            if tmp_cfg.MainDisplay == iface then
                assignment = "Main"
                missing.main = false
            elseif tmp_cfg.FlowDisplay == iface then
                assignment = "Flow"
                missing.flow = false
            else
                for i = 1, tmp_cfg.UnitCount do
                    if tmp_cfg.UnitDisplays[i] == iface then
                        missing.unit[i] = false
                        assignment = "Unit " .. i
                        break
                    end
                end
            end

            local line = Div{parent=mon_list,x=1,y=1,height=1}

            TextBox{parent=line,x=1,y=1,width=6,text=assignment,fg_bg=cpair(util.trinary(assignment=="Unused",colors.red,colors.blue),colors.white)}
            TextBox{parent=line,x=8,y=1,text=iface}

            local w, h = ppm.monitor_block_size(dev.getSize())

            local function unset_mon()
                purge_assignments(iface)
                tool_ctl.gen_mon_list()
            end

            TextBox{parent=line,x=33,y=1,width=4,text=w.."x"..h,fg_bg=cpair(colors.black,colors.white)}
            PushButton{parent=line,x=37,y=1,min_width=5,height=1,text="SET",callback=function()self.edit_monitor(iface,device)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
            local unset = PushButton{parent=line,x=42,y=1,min_width=7,height=1,text="UNSET",callback=unset_mon,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.black,colors.gray)}

            if assignment == "Unused" then unset.disable() end
        end

        local dc_list = {} -- disconnected monitor list

        if missing.main then table.insert(dc_list, { "Main", tmp_cfg.MainDisplay }) end
        if missing.flow then table.insert(dc_list, { "Flow", tmp_cfg.FlowDisplay }) end
        for i = 1, tmp_cfg.UnitCount do
            if missing.unit[i] then table.insert(dc_list, { "Unit " .. i, tmp_cfg.UnitDisplays[i] }) end
        end

        -- add monitors that are assigned but not connected
        for i = 1, #dc_list do
            local line = Div{parent=mon_list,x=1,y=1,height=1}

            TextBox{parent=line,x=1,y=1,width=6,text=dc_list[i][1],fg_bg=cpair(colors.blue,colors.white)}
            TextBox{parent=line,x=8,y=1,text="disconnected",fg_bg=cpair(colors.red,colors.white)}

            local function unset_mon()
                purge_assignments(dc_list[i][2])
                tool_ctl.gen_mon_list()
            end

            TextBox{parent=line,x=33,y=1,width=4,text="?x?",fg_bg=cpair(colors.black,colors.white)}
            PushButton{parent=line,x=37,y=1,min_width=5,height=1,text="SET",callback=function()end,dis_fg_bg=cpair(colors.black,colors.gray)}.disable()
            PushButton{parent=line,x=42,y=1,min_width=7,height=1,text="UNSET",callback=unset_mon,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.black,colors.gray)}
        end
    end

    --#endregion

    return mon_pane
end

return hmi
