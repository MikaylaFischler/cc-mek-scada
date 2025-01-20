local util           = require("scada-common.util")

local iocontrol      = require("coordinator.iocontrol")

local style          = require("coordinator.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local Rectangle      = require("graphics.elements.Rectangle")
local TextBox        = require("graphics.elements.TextBox")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local IndicatorLight = require("graphics.elements.indicators.IndicatorLight")
local PowerIndicator = require("graphics.elements.indicators.PowerIndicator")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")
local VerticalBar    = require("graphics.elements.indicators.VerticalBar")

local cpair = core.cpair
local border = core.border

local ALIGN = core.ALIGN

-- new induction matrix view
---@param root Container parent
---@param x integer top left x
---@param y integer top left y
---@param ps psil ps interface
---@param id number? matrix ID
local function new_view(root, x, y, ps, id)
    local label_fg = style.theme.label_fg
    local text_fg = style.theme.text_fg
    local lu_col = style.lu_colors

    local ind_yel = style.ind_yel
    local ind_wht = style.ind_wht

    local db = iocontrol.get_db()

    local title = "INDUCTION MATRIX"
    if type(id) == "number" then title = title .. id end

    local matrix = Div{parent=root,fg_bg=style.root,width=33,height=24,x=x,y=y}

    -- black has low contrast with dark gray, so if background is black use white instead
    local cutout_fg_bg = cpair(util.trinary(style.theme.bg == colors.black, colors.white, style.theme.bg), colors.gray)

    TextBox{parent=matrix,text=" ",width=33,x=1,y=1,fg_bg=cutout_fg_bg}
    TextBox{parent=matrix,text=title,alignment=ALIGN.CENTER,width=33,x=1,y=2,fg_bg=cutout_fg_bg}

    local rect = Rectangle{parent=matrix,border=border(1,colors.gray,true),width=33,height=22,x=1,y=3}

    local status    = StateIndicator{parent=rect,x=10,y=1,states=style.imatrix.states,value=1,min_width=14}
    local capacity  = PowerIndicator{parent=rect,x=7,y=3,lu_colors=lu_col,label="Capacity:",unit=db.energy_label,format="%8.2f",value=0,width=26,fg_bg=text_fg}
    local energy    = PowerIndicator{parent=rect,x=7,y=4,lu_colors=lu_col,label="Energy:  ",unit=db.energy_label,format="%8.2f",value=0,width=26,fg_bg=text_fg}
    local avg_chg   = PowerIndicator{parent=rect,x=7,y=5,lu_colors=lu_col,label="\xb7Average:",unit=db.energy_label,format="%8.2f",value=0,width=26,fg_bg=text_fg}
    local input     = PowerIndicator{parent=rect,x=7,y=6,lu_colors=lu_col,label="Input:   ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}
    local avg_in    = PowerIndicator{parent=rect,x=7,y=7,lu_colors=lu_col,label="\xb7Average:",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}
    local output    = PowerIndicator{parent=rect,x=7,y=8,lu_colors=lu_col,label="Output:  ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}
    local avg_out   = PowerIndicator{parent=rect,x=7,y=9,lu_colors=lu_col,label="\xb7Average:",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}
    local trans_cap = PowerIndicator{parent=rect,x=7,y=10,lu_colors=lu_col,label="Max I/O: ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}

    status.register(ps, "computed_status", status.update)
    capacity.register(ps, "max_energy", function (val) capacity.update(db.energy_convert(val)) end)
    energy.register(ps, "energy", function (val) energy.update(db.energy_convert(val)) end)
    avg_chg.register(ps, "avg_charge", avg_chg.update)
    input.register(ps, "last_input", function (val) input.update(db.energy_convert(val)) end)
    avg_in.register(ps, "avg_inflow", avg_in.update)
    output.register(ps, "last_output", function (val) output.update(db.energy_convert(val)) end)
    avg_out.register(ps, "avg_outflow", avg_out.update)
    trans_cap.register(ps, "transfer_cap", function (val) trans_cap.update(db.energy_convert(val)) end)

    local fill      = DataIndicator{parent=rect,x=11,y=12,lu_colors=lu_col,label="Fill:     ",format="%7.2f",unit="%",value=0,width=20,fg_bg=text_fg}
    local cells     = DataIndicator{parent=rect,x=11,y=13,lu_colors=lu_col,label="Cells:    ",format="%7d",value=0,width=18,fg_bg=text_fg}
    local providers = DataIndicator{parent=rect,x=11,y=14,lu_colors=lu_col,label="Providers:",format="%7d",value=0,width=18,fg_bg=text_fg}

    fill.register(ps, "energy_fill", function (val) fill.update(val * 100) end)
    cells.register(ps, "cells", cells.update)
    providers.register(ps, "providers", providers.update)

    local chging = IndicatorLight{parent=rect,x=11,y=16,label="Charging",colors=ind_wht}
    local dischg = IndicatorLight{parent=rect,x=11,y=17,label="Discharging",colors=ind_wht}
    local max_io = IndicatorLight{parent=rect,x=11,y=18,label="Max I/O Rate",colors=ind_yel}

    chging.register(ps, "is_charging", chging.update)
    dischg.register(ps, "is_discharging", dischg.update)
    max_io.register(ps, "at_max_io", max_io.update)

    local charge  = VerticalBar{parent=rect,x=2,y=2,fg_bg=cpair(colors.green,colors.gray),height=17,width=4}
    local in_cap  = VerticalBar{parent=rect,x=7,y=12,fg_bg=cpair(colors.red,colors.gray),height=7,width=1}
    local out_cap = VerticalBar{parent=rect,x=9,y=12,fg_bg=cpair(colors.blue,colors.gray),height=7,width=1}

    TextBox{parent=rect,text="FILL I/O",x=2,y=20,width=8,fg_bg=label_fg}

    local function calc_saturation(val)
        local data = db.facility.induction_data_tbl[id or 1]
        if (type(data.build) == "table") and (type(data.build.transfer_cap) == "number") and (data.build.transfer_cap > 0) then
            return val / data.build.transfer_cap
        else return 0 end
    end

    charge.register(ps, "energy_fill", charge.update)
    in_cap.register(ps, "last_input", function (val) in_cap.update(calc_saturation(val)) end)
    out_cap.register(ps, "last_output", function (val) out_cap.update(calc_saturation(val)) end)

    local eta = TextBox{parent=rect,x=11,y=20,width=20,text="ETA Unknown",alignment=ALIGN.CENTER,fg_bg=style.theme.field_box}

    eta.register(ps, "eta_string", eta.set_value)
end

return new_view
