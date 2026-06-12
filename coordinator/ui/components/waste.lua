--
-- Waste Processing Overview
--

local util           = require("scada-common.util")

local style          = require("coordinator.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local PipeNetwork    = require("graphics.elements.PipeNetwork")
local TextBox        = require("graphics.elements.TextBox")

local Rectangle      = require("graphics.elements.Rectangle")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")

local IndicatorLight = require("graphics.elements.indicators.IndicatorLight")

local ALIGN = core.ALIGN

local border = core.border
local cpair = core.cpair
local pipe = core.pipe

local wh_gray = style.wh_gray

-- make a new waste flow window
---@param parent Container parent
---@param x integer top left x
---@param y integer top left y
---@param wide boolean whether to render wide version
---@param fac_waste boolean true if using facility waste
---@param v_fields string[] valve ps field suffixes
---@param v_names string[] valve names
---@param ps psil unit ps
local function make(parent, x, y, wide, fac_waste, v_fields, v_names, ps)
    local s_field = style.theme.field_box

    local text_c = style.text_colors
    local lu_c = style.lu_colors
    local lu_c_d = style.lu_colors_dark

    local ind_grn = style.ind_grn
    local ind_wht = style.ind_wht

    local function _wide(a, b) return util.trinary(wide, a, b) end

    local root = Div{parent=parent,x=x,y=y,width=_wide(136, 114),height=11}

    local waste_c = style.theme.fuel_color

    local waste_pipes = {
        pipe(_wide(13, 12), 1, _wide(19, 16), 1, colors.brown, true),
        pipe(_wide(14, 13), 1, _wide(19, 17), 5, colors.brown, true),
        pipe(_wide(22, 19), 1, _wide(49, 45), 1, colors.brown, true),
        pipe(_wide(22, 19), 5, _wide(28, 24), 5, colors.brown, true),

        pipe(_wide(64, 53), 1, _wide(95, 81), 1, colors.cyan, true),

        pipe(_wide(48, 43), 4, _wide(71, 61), 4, colors.green, true),
        pipe(_wide(66, 57), 4, _wide(71, 61), 8, colors.green, true),
        pipe(_wide(74, 63), 4, _wide(95, 81), 4, colors.green, true),
        pipe(_wide(74, 63), 8, _wide(133, 111), 8, colors.green, true),

        pipe(_wide(108, 94), 1, _wide(132, 110), 6, waste_c, true, true),
        pipe(_wide(108, 94), 4, _wide(111, 95), 1, waste_c, true, true),
        pipe(_wide(132, 110), 6, _wide(130, 108), 6, waste_c, true, true)
    }

    PipeNetwork{parent=root,y=1,pipes=waste_pipes,bg=style.theme.bg}

    local function _valve(vx, vy, n)
        TextBox{parent=root,x=vx,y=vy,text="\x10\x11",fg_bg=text_c,width=2}
        local conn = IndicatorLight{parent=root,x=vx-3,y=vy+1,label=v_names[n],colors=ind_grn}
        local open = IndicatorLight{parent=root,x=vx-3,y=vy+2,label="OPEN",colors=ind_wht}
        conn.register(ps, util.c("V_", v_fields[n], "_conn"), conn.update)
        open.register(ps, util.c("V_", v_fields[n], "_state"), open.update)
    end

    local function _machine(mx, my, name)
        local l = string.len(name) + 2
        TextBox{parent=root,x=mx,y=my,text=string.rep("\x8f",l),alignment=ALIGN.CENTER,fg_bg=cpair(style.theme.bg,style.theme.header.bkg),width=l}
        TextBox{parent=root,x=mx,y=my+1,text=name,alignment=ALIGN.CENTER,fg_bg=style.theme.header,width=l}
    end

    local pu_rate = DataIndicator{parent=root,x=_wide(82,70),y=3,lu_colors=lu_c,label="",unit="mB/t",format="%7.3f",value=0,width=12,fg_bg=s_field}
    local po_rate = DataIndicator{parent=root,x=_wide(52,45),y=6,lu_colors=lu_c,label="",unit="mB/t",format="%7.2f",value=0,width=12,fg_bg=s_field}
    local popl_rate = DataIndicator{parent=root,x=_wide(82,70),y=6,lu_colors=lu_c,label="",unit="mB/t",format="%7.2f",value=0,width=12,fg_bg=s_field}
    local poam_rate = DataIndicator{parent=root,x=_wide(82,70),y=10,lu_colors=lu_c,label="",unit="mB/t",format="%7.2f",value=0,width=12,fg_bg=s_field}
    local spent_rate = DataIndicator{parent=root,x=_wide(117,98),y=3,lu_colors=lu_c,label="",unit="mB/t",format="%8.3f",value=0,width=13,fg_bg=s_field}

    pu_rate.register(ps, "pu_rate", pu_rate.update)
    po_rate.register(ps, "po_rate", po_rate.update)
    popl_rate.register(ps, "po_pl_rate", popl_rate.update)
    poam_rate.register(ps, "po_am_rate", poam_rate.update)
    spent_rate.register(ps, "ws_rate", spent_rate.update)

    _valve(_wide(21, 18), 2, 1)
    _valve(_wide(21, 18), 6, 2)
    _valve(_wide(73, 62), 5, 3)
    _valve(_wide(73, 62), 9, 4)

    _machine(_wide(51, 45), 1, "CENTRIFUGE \x1a");
    _machine(_wide(97, 83), 1, "PRC [Pu] \x1a");
    _machine(_wide(97, 83), 4, "PRC [Po] \x1a");
    _machine(_wide(116, 94), 6, "SPENT WASTE \x1b")

    TextBox{parent=root,x=_wide(30,25),y=3,text="SNAs [Po]",alignment=ALIGN.CENTER,width=19,fg_bg=wh_gray}
    local sna_po  = Rectangle{parent=root,x=_wide(30,25),y=4,border=border(1,colors.gray,true),width=19,height=8,thin=true,fg_bg=style.theme.highlight_box_bright}
    local sna_act = IndicatorLight{parent=sna_po,label="ACTIVE",colors=ind_grn}
    local sna_cnt = DataIndicator{parent=sna_po,x=12,y=1,lu_colors=lu_c_d,label="CNT",unit="",format="%2d",value=0,width=7}
    TextBox{parent=sna_po,y=3,text="PEAK\x1a",width=5,fg_bg=cpair(style.theme.label_dark,colors._INHERIT)}
    TextBox{parent=sna_po,text="MAX \x1a",width=5,fg_bg=cpair(style.theme.label_dark,colors._INHERIT)}
    local sna_pk = DataIndicator{parent=sna_po,x=6,y=3,lu_colors=lu_c_d,label="",unit="mB/t",format="%7.2f",value=0,width=17}
    local sna_max_o = DataIndicator{parent=sna_po,x=6,lu_colors=lu_c_d,label="",unit="mB/t",format="%7.2f",value=0,width=17}
    local sna_max_i = DataIndicator{parent=sna_po,lu_colors=lu_c_d,label="\x1aMAX",unit="mB/t",format="%7.2f",value=0,width=17}
    local sna_in = DataIndicator{parent=sna_po,lu_colors=lu_c_d,label="\x1aIN",unit="mB/t",format="%8.2f",value=0,width=17}

    sna_act.register(ps, "po_rate", function (r) sna_act.update(r > 0) end)
    sna_cnt.register(ps, "sna_count", sna_cnt.update)
    sna_pk.register(ps, "sna_peak_rate", sna_pk.update)
    sna_max_o.register(ps, "sna_max_rate_out", sna_max_o.update)
    sna_max_i.register(ps, "sna_max_rate_in", sna_max_i.update)
    sna_in.register(ps, "sna_in", sna_in.update)

    return root
end

return make
