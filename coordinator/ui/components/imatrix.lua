local util           = require("scada-common.util")

local style          = require("coordinator.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.div")
local Rectangle      = require("graphics.elements.rectangle")
local TextBox        = require("graphics.elements.textbox")

local DataIndicator  = require("graphics.elements.indicators.data")
local IndicatorLight = require("graphics.elements.indicators.light")
local PowerIndicator = require("graphics.elements.indicators.power")
local StateIndicator = require("graphics.elements.indicators.state")
local VerticalBar    = require("graphics.elements.indicators.vbar")

local cpair = core.cpair
local border = core.border

local ALIGN = core.ALIGN

-- new induction matrix view
---@param root graphics_element parent
---@param x integer top left x
---@param y integer top left y
---@param data imatrix_session_db matrix data
---@param ps psil ps interface
---@param id number? matrix ID
local function new_view(root, x, y, data, ps, id)
    local label_fg = style.theme.label_fg
    local text_fg = style.theme.text_fg
    local lu_col = style.lu_colors

    local ind_yel = style.ind_yel
    local ind_wht = style.ind_wht

    local title = "INDUCTION MATRIX"
    if type(id) == "number" then title = title .. id end

    local matrix = Div{parent=root,fg_bg=style.root,width=33,height=24,x=x,y=y}

    -- black has low contrast with dark gray, so if background is black use white instead
    local cutout_fg_bg = cpair(util.trinary(style.theme.bg == colors.black, colors.white, style.theme.bg), colors.gray)

    TextBox{parent=matrix,text=" ",width=33,height=1,x=1,y=1,fg_bg=cutout_fg_bg}
    TextBox{parent=matrix,text=title,alignment=ALIGN.CENTER,width=33,height=1,x=1,y=2,fg_bg=cutout_fg_bg}

    local rect = Rectangle{parent=matrix,border=border(1,colors.gray,true),width=33,height=22,x=1,y=3}

    local status    = StateIndicator{parent=rect,x=10,y=1,states=style.imatrix.states,value=1,min_width=14}
    local capacity  = PowerIndicator{parent=rect,x=7,y=3,lu_colors=lu_col,label="Capacity:",format="%8.2f",value=0,width=26,fg_bg=text_fg}
    local energy    = PowerIndicator{parent=rect,x=7,y=4,lu_colors=lu_col,label="Energy:  ",format="%8.2f",value=0,width=26,fg_bg=text_fg}
    local avg_chg   = PowerIndicator{parent=rect,x=7,y=5,lu_colors=lu_col,label="\xb7Average:",format="%8.2f",value=0,width=26,fg_bg=text_fg}
    local input     = PowerIndicator{parent=rect,x=7,y=6,lu_colors=lu_col,label="Input:   ",format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}
    local avg_in    = PowerIndicator{parent=rect,x=7,y=7,lu_colors=lu_col,label="\xb7Average:",format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}
    local output    = PowerIndicator{parent=rect,x=7,y=8,lu_colors=lu_col,label="Output:  ",format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}
    local avg_out   = PowerIndicator{parent=rect,x=7,y=9,lu_colors=lu_col,label="\xb7Average:",format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}
    local trans_cap = PowerIndicator{parent=rect,x=7,y=10,lu_colors=lu_col,label="Max I/O: ",format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg}

    status.register(ps, "computed_status", status.update)
    capacity.register(ps, "max_energy", function (val) capacity.update(util.joules_to_fe(val)) end)
    energy.register(ps, "energy", function (val) energy.update(util.joules_to_fe(val)) end)
    avg_chg.register(ps, "avg_charge", avg_chg.update)
    input.register(ps, "last_input", function (val) input.update(util.joules_to_fe(val)) end)
    avg_in.register(ps, "avg_inflow", avg_in.update)
    output.register(ps, "last_output", function (val) output.update(util.joules_to_fe(val)) end)
    avg_out.register(ps, "avg_outflow", avg_out.update)
    trans_cap.register(ps, "transfer_cap", function (val) trans_cap.update(util.joules_to_fe(val)) end)

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

    TextBox{parent=rect,text="FILL I/O",x=2,y=20,height=1,width=8,fg_bg=label_fg}

    local function calc_saturation(val)
        if (type(data.build) == "table") and (type(data.build.transfer_cap) == "number") and (data.build.transfer_cap > 0) then
            return val / data.build.transfer_cap
        else return 0 end
    end

    charge.register(ps, "energy_fill", charge.update)
    in_cap.register(ps, "last_input", function (val) in_cap.update(calc_saturation(val)) end)
    out_cap.register(ps, "last_output", function (val) out_cap.update(calc_saturation(val)) end)

    local eta = TextBox{parent=rect,x=11,y=20,width=20,height=1,text="ETA Unknown",alignment=ALIGN.CENTER,fg_bg=style.theme.field_box}

    eta.register(ps, "eta_ms", function (eta_ms)
        local str, pre = "", util.trinary(eta_ms >= 0, "Full in ", "Empty in ")

        local seconds = math.abs(eta_ms) / 1000
        local minutes = seconds / 60
        local hours   = minutes / 60
        local days    = hours / 24

        if math.abs(eta_ms) < 1000 or (eta_ms ~= eta_ms) then
            -- really small or NaN
            str = "No ETA"
        elseif days < 1000 then
            days    = math.floor(days)
            hours   = math.floor(hours % 24)
            minutes = math.floor(minutes % 60)
            seconds = math.floor(seconds % 60)

            if days > 0 then
                str = days .. "d"
            elseif hours > 0 then
                str = hours .. "h " .. minutes .. "m"
            elseif minutes > 0 then
                str = minutes .. "m " .. seconds .. "s"
            elseif seconds > 0 then
                str = seconds .. "s"
            end

            str = pre .. str
        else
            local years = math.floor(days / 365.25)

            if years <= 99999999 then
                str = pre .. years .. "y"
            else
                str = pre .. "eras"
            end
        end

        eta.set_value(str)
    end)
end

return new_view
