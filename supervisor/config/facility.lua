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
    tank_fluid_opts = {}, ---@type Radio2D[]

    vis_draw = nil,       ---@type function
    draw_fluid_ops = nil, ---@type function

    vis_ftanks = {},      ---@type { line: Div, pipe_conn?: TextBox, pipe_chain?: TextBox, pipe_direct?: TextBox, label?: TextBox }[]
    vis_utanks = {}       ---@type { line: Div, label: TextBox }[]
}

local facility = {}

-- generate the tank list and tank connections tables
---@param mode integer facility tank mode
---@param defs table facility tank definitions
---@return table tank_list, table tank_conns
function facility.generate_tank_list_and_conns(mode, defs)
    local tank_mode = mode
    local tank_defs = defs
    local tank_list = { table.unpack(tank_defs) }
    local tank_conns = { table.unpack(tank_defs) }

    local function calc_fdef(start_idx, end_idx)
        local first = 4
        for i = start_idx, end_idx do
            if tank_defs[i] == 2 then
                if i < first then first = i end
            end
        end
        return first
    end

    -- set units using their own tanks as connected to their respective unit tank
    for i = 1, #tank_defs do
        if tank_defs[i] == 1 then tank_conns[i] = i end
    end

    if tank_mode == 1 then
        -- (1) 1 total facility tank (A A A A)
        local first_fdef = calc_fdef(1, #tank_defs)
        for i = 1, #tank_defs do
            if (i >= first_fdef) and (tank_defs[i] == 2) then
                tank_conns[i] = first_fdef

                if i > first_fdef then tank_list[i] = 0 end
            end
        end
    elseif tank_mode == 2 then
        -- (2) 2 total facility tanks (A A A B)
        local first_fdef = calc_fdef(1, math.min(3, #tank_defs))
        for i = 1, #tank_defs do
            if (i >= first_fdef) and (tank_defs[i] == 2) then
                if i == 4 then
                    tank_conns[i] = 4
                else
                    tank_conns[i] = first_fdef

                    if i > first_fdef then tank_list[i] = 0 end
                end
            end
        end
    elseif tank_mode == 3 then
        -- (3) 2 total facility tanks (A A B B)
        for _, a in pairs({ 1, 3 }) do
            local b = a + 1

            if tank_defs[a] == 2 then
                tank_conns[a] = a
            elseif tank_defs[b] == 2 then
                tank_conns[b] = b
            end

            if (tank_defs[a] == 2) and (tank_defs[b] == 2) then
                tank_list[b] = 0
                tank_conns[b] = a
            end
        end
    elseif tank_mode == 4 then
        -- (4) 2 total facility tanks (A B B B)
        local first_fdef = calc_fdef(2, #tank_defs)
        for i = 1, #tank_defs do
            if tank_defs[i] == 2 then
                if i == 1 then
                    tank_conns[i] = 1
                elseif i >= first_fdef then
                    tank_conns[i] = first_fdef

                    if i > first_fdef then tank_list[i] = 0 end
                end
            end
        end
    elseif tank_mode == 5 then
        -- (5) 3 total facility tanks (A A B C)
        local first_fdef = calc_fdef(1, math.min(2, #tank_defs))
        for i = 1, #tank_defs do
            if (i >= first_fdef) and (tank_defs[i] == 2) then
                if i == 3 or i == 4 then
                    tank_conns[i] = i
                elseif i >= first_fdef then
                    tank_conns[i] = first_fdef

                    if i > first_fdef then tank_list[i] = 0 end
                end
            end
        end
    elseif tank_mode == 6 then
        -- (6) 3 total facility tanks (A B B C)
        local first_fdef = calc_fdef(2, math.min(3, #tank_defs))
        for i = 1, #tank_defs do
            if tank_defs[i] == 2 then
                if i == 1 or i == 4 then
                    tank_conns[i] = i
                elseif i >= first_fdef then
                    tank_conns[i] = first_fdef

                    if i > first_fdef then tank_list[i] = 0 end
                end
            end
        end
    elseif tank_mode == 7 then
        -- (7) 3 total facility tanks (A B C C)
        local first_fdef = calc_fdef(3, #tank_defs)
        for i = 1, #tank_defs do
            if tank_defs[i] == 2 then
                if i == 1 or i == 2 then
                    tank_conns[i] = i
                elseif i >= first_fdef then
                    tank_conns[i] = first_fdef

                    if i > first_fdef then tank_list[i] = 0 end
                end
            end
        end
    elseif tank_mode == 8 then
        -- (8) 4 total facility tanks (A B C D)
        for i = 1, #tank_defs do
            if tank_defs[i] == 2 then tank_conns[i] = i end
        end
    end

    return tank_list, tank_conns
end

-- create the facility configuration view
---@param tool_ctl _svr_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ svr_config, svr_config, svr_config, table, function ]
---@param fac_cfg Div
---@param style { [string]: cpair }
---@return MultiPane fac_pane
function facility.create(tool_ctl, main_pane, cfg_sys, fac_cfg, style)
    local _, ini_cfg, tmp_cfg, _, _ = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg

    --#region Facility

    local fac_c_1 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_2 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_3 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_4 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_5 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_6 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_7 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_8 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_9 = Div{parent=fac_cfg,x=2,y=4,width=49}

    local fac_pane = MultiPane{parent=fac_cfg,x=1,y=4,panes={fac_c_1,fac_c_2,fac_c_3,fac_c_4,fac_c_5,fac_c_6,fac_c_7,fac_c_8,fac_c_9}}

    TextBox{parent=fac_cfg,x=1,y=2,text=" Facility Configuration",fg_bg=cpair(colors.black,colors.yellow)}

    --#region Unit Count

    TextBox{parent=fac_c_1,x=1,y=1,height=3,text="Please enter the number of reactors you have, also referred to as reactor units or 'units' for short. A maximum of 4 is currently supported."}
    tool_ctl.num_units = NumberField{parent=fac_c_1,x=1,y=5,width=5,max_chars=2,default=ini_cfg.UnitCount,min=1,max=4,fg_bg=bw_fg_bg}
    TextBox{parent=fac_c_1,x=7,y=5,text="reactors"}
    TextBox{parent=fac_c_1,x=1,y=7,height=3,text="If you already configured your coordinator, make sure you update the coordinator's configured unit count.",fg_bg=cpair(colors.yellow,colors._INHERIT)}

    local nu_error = TextBox{parent=fac_c_1,x=8,y=14,width=35,text="Please set the number of reactors.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_num_units()
        local count = tonumber(tool_ctl.num_units.get_value())
        if count ~= nil and count > 0 and count < 5 then
            nu_error.hide(true)
            tmp_cfg.UnitCount = count

            local c_confs = tool_ctl.cooling_elems
            local a_confs = tool_ctl.aux_cool_elems

            for i = 2, 4 do
                if count >= i then
                    c_confs[i].line.show()
                    a_confs[i].line.show()
                else
                    c_confs[i].line.hide(true)
                    a_confs[i].line.hide(true)
                end
            end

            fac_pane.set_value(2)
        else nu_error.show() end
    end

    PushButton{parent=fac_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_1,x=44,y=14,text="Next \x1a",callback=submit_num_units,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Cooling Configuration

    TextBox{parent=fac_c_2,x=1,y=1,height=4,text="Please provide the reactor cooling configuration below. This includes the number of turbines, boilers, and if that reactor has a connection to a dynamic tank for emergency coolant."}
    TextBox{parent=fac_c_2,x=1,y=6,text="UNIT    TURBINES   BOILERS   HAS TANK CONNECTION?",fg_bg=g_lg_fg_bg}

    for i = 1, 4 do
        local num_t, num_b, has_t = 1, 0, false

        if ini_cfg.CoolingConfig[i] then
            local conf = ini_cfg.CoolingConfig[i]
            if util.is_int(conf.TurbineCount) then num_t = math.min(3, math.max(1, conf.TurbineCount or 1)) end
            if util.is_int(conf.BoilerCount) then num_b = math.min(2, math.max(0, conf.BoilerCount or 0)) end
            has_t = conf.TankConnection == true
        end

        local line = Div{parent=fac_c_2,x=1,y=7+i,height=1}

        TextBox{parent=line,text="Unit "..i,width=6}
        local turbines = NumberField{parent=line,x=9,y=1,width=5,max_chars=2,default=num_t,min=1,max=3,fg_bg=bw_fg_bg}
        local boilers = NumberField{parent=line,x=20,y=1,width=5,max_chars=2,default=num_b,min=0,max=2,fg_bg=bw_fg_bg}
        local tank = Checkbox{parent=line,x=30,y=1,label="Is Connected",default=has_t,box_fg_bg=cpair(colors.yellow,colors.black)}

        tool_ctl.cooling_elems[i] = { line = line, turbines = turbines, boilers = boilers, tank = tank }
    end

    local cool_err = TextBox{parent=fac_c_2,x=8,y=14,width=33,text="Please fill out all fields.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

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

            if not any_has_tank then
                tmp_cfg.FacilityTankMode = 0
                tmp_cfg.FacilityTankDefs = {}
                tmp_cfg.FacilityTankList = {}
                tmp_cfg.FacilityTankConns = {}
                tmp_cfg.TankFluidTypes = {}
            end

            if any_has_tank then fac_pane.set_value(3) else main_pane.set_value(3) end
        end
    end

    PushButton{parent=fac_c_2,x=1,y=14,text="\x1b Back",callback=function()fac_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_2,x=44,y=14,text="Next \x1a",callback=submit_cooling,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Facility Tanks Option

    TextBox{parent=fac_c_3,x=1,y=1,height=6,text="You have set one or more of your units to use dynamic tanks for emergency coolant. You have two paths for configuration. The first is to assign dynamic tanks to reactor units; one tank per reactor, only connected to that reactor. RTU configurations must also assign it as such."}
    TextBox{parent=fac_c_3,x=1,y=8,height=3,text="Alternatively, you can configure them as facility tanks to connect to multiple reactor units. These can intermingle with unit-specific tanks."}

    tool_ctl.en_fac_tanks = Checkbox{parent=fac_c_3,x=1,y=12,label="Use Facility Dynamic Tanks",default=ini_cfg.FacilityTankMode>0,box_fg_bg=cpair(colors.yellow,colors.black)}

    local function submit_en_fac_tank()
        if tool_ctl.en_fac_tanks.get_value() then
            fac_pane.set_value(4)
            tmp_cfg.FacilityTankMode = tri(tmp_cfg.FacilityTankMode == 0, 1, math.min(8, math.max(1, ini_cfg.FacilityTankMode)))
        else
            tmp_cfg.FacilityTankMode = 0
            tmp_cfg.FacilityTankDefs = {}

            -- on facility tank mode 0, setup tank defs to match unit tank option
            for i = 1, tmp_cfg.UnitCount do
                tmp_cfg.FacilityTankDefs[i] = tri(tmp_cfg.CoolingConfig[i].TankConnection, 1, 0)
            end

            tmp_cfg.FacilityTankList, tmp_cfg.FacilityTankConns = facility.generate_tank_list_and_conns(tmp_cfg.FacilityTankMode, tmp_cfg.FacilityTankDefs)

            self.draw_fluid_ops()

            fac_pane.set_value(7)
        end
    end

    PushButton{parent=fac_c_3,x=1,y=14,text="\x1b Back",callback=function()fac_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_3,x=44,y=14,text="Next \x1a",callback=submit_en_fac_tank,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Facility Tank Connections

    TextBox{parent=fac_c_4,x=1,y=1,height=4,text="Please set unit connections to dynamic tanks, selecting at least one facility tank. The layout for facility tanks will be configured next."}

    for i = 1, 4 do
        local val = math.max(1, ini_cfg.FacilityTankDefs[i] or 2)
        local div = Div{parent=fac_c_4,x=1,y=3+(2*i),height=2}

        TextBox{parent=div,x=1,y=1,width=33,text="Unit "..i.." will be connected to..."}
        TextBox{parent=div,x=6,y=2,width=3,text="..."}
        local tank_opt = Radio2D{parent=div,x=9,y=2,rows=1,columns=2,default=val,options={"its own Unit Tank","a Facility Tank"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
        local no_tank = TextBox{parent=div,x=9,y=2,width=34,text="no tank (as you set two steps ago)",fg_bg=cpair(colors.gray,colors.lightGray),hidden=true}

        tool_ctl.tank_elems[i] = { div = div, tank_opt = tank_opt, no_tank = no_tank }
    end

    local tank_err = TextBox{parent=fac_c_4,x=8,y=14,width=33,text="You selected no facility tanks.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

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

        self.vis_draw(tmp_cfg.FacilityTankMode)

        if any_fac then
            tank_err.hide(true)
            fac_pane.set_value(5)
        else tank_err.show() end
    end

    PushButton{parent=fac_c_4,x=1,y=14,text="\x1b Back",callback=function()fac_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_4,x=44,y=14,text="Next \x1a",callback=submit_tank_defs,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Facility Tank Mode

    TextBox{parent=fac_c_5,x=1,y=1,text="Please select your dynamic tank layout."}
    TextBox{parent=fac_c_5,x=12,y=3,text="Facility Tanks             Unit Tanks",fg_bg=g_lg_fg_bg}

    --#region Tank Layout Visualizer

    local pipe_cpair = cpair(colors.blue,colors.lightGray)

    local vis = Div{parent=fac_c_5,x=14,y=5,height=7}

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
    function self.vis_draw(mode)
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
        self.vis_draw(mode)
    end

    local tank_modes = { "Mode 1", "Mode 2", "Mode 3", "Mode 4", "Mode 5", "Mode 6", "Mode 7", "Mode 8" }
    tool_ctl.tank_mode = RadioButton{parent=fac_c_5,x=1,y=4,callback=change_mode,default=math.max(1,ini_cfg.FacilityTankMode),options=tank_modes,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow}

    --#endregion

    local function next_from_tank_mode()
        -- determine tank list and connections
        tmp_cfg.FacilityTankList, tmp_cfg.FacilityTankConns = facility.generate_tank_list_and_conns(tmp_cfg.FacilityTankMode, tmp_cfg.FacilityTankDefs)

        self.draw_fluid_ops()

        fac_pane.set_value(7)
    end

    PushButton{parent=fac_c_5,x=1,y=14,text="\x1b Back",callback=function()fac_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_5,x=44,y=14,text="Next \x1a",callback=next_from_tank_mode,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    PushButton{parent=fac_c_5,x=8,y=14,min_width=7,text="About",callback=function()fac_pane.set_value(6)end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Facility Tank Mode About

    TextBox{parent=fac_c_6,height=3,text="This visualization tool shows the pipe connections required for a particular dynamic tank configuration you have selected."}
    TextBox{parent=fac_c_6,y=5,height=4,text="Examples: A U2 tank should be configured on an RTU as the dynamic tank for unit #2. An F3 tank should be configured on an RTU as the #3 dynamic tank for the facility."}
    TextBox{parent=fac_c_6,y=10,height=3,text="Some modes may look the same if you are not using 4 total reactor units. The wiki has details. Modes that look the same will function the same.",fg_bg=g_lg_fg_bg}

    PushButton{parent=fac_c_6,x=1,y=14,text="\x1b Back",callback=function()fac_pane.set_value(5)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Dynamic Tank Fluid Types

    TextBox{parent=fac_c_7,height=3,text="Specify each tank's coolant type, for display use only. Water is the only option if one or more of the connected units is water cooled."}

    local tank_fluid_list = Div{parent=fac_c_7,x=1,y=5,height=8}

    function self.draw_fluid_ops()
        tank_fluid_list.remove_all()

        local tank_list = tmp_cfg.FacilityTankList
        local tank_conns = tmp_cfg.FacilityTankConns

        local next_f = 1

        for i = 1, #tank_list do
            local type = tmp_cfg.TankFluidTypes[i]

            if type == 0 then type = 1 end

            self.tank_fluid_opts[i] = nil

            if tank_list[i] == 1 then
                local row = Div{parent=tank_fluid_list,height=2}

                TextBox{parent=row,width=11,text="Unit Tank "..i}
                TextBox{parent=row,text="Connected to: Unit "..i,fg_bg=cpair(colors.gray,colors.lightGray)}

                local tank_fluid = Radio2D{parent=row,x=34,y=1,rows=1,columns=2,default=type,options={"Water","Sodium"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}

                if tmp_cfg.CoolingConfig[i].BoilerCount == 0 then
                    tank_fluid.set_value(1)
                    tank_fluid.disable()
                end

                self.tank_fluid_opts[i] = tank_fluid
            elseif tank_list[i] == 2 then
                local row = Div{parent=tank_fluid_list,height=2}

                TextBox{parent=row,width=15,text="Facility Tank "..next_f}

                local conns = ""
                local any_bwr = false

                for u = 1, #tank_conns do
                    if tank_conns[u] == i then
                        conns = conns .. tri(conns == "", "", ", ") .. "Unit " .. u
                        any_bwr = any_bwr or (tmp_cfg.CoolingConfig[u].BoilerCount == 0)
                    end
                end

                TextBox{parent=row,text="Connected to: "..conns,fg_bg=cpair(colors.gray,colors.lightGray)}

                local tank_fluid = Radio2D{parent=row,x=34,y=1,rows=1,columns=2,default=type,options={"Water","Sodium"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.yellow,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}

                if any_bwr then
                    tank_fluid.set_value(1)
                    tank_fluid.disable()
                end

                self.tank_fluid_opts[i] = tank_fluid

                next_f = next_f + 1
            end
        end
    end

    local function back_from_fluids()
        fac_pane.set_value(tri(tmp_cfg.FacilityTankMode == 0, 3, 5))
    end

    local function submit_tank_fluids()
        tmp_cfg.TankFluidTypes = {}

        for i = 1, #tmp_cfg.FacilityTankList do
            if self.tank_fluid_opts[i] ~= nil then
                tmp_cfg.TankFluidTypes[i] = self.tank_fluid_opts[i].get_value()
            else
                tmp_cfg.TankFluidTypes[i] = 0
            end
        end

        fac_pane.set_value(8)
    end

    PushButton{parent=fac_c_7,x=1,y=14,text="\x1b Back",callback=back_from_fluids,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_7,x=44,y=14,text="Next \x1a",callback=submit_tank_fluids,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Auxiliary Coolant

    TextBox{parent=fac_c_8,height=5,text="Auxiliary water coolant can be enabled for units to provide extra water during turbine ramp-up. For water cooled reactors, this goes to the reactor. For sodium cooled reactors, water goes to the boiler."}

    for i = 1, 4 do
        local line = Div{parent=fac_c_8,x=1,y=7+i,height=1}

        TextBox{parent=line,text="Unit "..i.." -",width=8}
        local aux_cool = Checkbox{parent=line,x=10,y=1,label="Has Auxiliary Coolant",default=ini_cfg.AuxiliaryCoolant[i],box_fg_bg=cpair(colors.yellow,colors.black)}

        tool_ctl.aux_cool_elems[i] = { line = line, enable = aux_cool }
    end

    local function submit_aux_cool()
        tmp_cfg.AuxiliaryCoolant = {}

        for i = 1, tmp_cfg.UnitCount do
            tmp_cfg.AuxiliaryCoolant[i] = tool_ctl.aux_cool_elems[i].enable.get_value()
        end

        fac_pane.set_value(9)
    end

    PushButton{parent=fac_c_8,x=1,y=14,text="\x1b Back",callback=function()fac_pane.set_value(7)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_8,x=44,y=14,text="Next \x1a",callback=submit_aux_cool,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Extended Idling

    TextBox{parent=fac_c_9,height=6,text="Charge control provides automatic control to maintain an induction matrix charge level. In order to have smoother control, reactors that were activated will be held on at 0.01 mB/t for a short period before allowing them to turn off. This minimizes overshooting the charge target."}
    TextBox{parent=fac_c_9,y=8,height=3,text="You can extend this to a full minute to minimize reactors flickering on/off, but there may be more overshoot of the target."}

    local ext_idling = Checkbox{parent=fac_c_9,x=1,y=12,label="Enable Extended Idling",default=ini_cfg.ExtChargeIdling,box_fg_bg=cpair(colors.yellow,colors.black)}

    local function submit_idling()
        tmp_cfg.ExtChargeIdling = ext_idling.get_value()
        main_pane.set_value(3)
    end

    PushButton{parent=fac_c_9,x=1,y=14,text="\x1b Back",callback=function()fac_pane.set_value(8)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_9,x=44,y=14,text="Next \x1a",callback=submit_idling,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#endregion

    return fac_pane
end

return facility
