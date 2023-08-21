--
-- Basic Unit Flow Overview
--

local util              = require("scada-common.util")

local style             = require("coordinator.ui.style")

local core              = require("graphics.core")

local Div               = require("graphics.elements.div")
local PipeNetwork       = require("graphics.elements.pipenet")
local TextBox           = require("graphics.elements.textbox")

local Rectangle         = require("graphics.elements.rectangle")

local DataIndicator     = require("graphics.elements.indicators.data")

local IndicatorLight    = require("graphics.elements.indicators.light")
local TriIndicatorLight = require("graphics.elements.indicators.trilight")

local TEXT_ALIGN = core.TEXT_ALIGN

local sprintf = util.sprintf

local cpair = core.cpair
local border = core.border
local pipe = core.pipe

local wh_gray = style.wh_gray
local bw_fg_bg = style.bw_fg_bg
local text_c = style.text_colors
local lu_c = style.lu_colors

local ind_grn = style.ind_grn
local ind_wht = style.ind_wht

-- make a new unit flow window
---@param parent graphics_element parent
---@param x integer top left x
---@param y integer top left y
---@param wide boolean whether to render wide version
---@param unit ioctl_unit unit database entry
local function make(parent, x, y, wide, unit)
    local height = 16

    local v_start = 1 + ((unit.unit_id - 1) * 5)
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

    local lg_gray = cpair(colors.lightGray, colors.gray)

    ------------------
    -- COOLING LOOP --
    ------------------

    local reactor = Rectangle{parent=root,x=1,y=1,border=border(1,colors.gray,true),width=19,height=5,fg_bg=wh_gray}
    TextBox{parent=reactor,y=1,text="FISSION REACTOR",alignment=TEXT_ALIGN.CENTER,height=1}
    TextBox{parent=reactor,y=3,text="UNIT #"..unit.unit_id,alignment=TEXT_ALIGN.CENTER,height=1}
    TextBox{parent=root,x=19,y=2,text="\x1b \x80 \x1a",width=1,height=3,fg_bg=lg_gray}
    TextBox{parent=root,x=3,y=5,text="\x19",width=1,height=1,fg_bg=lg_gray}

    local rc_pipes = {}

    local emc_x = 42    -- emergency coolant connection x point

    if unit.num_boilers > 0 then
        table.insert(rc_pipes, pipe(0, 1, _wide(28, 19), 1, colors.lightBlue, true))
        table.insert(rc_pipes, pipe(0, 3, _wide(28, 19), 3, colors.orange, true))
        table.insert(rc_pipes, pipe(_wide(46 ,39), 1, _wide(72,58), 1, colors.blue, true))
        table.insert(rc_pipes, pipe(_wide(46,39), 3, _wide(72,58), 3, colors.white, true))
    else
        emc_x = 3
        table.insert(rc_pipes, pipe(0, 1, _wide(72,58), 1, colors.blue, true))
        table.insert(rc_pipes, pipe(0, 3, _wide(72,58), 3, colors.white, true))
    end

    if unit.has_tank then
        table.insert(rc_pipes, pipe(emc_x, 1, emc_x, 0, colors.blue, true, true))
    end

    local prv_yo = math.max(3 - unit.num_turbines, 0)
    for i = 1, unit.num_turbines do
        local py = 2 * (i - 1) + prv_yo
        table.insert(rc_pipes, pipe(_wide(92, 78), py, _wide(104, 83), py, colors.white, true))
    end

    PipeNetwork{parent=root,x=20,y=1,pipes=rc_pipes,bg=colors.lightGray}

    if unit.num_boilers > 0 then
        local cc_rate = DataIndicator{parent=root,x=_wide(25,22),y=5,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=bw_fg_bg}
        local hc_rate = DataIndicator{parent=root,x=_wide(25,22),y=3,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=bw_fg_bg}

        cc_rate.register(unit.unit_ps, "boil_sum", cc_rate.update)
        hc_rate.register(unit.unit_ps, "heating_rate", hc_rate.update)

        local boiler = Rectangle{parent=root,x=_wide(47,40),y=1,border=border(1, colors.gray, true),width=19,height=5,fg_bg=wh_gray}
        TextBox{parent=boiler,y=1,text="THERMO-ELECTRIC",alignment=TEXT_ALIGN.CENTER,height=1}
        TextBox{parent=boiler,y=3,text="BOILERS",alignment=TEXT_ALIGN.CENTER,height=1}
        TextBox{parent=root,x=_wide(47,40),y=2,text="\x1b \x80 \x1a",width=1,height=3,fg_bg=lg_gray}
        TextBox{parent=root,x=_wide(65,58),y=2,text="\x1b \x80 \x1a",width=1,height=3,fg_bg=lg_gray}

        local wt_rate = DataIndicator{parent=root,x=_wide(71,61),y=3,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=bw_fg_bg}
        local st_rate = DataIndicator{parent=root,x=_wide(71,61),y=5,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=bw_fg_bg}

        wt_rate.register(unit.unit_ps, "turbine_flow_sum", wt_rate.update)
        st_rate.register(unit.unit_ps, "boil_sum", st_rate.update)
    else
        local wt_rate = DataIndicator{parent=root,x=28,y=3,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=bw_fg_bg}
        local st_rate = DataIndicator{parent=root,x=28,y=5,lu_colors=lu_c,label="",unit="mB/t",format="%11.0f",value=0,commas=true,width=16,fg_bg=bw_fg_bg}

        wt_rate.register(unit.unit_ps, "turbine_flow_sum", wt_rate.update)
        st_rate.register(unit.unit_ps, "heating_rate", st_rate.update)
    end

    local turbine = Rectangle{parent=root,x=_wide(93,79),y=1,border=border(1, colors.gray, true),width=19,height=5,fg_bg=wh_gray}
    TextBox{parent=turbine,y=1,text="STEAM TURBINE",alignment=TEXT_ALIGN.CENTER,height=1}
    TextBox{parent=turbine,y=3,text=util.trinary(unit.num_turbines>1,"GENERATORS","GENERATOR"),alignment=TEXT_ALIGN.CENTER,height=1}
    TextBox{parent=root,x=_wide(93,79),y=2,text="\x1b \x80 \x1a",width=1,height=3,fg_bg=lg_gray}

    for i = 1, unit.num_turbines do
        local ry = 1 + (2 * (i - 1)) + prv_yo
        TextBox{parent=root,x=_wide(125,103),y=ry,text="\x10\x11\x7f",fg_bg=text_c,width=3,height=1}
        local state = TriIndicatorLight{parent=root,x=_wide(129,107),y=ry,label=v_names[i+4],c1=colors.gray,c2=colors.yellow,c3=colors.red}
        state.register(unit.turbine_ps_tbl[i], "SteamDumpOpen", state.update)
    end

    ----------------------
    -- WASTE PROCESSING --
    ----------------------

    local waste = Div{parent=root,x=3,y=6}

    local waste_pipes = {
        pipe(0, 0, _wide(19, 16), 1, colors.brown, true),
        pipe(_wide(14, 13), 1, _wide(19, 17), 5, colors.brown, true),
        pipe(_wide(22, 19), 1, _wide(49, 45), 1, colors.brown, true),
        pipe(_wide(22, 19), 5, _wide(28, 24), 5, colors.brown, true),

        pipe(_wide(64, 53), 1, _wide(95, 81), 1, colors.green, true),

        pipe(_wide(48, 43), 4, _wide(71, 61), 4, colors.cyan, true),
        pipe(_wide(66, 57), 4, _wide(71, 61), 8, colors.cyan, true),
        pipe(_wide(74, 63), 4, _wide(95, 81), 4, colors.cyan, true),
        pipe(_wide(74, 63), 8, _wide(133, 111), 8, colors.cyan, true),

        pipe(_wide(108, 94), 1, _wide(132, 110), 6, colors.black, true, true),
        pipe(_wide(108, 94), 4, _wide(111, 95), 1, colors.black, true, true),
        pipe(_wide(132, 110), 6, _wide(130, 108), 6, colors.black, true, true)
    }

    PipeNetwork{parent=waste,x=1,y=1,pipes=waste_pipes,bg=colors.lightGray}

    local function _valve(vx, vy, n)
        TextBox{parent=waste,x=vx,y=vy,text="\x10\x11",fg_bg=text_c,width=2,height=1}
        local conn = IndicatorLight{parent=waste,x=vx-3,y=vy+1,label=v_names[n],colors=ind_grn}
        local open = IndicatorLight{parent=waste,x=vx-3,y=vy+2,label="OPEN",colors=ind_wht}
        conn.register(unit.unit_ps, util.c("V_", v_fields[n], "_conn"), conn.update)
        open.register(unit.unit_ps, util.c("V_", v_fields[n], "_state"), open.update)
    end

    local function _machine(mx, my, name)
        local l = string.len(name) + 2
        TextBox{parent=waste,x=mx,y=my,text=string.rep("\x8f",l),alignment=TEXT_ALIGN.CENTER,fg_bg=lg_gray,width=l,height=1}
        TextBox{parent=waste,x=mx,y=my+1,text=name,alignment=TEXT_ALIGN.CENTER,fg_bg=wh_gray,width=l,height=1}
    end

    local waste_rate = DataIndicator{parent=waste,x=1,y=3,lu_colors=lu_c,label="",unit="mB/t",format="%7.2f",value=0,width=12,fg_bg=bw_fg_bg}
    local pu_rate = DataIndicator{parent=waste,x=_wide(82,70),y=3,lu_colors=lu_c,label="",unit="mB/t",format="%7.3f",value=0,width=12,fg_bg=bw_fg_bg}
    local po_rate = DataIndicator{parent=waste,x=_wide(52,45),y=6,lu_colors=lu_c,label="",unit="mB/t",format="%7.3f",value=0,width=12,fg_bg=bw_fg_bg}
    local popl_rate = DataIndicator{parent=waste,x=_wide(82,70),y=6,lu_colors=lu_c,label="",unit="mB/t",format="%7.3f",value=0,width=12,fg_bg=bw_fg_bg}
    local poam_rate = DataIndicator{parent=waste,x=_wide(82,70),y=10,lu_colors=lu_c,label="",unit="mB/t",format="%7.3f",value=0,width=12,fg_bg=bw_fg_bg}
    local spent_rate = DataIndicator{parent=waste,x=_wide(117,99),y=3,lu_colors=lu_c,label="",unit="mB/t",format="%7.3f",value=0,width=12,fg_bg=bw_fg_bg}

    waste_rate.register(unit.unit_ps, "act_burn_rate", waste_rate.update)
    pu_rate.register(unit.unit_ps, "pu_rate", pu_rate.update)
    po_rate.register(unit.unit_ps, "po_rate", po_rate.update)
    popl_rate.register(unit.unit_ps, "po_pl_rate", popl_rate.update)
    poam_rate.register(unit.unit_ps, "po_am_rate", poam_rate.update)
    spent_rate.register(unit.unit_ps, "ws_rate", spent_rate.update)

    _valve(_wide(21, 18), 2, 1)
    _valve(_wide(21, 18), 6, 2)
    _valve(_wide(73, 62), 5, 3)
    _valve(_wide(73, 62), 9, 4)

    _machine(_wide(51, 45), 1, "CENTRIFUGE \x1a");
    _machine(_wide(97, 83), 1, "PRC [Pu] \x1a");
    _machine(_wide(97, 83), 4, "PRC [Po] \x1a");
    _machine(_wide(116, 94), 6, "SPENT WASTE \x1b")

    TextBox{parent=waste,x=_wide(30,25),y=3,text="SNAs [Po]",alignment=TEXT_ALIGN.CENTER,width=19,height=1,fg_bg=wh_gray}
    local sna_po  = Rectangle{parent=waste,x=_wide(30,25),y=4,border=border(1,colors.gray,true),width=19,height=7,thin=true,fg_bg=bw_fg_bg}
    local sna_act = IndicatorLight{parent=sna_po,label="ACTIVE",colors=ind_grn}
    local sna_cnt = DataIndicator{parent=sna_po,x=12,y=1,lu_colors=lu_c,label="CNT",unit="",format="%2d",value=0,width=7}
    local sna_pk = DataIndicator{parent=sna_po,y=3,lu_colors=lu_c,label="PEAK",unit="mB/t",format="%7.2f",value=0,width=17}
    local sna_max = DataIndicator{parent=sna_po,lu_colors=lu_c,label="MAX",unit="mB/t",format="%8.2f",value=0,width=17}
    local sna_in = DataIndicator{parent=sna_po,lu_colors=lu_c,label="IN",unit="mB/t",format="%9.2f",value=0,width=17}

    sna_act.register(unit.unit_ps, "po_rate", function (r) sna_act.update(r > 0) end)
    sna_cnt.register(unit.unit_ps, "sna_count", sna_cnt.update)
    sna_pk.register(unit.unit_ps, "sna_peak_rate", sna_pk.update)
    sna_max.register(unit.unit_ps, "sna_prod_rate", sna_max.update)
    sna_in.register(unit.unit_ps, "sna_in", sna_in.update)

    return root
end

return make
