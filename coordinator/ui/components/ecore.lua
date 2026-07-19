local util           = require("scada-common.util")

local ioctl          = require("coordinator.ioctl")

local style          = require("coordinator.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local Rectangle      = require("graphics.elements.Rectangle")
local TextBox        = require("graphics.elements.TextBox")

local IndicatorLight = require("graphics.elements.indicators.IndicatorLight")
local PowerIndicator = require("graphics.elements.indicators.PowerIndicator")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")
local VerticalBar    = require("graphics.elements.indicators.VerticalBar")

local cpair = core.cpair
local border = core.border

local ALIGN = core.ALIGN

-- new energy core view
---@param root Container parent
---@param x integer top left x
---@param y integer top left y
---@param ps psil ps interface
---@param id number? energy core ID
local function new_view(root, x, y, ps, id)
    local label_fg = style.theme.label_fg
    local text_fg = style.theme.text_fg
    local lu_col = style.lu_colors

    local ind_wht = style.ind_wht

    local db = ioctl.get_db()

    local title = "ENERGY CORE"
    if type(id) == "number" then title = title .. id end

    local ecore = Div{parent=root,fg_bg=style.root,width=33,height=24,x=x,y=y}

    -- black has low contrast with dark gray, so if background is black use white instead
    local cutout_fg_bg = cpair(util.trinary(style.theme.bg == colors.black, colors.white, style.theme.bg), colors.gray)

    TextBox{parent=ecore,text=" ",width=33,y=1,fg_bg=cutout_fg_bg}
    TextBox{parent=ecore,text=title,alignment=ALIGN.CENTER,width=33,y=2,fg_bg=cutout_fg_bg}

    local rect = Rectangle{parent=ecore,border=border(1,colors.gray,true),width=33,height=22,y=3}

    local status   = StateIndicator{parent=rect,x=10,y=1,states=style.ecore.states,value=1,min_width=14}
    local capacity = PowerIndicator{parent=rect,x=7,y=3,lu_colors=lu_col,label="Capacity:",unit=db.energy_label,format="%8.2f",value=0,width=26,fg_bg=text_fg}
    local energy   = PowerIndicator{parent=rect,x=7,y=5,lu_colors=lu_col,label="Energy:  ",unit=db.energy_label,format="%8.2f",value=0,width=26,fg_bg=text_fg}
    local avg_chg  = PowerIndicator{parent=rect,x=7,y=6,lu_colors=lu_col,label="\xb7Average:",unit=db.energy_label,format="%8.2f",value=0,width=26,fg_bg=text_fg}

    local transfer = PowerIndicator{parent=rect,x=7,y=8,lu_colors=lu_col,label="Transfer:",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}

    local chging   = IndicatorLight{parent=rect,x=7,y=10,label="Charging",colors=ind_wht}
    local dischg   = IndicatorLight{parent=rect,x=7,y=11,label="Discharging",colors=ind_wht}

    local input    = PowerIndicator{parent=rect,x=7,y=13,lu_colors=lu_col,label="Input:   ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}
    local avg_in   = PowerIndicator{parent=rect,x=7,y=14,lu_colors=lu_col,label="\xb7Average:",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}
    local output   = PowerIndicator{parent=rect,x=7,y=16,lu_colors=lu_col,label="Output:  ",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}
    local avg_out  = PowerIndicator{parent=rect,x=7,y=17,lu_colors=lu_col,label="\xb7Average:",unit=db.energy_label,format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}

    status.register(ps, "computed_status", status.update)
    capacity.register(ps, "max_energy", function (val) capacity.update(db.energy_convert_from_fe(val)) end)
    energy.register(ps, "energy", function (val) energy.update(db.energy_convert_from_fe(val)) end)
    avg_chg.register(ps, "avg_charge", avg_chg.update)

    transfer.register(ps, "transfer", function (val) transfer.update(db.energy_convert_from_fe(val)) end)
    input.register(ps, "input", function (val) input.update(db.energy_convert_from_fe(val)) end)
    avg_in.register(ps, "avg_inflow", avg_in.update)
    output.register(ps, "output", function (val) output.update(db.energy_convert_from_fe(val)) end)
    avg_out.register(ps, "avg_outflow", avg_out.update)

    chging.register(ps, "is_charging", chging.update)
    dischg.register(ps, "is_discharging", dischg.update)

    local charge = VerticalBar{parent=rect,x=2,y=2,fg_bg=cpair(colors.green,colors.gray),height=17,width=4}

    TextBox{parent=rect,text="FILL",x=2,y=20,fg_bg=label_fg}

    charge.register(ps, "energy_fill", charge.update)

    local eta = TextBox{parent=rect,x=7,y=20,width=24,text="ETA Unknown",alignment=ALIGN.CENTER,fg_bg=style.theme.field_box}

    eta.register(ps, "eta_string", eta.set_value)
end

return new_view
