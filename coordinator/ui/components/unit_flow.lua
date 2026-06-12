--
-- Basic Unit Flow Overview
--

local types             = require("scada-common.types")
local util              = require("scada-common.util")

local ioctl             = require("coordinator.ioctl")

local style             = require("coordinator.ui.style")

local waste_view        = require("coordinator.ui.components.waste")

local core              = require("graphics.core")

local Div               = require("graphics.elements.Div")
local PipeNetwork       = require("graphics.elements.PipeNetwork")
local TextBox           = require("graphics.elements.TextBox")

local Rectangle         = require("graphics.elements.Rectangle")

local DataIndicator     = require("graphics.elements.indicators.DataIndicator")

local TriIndicatorLight = require("graphics.elements.indicators.TriIndicatorLight")

local COOLANT_TYPE = types.COOLANT_TYPE

local ALIGN = core.ALIGN

local sprintf = util.sprintf

local border = core.border
local cpair = core.cpair
local pipe = core.pipe

local wh_gray = style.wh_gray
local lg_gray = style.lg_gray

-- make a new unit flow window
---@param parent Container parent
---@param x integer top left x
---@param y integer top left y
---@param wide boolean whether to render wide version
---@param fac_waste boolean true if using facility waste
---@param unit_id integer unit index
local function make(parent, x, y, wide, fac_waste, unit_id)
    local s_field = style.theme.field_box

    local text_c = style.text_colors
    local lu_c = style.lu_colors

    local height = 16

    local fac  = ioctl.get_db().facility
    local unit = ioctl.get_db().units[unit_id]

    local tank_conns = fac.tank_conns
    local tank_types = fac.tank_fluid_types

    local v_start = 1 + ((unit.unit_id - 1) * 6)
    local prv_start = 1 + ((unit.unit_id - 1) * 3)
    local v_fields = { "pu", "po", "pl", "am" }
    local v_names = {
        sprintf("PV%02d-PU", v_start),
        sprintf("PV%02d-PO", v_start + 1),
        sprintf("PV%02d-PL", v_start + 2),
        sprintf("PV%02d-AM", v_start + 3),
        sprintf("PRV%02d", prv_start),
        sprintf("PRV%02d", prv_start + 1),
        sprintf("PRV%02d", prv_start + 2)
    }

    assert(parent.get_height() >= (y + height), "flow display not of sufficient vertical resolution (add an additional row of monitors) " .. y .. "," .. parent.get_height())

    local function _wide(a, b) return util.trinary(wide, a, b) end

    -- bounding box div
    local root = Div{parent=parent,x=x,y=y,width=_wide(136, 114),height=height}

    ------------------
    -- COOLING LOOP --
    ------------------

    local reactor = Rectangle{parent=root,y=1,border=border(1,colors.gray,true),width=19,height=5,fg_bg=wh_gray}
    TextBox{parent=reactor,y=1,text="FISSION REACTOR",alignment=ALIGN.CENTER}
    TextBox{parent=reactor,y=3,text="UNIT #"..unit.unit_id,alignment=ALIGN.CENTER}
    TextBox{parent=root,x=19,y=2,text="\x1b \x80 \x1a",width=1,height=3,fg_bg=lg_gray}
    TextBox{parent=root,x=3,y=5,text="\x19",width=1,fg_bg=lg_gray}

    local rc_pipes = {}

    if unit.num_boilers > 0 then
        table.insert(rc_pipes, pipe(0, 1, _wide(28, 19), 1, colors.lightBlue, true))
        table.insert(rc_pipes, pipe(0, 3, _wide(28, 19), 3, colors.orange, true))
        table.insert(rc_pipes, pipe(_wide(46, 39), 1, _wide(72, 58), 1, colors.blue, true))
        table.insert(rc_pipes, pipe(_wide(46, 39), 3, _wide(72, 58), 3, colors.white, true))

        if unit.aux_coolant then
            local em_water = fac.tank_fluid_types[fac.tank_conns[unit_id]] == COOLANT_TYPE.WATER
            local offset = util.trinary(unit.has_tank and em_water, 3, 0)
            table.insert(rc_pipes, pipe(_wide(51, 41) + offset, 0, _wide(51, 41) + offset, 0, colors.blue, true))
        end
    else
        table.insert(rc_pipes, pipe(0, 1, _wide(72, 58), 1, colors.blue, true))
        table.insert(rc_pipes, pipe(0, 3, _wide(72, 58), 3, colors.white, true))

        if unit.aux_coolant then
            table.insert(rc_pipes, pipe(8, 0, 8, 0, colors.blue, true))
        end
    end

    if unit.has_tank then
        local is_water = tank_types[tank_conns[unit_id]] == COOLANT_TYPE.WATER
        -- emergency coolant connection x point
        local emc_x = util.trinary(is_water and (unit.num_boilers > 0), 42, 3)

        table.insert(rc_pipes, pipe(emc_x, 1, emc_x, 0, util.trinary(is_water, colors.blue, colors.lightBlue), true, true))
    end

    local prv_yo = math.max(3 - unit.num_turbines, 0)
    for i = 1, unit.num_turbines do
        local py = 2 * (i - 1) + prv_yo
        table.insert(rc_pipes, pipe(_wide(92, 78), py, _wide(104, 83), py, colors.white, true))
    end

    PipeNetwork{parent=root,x=20,y=1,pipes=rc_pipes,bg=style.theme.bg}

    if unit.num_boilers > 0 then
        local cc_rate = DataIndicator{parent=root,x=_wide(25,22),y=3,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=s_field}
        local hc_rate = DataIndicator{parent=root,x=_wide(25,22),y=5,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=s_field}

        cc_rate.register(unit.unit_ps, "boiler_boil_sum", function (sum) cc_rate.update(sum * 10) end)
        hc_rate.register(unit.unit_ps, "heating_rate", hc_rate.update)

        local boiler = Rectangle{parent=root,x=_wide(47,40),y=1,border=border(1,colors.gray,true),width=19,height=5,fg_bg=wh_gray}
        TextBox{parent=boiler,y=1,text="THERMO-ELECTRIC",alignment=ALIGN.CENTER}
        TextBox{parent=boiler,y=3,text=util.trinary(unit.num_boilers>1,"BOILERS","BOILER"),alignment=ALIGN.CENTER}
        TextBox{parent=root,x=_wide(47,40),y=2,text="\x1b \x80 \x1a",width=1,height=3,fg_bg=lg_gray}
        TextBox{parent=root,x=_wide(65,58),y=2,text="\x1b \x80 \x1a",width=1,height=3,fg_bg=lg_gray}

        local wt_rate = DataIndicator{parent=root,x=_wide(71,61),y=3,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=s_field}
        local st_rate = DataIndicator{parent=root,x=_wide(71,61),y=5,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=s_field}

        wt_rate.register(unit.unit_ps, "turbine_flow_sum", wt_rate.update)
        st_rate.register(unit.unit_ps, "boiler_boil_sum", st_rate.update)
    else
        local wt_rate = DataIndicator{parent=root,x=28,y=3,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=s_field}
        local st_rate = DataIndicator{parent=root,x=28,y=5,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=s_field}

        wt_rate.register(unit.unit_ps, "turbine_flow_sum", wt_rate.update)
        st_rate.register(unit.unit_ps, "heating_rate", st_rate.update)
    end

    local turbine = Rectangle{parent=root,x=_wide(93,79),y=1,border=border(1,colors.gray,true),width=19,height=5,fg_bg=wh_gray}
    TextBox{parent=turbine,y=1,text="STEAM TURBINE",alignment=ALIGN.CENTER}
    TextBox{parent=turbine,y=3,text=util.trinary(unit.num_turbines>1,"GENERATORS","GENERATOR"),alignment=ALIGN.CENTER}
    TextBox{parent=root,x=_wide(93,79),y=2,text="\x1b \x80 \x1a",width=1,height=3,fg_bg=lg_gray}

    for i = 1, unit.num_turbines do
        local ry = 1 + (2 * (i - 1)) + prv_yo
        TextBox{parent=root,x=_wide(125,103),y=ry,text="\x10\x11\x7f",fg_bg=text_c,width=3}
        local state = TriIndicatorLight{parent=root,x=_wide(129,107),y=ry,label=v_names[i+4],c1=style.ind_bkg,c2=style.ind_yel.fgd,c3=style.ind_red.fgd}
        state.register(unit.turbine_ps_tbl[i], "SteamDumpOpen", state.update)
    end

    ----------------------
    -- WASTE PROCESSING --
    ----------------------

    local waste = Div{parent=root,x=3,y=6}

    PipeNetwork{parent=waste,y=1,pipes={pipe(0,0,13,1,colors.brown,true)},bg=style.theme.bg}

    local waste_rate = DataIndicator{parent=waste,x=util.trinary(fac_waste,2,1),y=3,lu_colors=lu_c,label="",unit="mB/t",format="%7.2f",value=0,width=12,fg_bg=s_field}
    waste_rate.register(unit.unit_ps, "act_burn_rate", waste_rate.update)

    if fac_waste then
        TextBox{parent=waste,x=16,y=2,text="\x1a",fg_bg=cpair(colors.brown,text_c.bkg),width=1}
    else
        waste_view(waste, 13, 1, wide, fac_waste, v_fields, v_names, unit.unit_ps)
    end

    return root
end

return make
