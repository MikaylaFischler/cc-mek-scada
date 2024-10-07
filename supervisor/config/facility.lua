local util        = require("scada-common.util")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local Checkbox    = require("graphics.elements.controls.Checkbox")
local PushButton  = require("graphics.elements.controls.PushButton")
local Radio2D     = require("graphics.elements.controls.Radio2D")
local RadioButton = require("graphics.elements.controls.RadioButton")

local NumberField = require("graphics.elements.form.NumberField")

local tri = util.trinary

local cpair = core.cpair

local self = {
    vis_ftanks = {}, ---@type { line: Div, pipe_conn?: TextBox, pipe_chain?: TextBox, pipe_direct?: TextBox, label?: TextBox }[]
    vis_utanks = {}  ---@type { line: Div, label: TextBox }[]
}

local facility = {}

-- create the facility configuration view
---@param tool_ctl _svr_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ svr_config, svr_config, svr_config, table, function ]
---@param svr_cfg Div
---@param style { [string]: cpair }
---@return MultiPane peri_pane
function facility.create(tool_ctl, main_pane, cfg_sys, svr_cfg, style)
    local _, ini_cfg, tmp_cfg, _, _ = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg

    --#region Facility

    local svr_c_1 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_2 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_3 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_4 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_5 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_6 = Div{parent=svr_cfg,x=2,y=4,width=49}
    local svr_c_7 = Div{parent=svr_cfg,x=2,y=4,width=49}

    local svr_pane = MultiPane{parent=svr_cfg,x=1,y=4,panes={svr_c_1,svr_c_2,svr_c_3,svr_c_4,svr_c_5,svr_c_6,svr_c_7}}

    TextBox{parent=svr_cfg,x=1,y=2,text=" Facility Configuration",fg_bg=cpair(colors.black,colors.yellow)}

    TextBox{parent=svr_c_1,x=1,y=1,height=3,text="Please enter the number of reactors you have, also referred to as reactor units or 'units' for short. A maximum of 4 is currently supported."}
    tool_ctl.num_units = NumberField{parent=svr_c_1,x=1,y=5,width=5,max_chars=2,default=ini_cfg.UnitCount,min=1,max=4,fg_bg=bw_fg_bg}
    TextBox{parent=svr_c_1,x=7,y=5,text="reactors"}

    local nu_error = TextBox{parent=svr_c_1,x=8,y=14,width=35,text="Please set the number of reactors.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_num_units()
        local count = tonumber(tool_ctl.num_units.get_value())
        if count ~= nil and count > 0 and count < 5 then
            nu_error.hide(true)
            tmp_cfg.UnitCount = count

            local confs = tool_ctl.cooling_elems
            if count >= 2 then confs[2].line.show() else confs[2].line.hide(true) end
            if count >= 3 then confs[3].line.show() else confs[3].line.hide(true) end
            if count == 4 then confs[4].line.show() else confs[4].line.hide(true) end

            svr_pane.set_value(2)
        else nu_error.show() end
    end

    PushButton{parent=svr_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_1,x=44,y=14,text="Next \x1a",callback=submit_num_units,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_2,x=1,y=1,height=4,text="Please provide the reactor cooling configuration below. This includes the number of turbines, boilers, and if that reactor has a connection to a dynamic tank for emergency coolant."}
    TextBox{parent=svr_c_2,x=1,y=6,text="UNIT    TURBINES   BOILERS   HAS TANK CONNECTION?",fg_bg=g_lg_fg_bg}

    for i = 1, 4 do
        local num_t, num_b, has_t = 1, 0, false

        if ini_cfg.CoolingConfig[i] then
            local conf = ini_cfg.CoolingConfig[i]
            if util.is_int(conf.TurbineCount) then num_t = math.min(3, math.max(1, conf.TurbineCount or 1)) end
            if util.is_int(conf.BoilerCount) then num_b = math.min(2, math.max(0, conf.BoilerCount or 0)) end
            has_t = conf.TankConnection == true
        end

        local line = Div{parent=svr_c_2,x=1,y=7+i,height=1}

        TextBox{parent=line,text="Unit "..i,width=6}
        local turbines = NumberField{parent=line,x=9,y=1,width=5,max_chars=2,default=num_t,min=1,max=3,fg_bg=bw_fg_bg}
        local boilers = NumberField{parent=line,x=20,y=1,width=5,max_chars=2,default=num_b,min=0,max=2,fg_bg=bw_fg_bg}
        local tank = Checkbox{parent=line,x=30,y=1,label="Is Connected",default=has_t,box_fg_bg=cpair(colors.yellow,colors.black)}

        tool_ctl.cooling_elems[i] = { line = line, turbines = turbines, boilers = boilers, tank = tank }
    end

    local cool_err = TextBox{parent=svr_c_2,x=8,y=14,width=33,text="Please fill out all fields.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_cooling()
        local any_missing = false
        for i = 1, tmp_cfg.UnitCount do
            local conf = tool_ctl.cooling_elems[i]
            any_missing = any_missing or (tonumber(conf.turbines.get_value()) == nil)
            any_missing = any_missing or (tonumber(conf.boilers.get_value()) == nil)
        end

        if any_missing then
            cool_err.show()
        else
            local any_has_tank = false

            tmp_cfg.CoolingConfig = {}
            for i = 1, tmp_cfg.UnitCount do
                local conf = tool_ctl.cooling_elems[i]
                -- already verified fields are numbers
                tmp_cfg.CoolingConfig[i] = {
                    TurbineCount = tonumber(conf.turbines.get_value()) --[[@as number]],
                    BoilerCount = tonumber(conf.boilers.get_value()) --[[@as number]],
                    TankConnection = conf.tank.get_value()
                }

                if conf.tank.get_value() then any_has_tank = true end
            end

            for i = 1, 4 do
                local elem = tool_ctl.tank_elems[i]
                if i <= tmp_cfg.UnitCount then
                    elem.div.show()
                    if tmp_cfg.CoolingConfig[i].TankConnection then
                        elem.no_tank.hide()
                        elem.tank_opt.show()
                    else
                        elem.tank_opt.hide(true)
                        elem.no_tank.show()
                    end
                else elem.div.hide(true) end
            end

            if any_has_tank then svr_pane.set_value(3) else main_pane.set_value(3) end
        end
    end

    PushButton{parent=svr_c_2,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_2,x=44,y=14,text="Next \x1a",callback=submit_cooling,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_3,x=1,y=1,height=6,text="You have set one or more of your units to use dynamic tanks for emergency coolant. You have two paths for configuration. The first is to assign dynamic tanks to reactor units; one tank per reactor, only connected to that reactor. RTU configurations must also assign it as such."}
    TextBox{parent=svr_c_3,x=1,y=8,height=3,text="Alternatively, you can configure them as facility tanks to connect to multiple reactor units. These can intermingle with unit-specific tanks."}

    tool_ctl.en_fac_tanks = Checkbox{parent=svr_c_3,x=1,y=12,label="Use Facility Dynamic Tanks",default=ini_cfg.FacilityTankMode>0,box_fg_bg=cpair(colors.yellow,colors.black)}

    local function submit_en_fac_tank()
        if tool_ctl.en_fac_tanks.get_value() then
            svr_pane.set_value(4)
            tmp_cfg.FacilityTankMode = tri(tmp_cfg.FacilityTankMode == 0, 1, math.min(8, math.max(1, ini_cfg.FacilityTankMode)))
        else
            tmp_cfg.FacilityTankMode = 0
            tmp_cfg.FacilityTankDefs = {}
            svr_pane.set_value(7)
        end
    end

    PushButton{parent=svr_c_3,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_3,x=44,y=14,text="Next \x1a",callback=submit_en_fac_tank,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_4,x=1,y=1,height=4,text="Please set unit connections to dynamic tanks, selecting at least one facility tank. The layout for facility tanks will be configured next."}

    for i = 1, 4 do
        local val = math.max(1, ini_cfg.FacilityTankDefs[i] or 2)
        local div = Div{parent=svr_c_4,x=1,y=3+(2*i),height=2}

        TextBox{parent=div,x=1,y=1,width=33,text="Unit "..i.." will be connected to..."}
        TextBox{parent=div,x=6,y=2,width=3,text="..."}
        local tank_opt = Radio2D{parent=div,x=9,y=2,rows=1,columns=2,default=val,options={"its own Unit Tank","a Facility Tank"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
        local no_tank = TextBox{parent=div,x=9,y=2,width=34,text="no tank (as you set two steps ago)",fg_bg=cpair(colors.gray,colors.lightGray),hidden=true}

        tool_ctl.tank_elems[i] = { div = div, tank_opt = tank_opt, no_tank = no_tank }
    end

    local tank_err = TextBox{parent=svr_c_4,x=8,y=14,width=33,text="You selected no facility tanks.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function hide_fconn(i)
        if i > 1 then self.vis_ftanks[i].pipe_conn.hide(true)
        else self.vis_ftanks[i].line.hide(true) end
    end

    local function submit_tank_defs()
        local any_fac = false

        tmp_cfg.FacilityTankDefs = {}
        for i = 1, tmp_cfg.UnitCount do
            local def

            if tmp_cfg.CoolingConfig[i].TankConnection then
                def = tool_ctl.tank_elems[i].tank_opt.get_value()
                any_fac = any_fac or (def == 2)
            else def = 0 end

            if def == 1 then
                self.vis_utanks[i].line.show()
                self.vis_utanks[i].label.set_value("Tank U" .. i)
                hide_fconn(i)
            else
                if def == 2 then
                    if i > 1 then self.vis_ftanks[i].pipe_conn.show()
                    else self.vis_ftanks[i].line.show() end
                else hide_fconn(i) end
                self.vis_utanks[i].line.hide(true)
            end

            tmp_cfg.FacilityTankDefs[i] = def
        end

        for i = tmp_cfg.UnitCount + 1, 4 do
            self.vis_utanks[i].line.hide(true)
        end

        tool_ctl.vis_draw(tmp_cfg.FacilityTankMode)

        if any_fac then
            tank_err.hide(true)
            svr_pane.set_value(5)
        else tank_err.show() end
    end

    PushButton{parent=svr_c_4,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_4,x=44,y=14,text="Next \x1a",callback=submit_tank_defs,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_5,x=1,y=1,text="Please select your dynamic tank layout."}
    TextBox{parent=svr_c_5,x=12,y=3,text="Facility Tanks             Unit Tanks",fg_bg=g_lg_fg_bg}

    --#region Tank Layout Visualizer

    local pipe_cpair = cpair(colors.blue,colors.lightGray)

    local vis = Div{parent=svr_c_5,x=14,y=5,height=7}

    local vis_unit_list = TextBox{parent=vis,x=15,y=1,width=6,height=7,text="Unit 1\n\nUnit 2\n\nUnit 3\n\nUnit 4"}

    -- draw unit tanks and their pipes
    for i = 1, 4 do
        local line = Div{parent=vis,x=22,y=(i*2)-1,width=13,height=1}
        TextBox{parent=line,width=5,text=string.rep("\x8c",5),fg_bg=pipe_cpair}
        local label = TextBox{parent=line,x=7,y=1,width=7,text="Tank ?"}
        self.vis_utanks[i] = { line = line, label = label }
    end

    -- draw facility tank connections

    local ftank_1 = Div{parent=vis,x=1,y=1,width=13,height=1}
    TextBox{parent=ftank_1,width=7,text="Tank F1"}
    self.vis_ftanks[1] = {
        line = ftank_1, pipe_direct = TextBox{parent=ftank_1,x=9,y=1,width=5,text=string.rep("\x8c",5),fg_bg=pipe_cpair}
    }

    for i = 2, 4 do
        local line = Div{parent=vis,x=1,y=(i-1)*2,width=13,height=2}
        local pipe_conn = TextBox{parent=line,x=13,y=2,width=1,text="\x8c",fg_bg=pipe_cpair}
        local pipe_chain = TextBox{parent=line,x=12,y=1,width=1,height=2,text="\x95\n\x8d",fg_bg=pipe_cpair}
        local pipe_direct = TextBox{parent=line,x=9,y=2,width=4,text="\x8c\x8c\x8c\x8c",fg_bg=pipe_cpair}
        local label = TextBox{parent=line,x=1,y=2,width=7,text=""}
        self.vis_ftanks[i] = { line = line, pipe_conn = pipe_conn, pipe_chain = pipe_chain, pipe_direct = pipe_direct, label = label }
    end

    -- draw the pipe visualization
    ---@param mode integer pipe mode
    function tool_ctl.vis_draw(mode)
        -- is a facility tank connected to this unit
        ---@param i integer unit 1 - 4
        ---@return boolean connected
        local function is_ft(i) return tmp_cfg.FacilityTankDefs[i] == 2 end

        local u_text = ""
        for i = 1, tmp_cfg.UnitCount do
            u_text = u_text .. "Unit " .. i .. "\n\n"
        end

        vis_unit_list.set_value(u_text)

        local vis_ftanks = self.vis_ftanks
        local next_idx = 1

        if is_ft(1) then
            next_idx = 2

            if (mode == 1 and (is_ft(2) or is_ft(3) or is_ft(4))) or (mode == 2 and (is_ft(2) or is_ft(3))) or ((mode == 3 or mode == 5) and is_ft(2)) then
                vis_ftanks[1].pipe_direct.set_value("\x8c\x8c\x8c\x9c\x8c")
            else
                vis_ftanks[1].pipe_direct.set_value(string.rep("\x8c",5))
            end
        end

        local _2_12_need_passt = (mode == 1 and (is_ft(3) or is_ft(4))) or (mode == 2 and is_ft(3))
        local _2_46_need_chain = (mode == 4 and (is_ft(3) or is_ft(4))) or (mode == 6 and is_ft(3))

        if is_ft(2) then
            vis_ftanks[2].label.set_value("Tank F" .. next_idx)

            if (mode < 4 or mode == 5) and is_ft(1) then
                vis_ftanks[2].label.hide(true)
                vis_ftanks[2].pipe_direct.hide(true)
                if _2_12_need_passt then
                    vis_ftanks[2].pipe_chain.set_value("\x95\n\x9d")
                else
                    vis_ftanks[2].pipe_chain.set_value("\x95\n\x8d")
                end
                vis_ftanks[2].pipe_chain.show()
            else
                vis_ftanks[2].label.show()
                next_idx = next_idx + 1

                vis_ftanks[2].pipe_chain.hide(true)
                if _2_12_need_passt or _2_46_need_chain then
                    vis_ftanks[2].pipe_direct.set_value("\x8c\x8c\x8c\x9c")
                else
                    vis_ftanks[2].pipe_direct.set_value("\x8c\x8c\x8c\x8c")
                end
                vis_ftanks[2].pipe_direct.show()
            end

            vis_ftanks[2].line.show()
        elseif is_ft(1) and _2_12_need_passt then
            vis_ftanks[2].label.hide(true)
            vis_ftanks[2].pipe_direct.hide(true)
            vis_ftanks[2].pipe_chain.set_value("\x95\n\x95")
            vis_ftanks[2].pipe_chain.show()
            vis_ftanks[2].line.show()
        else
            vis_ftanks[2].line.hide(true)
        end

        if is_ft(3) then
            vis_ftanks[3].label.set_value("Tank F" .. next_idx)

            if (mode < 3 and (is_ft(1) or is_ft(2))) or ((mode == 4 or mode == 6) and is_ft(2)) then
                vis_ftanks[3].label.hide(true)
                vis_ftanks[3].pipe_direct.hide(true)
                if (mode == 1 or mode == 4) and is_ft(4) then
                    vis_ftanks[3].pipe_chain.set_value("\x95\n\x9d")
                else
                    vis_ftanks[3].pipe_chain.set_value("\x95\n\x8d")
                end
                vis_ftanks[3].pipe_chain.show()
            else
                vis_ftanks[3].label.show()
                next_idx = next_idx + 1

                vis_ftanks[3].pipe_chain.hide(true)
                if (mode == 1 or mode == 3 or mode == 4 or mode == 7) and is_ft(4) then
                    vis_ftanks[3].pipe_direct.set_value("\x8c\x8c\x8c\x9c")
                else
                    vis_ftanks[3].pipe_direct.set_value("\x8c\x8c\x8c\x8c")
                end
                vis_ftanks[3].pipe_direct.show()
            end

            vis_ftanks[3].line.show()
        elseif (mode == 1 and is_ft(4) and (is_ft(1) or is_ft(2))) or (mode == 4 and is_ft(2) and is_ft(4)) then
            vis_ftanks[3].label.hide(true)
            vis_ftanks[3].pipe_direct.hide(true)
            vis_ftanks[3].pipe_chain.set_value("\x95\n\x95")
            vis_ftanks[3].pipe_chain.show()
            vis_ftanks[3].line.show()
        else
            vis_ftanks[3].line.hide(true)
        end

        if is_ft(4) then
            vis_ftanks[4].label.set_value("Tank F" .. next_idx)

            if (mode == 1 and (is_ft(1) or is_ft(2) or is_ft(3))) or ((mode == 3 or mode == 7) and is_ft(3)) or (mode == 4 and (is_ft(2) or is_ft(3))) then
                vis_ftanks[4].label.hide(true)
                vis_ftanks[4].pipe_direct.hide(true)
                vis_ftanks[4].pipe_chain.show()
            else
                vis_ftanks[4].label.show()
                vis_ftanks[4].pipe_chain.hide(true)
                vis_ftanks[4].pipe_direct.show()
            end

            vis_ftanks[4].line.show()
        else
            vis_ftanks[4].line.hide(true)
        end
    end

    local function change_mode(mode)
        tmp_cfg.FacilityTankMode = mode
        tool_ctl.vis_draw(mode)
    end

    local tank_modes = { "Mode 1", "Mode 2", "Mode 3", "Mode 4", "Mode 5", "Mode 6", "Mode 7", "Mode 8" }
    tool_ctl.tank_mode = RadioButton{parent=svr_c_5,x=1,y=4,callback=change_mode,default=math.max(1,ini_cfg.FacilityTankMode),options=tank_modes,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow}

    --#endregion

    PushButton{parent=svr_c_5,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_5,x=44,y=14,text="Next \x1a",callback=function()svr_pane.set_value(7)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    PushButton{parent=svr_c_5,x=8,y=14,min_width=7,text="About",callback=function()svr_pane.set_value(6)end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_6,height=3,text="This visualization tool shows the pipe connections required for a particular dynamic tank configuration you have selected."}
    TextBox{parent=svr_c_6,y=5,height=4,text="Examples: A U2 tank should be configured on an RTU as the dynamic tank for unit #2. An F3 tank should be configured on an RTU as the #3 dynamic tank for the facility."}
    TextBox{parent=svr_c_6,y=10,height=3,text="Some modes may look the same if you are not using 4 total reactor units. The wiki has details. Modes that look the same will function the same.",fg_bg=g_lg_fg_bg}

    PushButton{parent=svr_c_6,x=1,y=14,text="\x1b Back",callback=function()svr_pane.set_value(5)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=svr_c_7,height=6,text="Charge control provides automatic control to maintain an induction matrix charge level. In order to have smoother control, reactors that were activated will be held on at 0.01 mB/t for a short period before allowing them to turn off. This minimizes overshooting the charge target."}
    TextBox{parent=svr_c_7,y=8,height=3,text="You can extend this to a full minute to minimize reactors flickering on/off, but there may be more overshoot of the target."}

    local ext_idling = Checkbox{parent=svr_c_7,x=1,y=12,label="Enable Extended Idling",default=ini_cfg.ExtChargeIdling,box_fg_bg=cpair(colors.yellow,colors.black)}

    local function back_from_idling()
        svr_pane.set_value(tri(tmp_cfg.FacilityTankMode == 0, 3, 5))
    end

    local function submit_idling()
        tmp_cfg.ExtChargeIdling = ext_idling.get_value()
        main_pane.set_value(3)
    end

    PushButton{parent=svr_c_7,x=1,y=14,text="\x1b Back",callback=back_from_idling,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=svr_c_7,x=44,y=14,text="Next \x1a",callback=submit_idling,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    return svr_pane
end

return facility
