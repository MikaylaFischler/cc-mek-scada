--
-- Flow Monitor GUI
--

local types          = require("scada-common.types")
local util           = require("scada-common.util")

local iocontrol      = require("coordinator.iocontrol")

local style          = require("coordinator.ui.style")

local unit_flow      = require("coordinator.ui.components.unit_flow")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local PipeNetwork    = require("graphics.elements.PipeNetwork")
local Rectangle      = require("graphics.elements.Rectangle")
local TextBox        = require("graphics.elements.TextBox")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local HorizontalBar  = require("graphics.elements.indicators.HorizontalBar")
local IndicatorLight = require("graphics.elements.indicators.IndicatorLight")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")

local CONTAINER_MODE = types.CONTAINER_MODE
local COOLANT_TYPE = types.COOLANT_TYPE

local ALIGN = core.ALIGN

local cpair = core.cpair
local border = core.border
local pipe = core.pipe

local wh_gray = style.wh_gray

-- create new flow view
---@param main DisplayBox main displaybox
local function init(main)
    local s_hi_bright = style.theme.highlight_box_bright
    local s_field = style.theme.field_box
    local text_col = style.text_colors
    local lu_col = style.lu_colors
    local lu_c_d = style.lu_colors_dark

    local facility = iocontrol.get_db().facility
    local units = iocontrol.get_db().units

    local tank_defs  = facility.tank_defs
    local tank_conns = facility.tank_conns
    local tank_list  = facility.tank_list
    local tank_types = facility.tank_fluid_types

    -- window header message
    local header = TextBox{parent=main,y=1,text="Monitor de Fluxo de Refrigera\xe7\xe3o e Res\xedduos",alignment=ALIGN.CENTER,fg_bg=style.theme.header}
    -- max length example: "01:23:45 AM - Wednesday, September 28 2022"
    local datetime = TextBox{parent=main,x=(header.get_width()-42),y=1,text="",alignment=ALIGN.RIGHT,width=42,fg_bg=style.theme.header}

    datetime.register(facility.ps, "date_time", datetime.set_value)

    local po_pipes = {}
    local emcool_pipes = {}

    -- get the y offset for this unit index
    ---@param idx integer unit index
    local function y_ofs(idx) return ((idx - 1) * 20) end

    -- get the coolant color
    ---@param idx integer tank index
    local function c_clr(idx) return util.trinary(tank_types[tank_conns[idx]] == COOLANT_TYPE.WATER, colors.blue, colors.lightBlue) end

    -- determinte facility tank start/end from the definitions list
    ---@param start_idx integer start index of table iteration
    ---@param end_idx integer end index of table iteration
    local function find_fdef(start_idx, end_idx)
        local first, last = 4, 0
        for i = start_idx, end_idx do
            if tank_defs[i] == 2 then
                last = i
                if i < first then first = i end
            end
        end
        return first, last
    end

    if facility.tank_mode == 0 or facility.tank_mode == 8 then
        -- (0) tanks belong to reactor units OR (8) 4 total facility tanks (A B C D)
        for i = 1, facility.num_units do
            if units[i].has_tank then
                local y = y_ofs(i)
                local color = c_clr(i)

                table.insert(emcool_pipes, pipe(2, y, 2, y + 3, color, true))
                table.insert(emcool_pipes, pipe(2, y, 21, y, color, true))

                local x = util.trinary((tank_types[tank_conns[i]] == COOLANT_TYPE.SODIUM) or (units[i].num_boilers == 0), 45, 84)
                table.insert(emcool_pipes, pipe(21, y, x, y + 2, color, true, true))
            end
        end
    else
        -- setup connections for units with emergency coolant, always the same
        for i = 1, #tank_defs do
            if tank_defs[i] > 0 then
                local y = y_ofs(i)
                local color = c_clr(i)

                if tank_defs[i] == 2 then
                    table.insert(emcool_pipes, pipe(1, y, 21, y, color, true))
                else
                    table.insert(emcool_pipes, pipe(2, y, 2, y + 3, color, true))
                    table.insert(emcool_pipes, pipe(2, y, 21, y, color, true))
                end

                local x = util.trinary((tank_types[tank_conns[i]] == COOLANT_TYPE.SODIUM) or (units[i].num_boilers == 0), 45, 84)
                table.insert(emcool_pipes, pipe(21, y, x, y + 2, color, true, true))
            end
        end

        if facility.tank_mode == 1 then
            -- (1) 1 total facility tank (A A A A)
            local first_fdef, last_fdef = find_fdef(1, #tank_defs)

            for i = 1, #tank_defs do
                local y = y_ofs(i)

                if i == first_fdef then
                    table.insert(emcool_pipes, pipe(0, y, 1, y + 5, c_clr(i), true))
                elseif i > first_fdef then
                    if i == last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y, c_clr(first_fdef), true))
                    elseif i < last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y + 5, c_clr(first_fdef), true))
                    end
                end
            end
        elseif facility.tank_mode == 2 then
            -- (2) 2 total facility tanks (A A A B)
            local first_fdef, last_fdef = find_fdef(1, math.min(3, #tank_defs))

            for i = 1, #tank_defs do
                local y = y_ofs(i)
                local color = c_clr(first_fdef)

                if i == 4 then
                    if tank_defs[i] == 2 then
                        table.insert(emcool_pipes, pipe(0, y, 1, y + 5, c_clr(i), true))
                    end
                elseif i == first_fdef then
                    table.insert(emcool_pipes, pipe(0, y, 1, y + 5, color, true))
                elseif i > first_fdef then
                    if i == last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y, color, true))
                    elseif i < last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y + 5, color, true))
                    end
                end
            end
        elseif facility.tank_mode == 3 then
            -- (3) 2 total facility tanks (A A B B)
            for _, a in pairs({ 1, 3 }) do
                local b = a + 1
                if tank_defs[a] == 2 then
                    table.insert(emcool_pipes, pipe(0, y_ofs(a), 1, y_ofs(a) + 6, c_clr(a), true))
                    if tank_defs[b] == 2 then
                        table.insert(emcool_pipes, pipe(0, y_ofs(b) - 13, 1, y_ofs(b), c_clr(a), true))
                    end
                elseif tank_defs[b] == 2 then
                    table.insert(emcool_pipes, pipe(0, y_ofs(b), 1, y_ofs(b) + 6, c_clr(b), true))
                end
            end
        elseif facility.tank_mode == 4 then
            -- (4) 2 total facility tanks (A B B B)
            local first_fdef, last_fdef = find_fdef(2, #tank_defs)

            for i = 1, #tank_defs do
                local y = y_ofs(i)
                local color = c_clr(first_fdef)

                if i == 1 then
                    if tank_defs[i] == 2 then
                        table.insert(emcool_pipes, pipe(0, y, 1, y + 5, c_clr(i), true))
                    end
                elseif i == first_fdef then
                    table.insert(emcool_pipes, pipe(0, y, 1, y + 5, color, true))
                elseif i > first_fdef then
                    if i == last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y, color, true))
                    elseif i < last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y + 5, color, true))
                    end
                end
            end
        elseif facility.tank_mode == 5 then
            -- (5) 3 total facility tanks (A A B C)
            local first_fdef, last_fdef = find_fdef(1, math.min(2, #tank_defs))

            for i = 1, #tank_defs do
                local y = y_ofs(i)
                local color = c_clr(first_fdef)

                if i == 3 or i == 4 then
                    if tank_defs[i] == 2 then
                        table.insert(emcool_pipes, pipe(0, y, 1, y + 5, c_clr(i), true))
                    end
                elseif i == first_fdef then
                    table.insert(emcool_pipes, pipe(0, y, 1, y + 5, color, true))
                elseif i > first_fdef then
                    if i == last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y, color, true))
                    elseif i < last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y + 5, color, true))
                    end
                end
            end
        elseif facility.tank_mode == 6 then
            -- (6) 3 total facility tanks (A B B C)
            local first_fdef, last_fdef = find_fdef(2, math.min(3, #tank_defs))

            for i = 1, #tank_defs do
                local y = y_ofs(i)
                local color = c_clr(first_fdef)

                if i == 1 or i == 4 then
                    if tank_defs[i] == 2 then
                        table.insert(emcool_pipes, pipe(0, y, 1, y + 5, c_clr(i), true))
                    end
                elseif i == first_fdef then
                    table.insert(emcool_pipes, pipe(0, y, 1, y + 5, color, true))
                elseif i > first_fdef then
                    if i == last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y, color, true))
                    elseif i < last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y + 5, color, true))
                    end
                end
            end
        elseif facility.tank_mode == 7 then
            -- (7) 3 total facility tanks (A B C C)
            local first_fdef, last_fdef = find_fdef(3, #tank_defs)

            for i = 1, #tank_defs do
                local y = y_ofs(i)
                local color = c_clr(first_fdef)

                if i == 1 or i == 2 then
                    if tank_defs[i] == 2 then
                        table.insert(emcool_pipes, pipe(0, y, 1, y + 5, c_clr(i), true))
                    end
                elseif i == first_fdef then
                    table.insert(emcool_pipes, pipe(0, y, 1, y + 5, color, true))
                elseif i > first_fdef then
                    if i == last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y, color, true))
                    elseif i < last_fdef then
                        table.insert(emcool_pipes, pipe(0, y - 14, 0, y + 5, color, true))
                    end
                end
            end
        end
    end

    local flow_x = 3
    if #emcool_pipes > 0 then
        flow_x = 25
        PipeNetwork{parent=main,x=2,y=3,pipes=emcool_pipes,bg=style.theme.bg}
    end

    for i = 1, facility.num_units do
        local y_offset = y_ofs(i)
        unit_flow(main, flow_x, 5 + y_offset, #emcool_pipes == 0, i)
        table.insert(po_pipes, pipe(0, 3 + y_offset, 4, 0, colors.cyan, true, true))
        util.nop()
    end

    PipeNetwork{parent=main,x=139,y=15,pipes=po_pipes,bg=style.theme.bg}

    -----------------
    -- tank valves --
    -----------------

    local next_f_id = 1

    for i = 1, #tank_defs do
        if tank_defs[i] > 0 then
            local vy = 3 + y_ofs(i)

            TextBox{parent=main,x=12,y=vy,text="\x10\x11",fg_bg=text_col,width=2}

            local conn = IndicatorLight{parent=main,x=9,y=vy+1,label=util.sprintf("PV%02d-EMC", (i * 6) - 1),colors=style.ind_grn}
            local open = IndicatorLight{parent=main,x=9,y=vy+2,label="OPEN",colors=style.ind_wht}

            conn.register(units[i].unit_ps, "V_emc_conn", conn.update)
            open.register(units[i].unit_ps, "V_emc_state", open.update)
        end
    end

    ------------------------------
    -- auxiliary coolant valves --
    ------------------------------

    for i = 1, facility.num_units do
        if units[i].aux_coolant then
            local vx
            local vy = 3 + y_ofs(i)

            if #emcool_pipes == 0 then
                vx = util.trinary(units[i].num_boilers == 0, 36, 79)
            else
                local em_water = tank_types[tank_conns[i]] == COOLANT_TYPE.WATER
                vx = util.trinary(units[i].num_boilers == 0, 58, util.trinary(units[i].has_tank and em_water, 94, 91))
            end

            PipeNetwork{parent=main,x=vx-6,y=vy,pipes={pipe(0,1,9,0,colors.blue,true)},bg=style.theme.bg}

            TextBox{parent=main,x=vx,y=vy,text="\x10\x11",fg_bg=text_col,width=2}
            TextBox{parent=main,x=vx+5,y=vy,text="\x1b",fg_bg=cpair(colors.blue,text_col.bkg),width=1}

            local conn = IndicatorLight{parent=main,x=vx-3,y=vy+1,label=util.sprintf("PV%02d-AUX", i * 6),colors=style.ind_grn}
            local open = IndicatorLight{parent=main,x=vx-3,y=vy+2,label="OPEN",colors=style.ind_wht}

            conn.register(units[i].unit_ps, "V_aux_conn", conn.update)
            open.register(units[i].unit_ps, "V_aux_state", open.update)
        end
    end

    -------------------
    -- dynamic tanks --
    -------------------

    for i = 1, #tank_list do
        if tank_list[i] > 0 then
            local id = "U-" .. i
            local f_id = next_f_id
            if tank_list[i] == 2 then
                id = "F-" .. next_f_id
                next_f_id = next_f_id + 1
            end

            local y_offset = y_ofs(i)

            local tank = Div{parent=main,x=3,y=7+y_offset,width=20,height=14}

            TextBox{parent=tank,text=" ",x=1,y=1,fg_bg=style.lg_gray}
            TextBox{parent=tank,text="TANQUE DIN\xc3MICO "..id,alignment=ALIGN.CENTER,fg_bg=style.wh_gray}

            local tank_box = Rectangle{parent=tank,border=border(1,colors.gray,true),width=20,height=12}

            local status = StateIndicator{parent=tank_box,x=3,y=1,states=style.dtank.states,value=1,min_width=14}

            TextBox{parent=tank_box,x=2,y=3,text="Encher",width=10,fg_bg=style.label}
            local tank_pcnt = DataIndicator{parent=tank_box,x=10,y=3,label="",format="%5.2f",value=100,unit="%",lu_colors=lu_col,width=8,fg_bg=text_col}
            local tank_amnt = DataIndicator{parent=tank_box,x=2,label="",format="%13d",value=0,commas=true,unit="mB",lu_colors=lu_col,width=16,fg_bg=s_field}

            local is_water = tank_types[i] == COOLANT_TYPE.WATER

            TextBox{parent=tank_box,x=2,y=6,text=util.trinary(is_water,"Water","Sodium").." Level",width=12,fg_bg=style.label}
            local level = HorizontalBar{parent=tank_box,x=2,y=7,bar_fg_bg=cpair(util.trinary(is_water,colors.blue,colors.lightBlue),colors.gray),height=1,width=16}

            TextBox{parent=tank_box,x=2,y=9,text="Modo Ent./Said.",width=11,fg_bg=style.label}
            local can_fill = IndicatorLight{parent=tank_box,x=2,y=10,label="FILL",colors=style.ind_wht}
            local can_empty = IndicatorLight{parent=tank_box,x=10,y=10,label="EMPTY",colors=style.ind_wht}

            local function _can_fill(mode)
                can_fill.update((mode == CONTAINER_MODE.BOTH) or (mode == CONTAINER_MODE.FILL))
            end

            local function _can_empty(mode)
                can_empty.update((mode == CONTAINER_MODE.BOTH) or (mode == CONTAINER_MODE.EMPTY))
            end

            if tank_list[i] == 1 then
                status.register(units[i].tank_ps_tbl[1], "computed_status", status.update)
                tank_pcnt.register(units[i].tank_ps_tbl[1], "fill", function (f) tank_pcnt.update(f * 100) end)
                tank_amnt.register(units[i].tank_ps_tbl[1], "stored", function (sto) tank_amnt.update(sto.amount) end)
                level.register(units[i].tank_ps_tbl[1], "fill", level.update)
                can_fill.register(units[i].tank_ps_tbl[1], "container_mode", _can_fill)
                can_empty.register(units[i].tank_ps_tbl[1], "container_mode", _can_empty)
            else
                status.register(facility.tank_ps_tbl[f_id], "computed_status", status.update)
                tank_pcnt.register(facility.tank_ps_tbl[f_id], "fill", function (f) tank_pcnt.update(f * 100) end)
                tank_amnt.register(facility.tank_ps_tbl[f_id], "stored", function (sto) tank_amnt.update(sto.amount) end)
                level.register(facility.tank_ps_tbl[f_id], "fill", level.update)
                can_fill.register(facility.tank_ps_tbl[f_id], "container_mode", _can_fill)
                can_empty.register(facility.tank_ps_tbl[f_id], "container_mode", _can_empty)
            end
        end
    end

    util.nop()

    ---------
    -- SPS --
    ---------

    local sps = Div{parent=main,x=140,y=3,height=12}

    TextBox{parent=sps,text=" ",width=24,x=1,y=1,fg_bg=style.lg_gray}
    TextBox{parent=sps,text="SPS",alignment=ALIGN.CENTER,width=24,fg_bg=wh_gray}

    local sps_box = Rectangle{parent=sps,border=border(1,colors.gray,true),width=24,height=10}

    local status = StateIndicator{parent=sps_box,x=5,y=1,states=style.sps.states,value=1,min_width=14}

    status.register(facility.sps_ps_tbl[1], "computed_status", status.update)

    TextBox{parent=sps_box,x=2,y=3,text="Taxa de Entrada",width=10,fg_bg=style.label}
    local sps_in = DataIndicator{parent=sps_box,x=2,label="",format="%15.2f",value=0,unit="mB/t",lu_colors=lu_col,width=20,fg_bg=s_field}

    sps_in.register(facility.ps, "po_am_rate", sps_in.update)

    TextBox{parent=sps_box,x=2,y=6,text="Taxa de Produ\xe7\xe3o",width=15,fg_bg=style.label}
    local sps_rate = DataIndicator{parent=sps_box,x=2,label="",format="%15d",value=0,unit="\xb5B/t",lu_colors=lu_col,width=20,fg_bg=s_field}

    sps_rate.register(facility.sps_ps_tbl[1], "process_rate", function (r) sps_rate.update(r * 1000) end)

    ----------------
    -- statistics --
    ----------------

    TextBox{parent=main,x=145,y=16,text="RES\xcdDUO BRUTO",alignment=ALIGN.CENTER,width=19,fg_bg=wh_gray}
    local raw_waste  = Rectangle{parent=main,x=145,y=17,border=border(1,colors.gray,true),width=19,height=3,thin=true,fg_bg=s_hi_bright}
    local sum_raw_waste = DataIndicator{parent=raw_waste,lu_colors=lu_c_d,label="SUM",unit="mB/t",format="%8.2f",value=0,width=17}

    sum_raw_waste.register(facility.ps, "burn_sum", sum_raw_waste.update)

    TextBox{parent=main,x=145,y=21,text="PROC. DE RES\xcdDUO",alignment=ALIGN.CENTER,width=19,fg_bg=wh_gray}
    local pr_waste  = Rectangle{parent=main,x=145,y=22,border=border(1,colors.gray,true),width=19,height=5,thin=true,fg_bg=s_hi_bright}
    local pu = DataIndicator{parent=pr_waste,lu_colors=lu_c_d,label="Pu",unit="mB/t",format="%9.3f",value=0,width=17}
    local po = DataIndicator{parent=pr_waste,lu_colors=lu_c_d,label="Po",unit="mB/t",format="%9.2f",value=0,width=17}
    local popl = DataIndicator{parent=pr_waste,lu_colors=lu_c_d,label="PoPl",unit="mB/t",format="%7.2f",value=0,width=17}

    pu.register(facility.ps, "pu_rate", pu.update)
    po.register(facility.ps, "po_rate", po.update)
    popl.register(facility.ps, "po_pl_rate", popl.update)

    TextBox{parent=main,x=145,y=28,text="RES\xcdDUO USADO",alignment=ALIGN.CENTER,width=19,fg_bg=wh_gray}
    local sp_waste  = Rectangle{parent=main,x=145,y=29,border=border(1,colors.gray,true),width=19,height=3,thin=true,fg_bg=s_hi_bright}
    local sum_sp_waste = DataIndicator{parent=sp_waste,lu_colors=lu_c_d,label="SUM",unit="mB/t",format="%8.3f",value=0,width=17}

    sum_sp_waste.register(facility.ps, "spent_waste_rate", sum_sp_waste.update)
end

return init
