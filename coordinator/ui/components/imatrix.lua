local util           = require("scada-common.util")

local style          = require("coordinator.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.div")
local Rectangle      = require("graphics.elements.rectangle")
local TextBox        = require("graphics.elements.textbox")

local DataIndicator  = require("graphics.elements.indicators.data")
local PowerIndicator = require("graphics.elements.indicators.power")
local StateIndicator = require("graphics.elements.indicators.state")
local VerticalBar    = require("graphics.elements.indicators.vbar")

local cpair = core.cpair
local border = core.border

local TEXT_ALIGN = core.TEXT_ALIGN

-- new induction matrix view
---@param root graphics_element parent
---@param x integer top left x
---@param y integer top left y
---@param data imatrix_session_db matrix data
---@param ps psil ps interface
---@param id number? matrix ID
local function new_view(root, x, y, data, ps, id)
    local title = "INDUCTION MATRIX"
    if type(id) == "number" then title = title .. id end

    local matrix = Div{parent=root,fg_bg=style.root,width=33,height=24,x=x,y=y}

    TextBox{parent=matrix,text=" ",width=33,height=1,x=1,y=1,fg_bg=cpair(colors.lightGray,colors.gray)}
    TextBox{parent=matrix,text=title,alignment=TEXT_ALIGN.CENTER,width=33,height=1,x=1,y=2,fg_bg=cpair(colors.lightGray,colors.gray)}

    local rect = Rectangle{parent=matrix,border=border(1,colors.gray,true),width=33,height=22,x=1,y=3}

    local text_fg_bg = cpair(colors.black, colors.lightGray)
    local label_fg_bg = cpair(colors.gray, colors.lightGray)
    local lu_col = cpair(colors.gray, colors.gray)

    local status   = StateIndicator{parent=rect,x=10,y=1,states=style.imatrix.states,value=1,min_width=14}
    local energy   = PowerIndicator{parent=rect,x=7,y=3,lu_colors=lu_col,label="Energy:  ",format="%8.2f",value=0,width=26,fg_bg=text_fg_bg}
    local capacity = PowerIndicator{parent=rect,x=7,y=4,lu_colors=lu_col,label="Capacity:",format="%8.2f",value=0,width=26,fg_bg=text_fg_bg}
    local input    = PowerIndicator{parent=rect,x=7,y=5,lu_colors=lu_col,label="Input:   ",format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg_bg}
    local output   = PowerIndicator{parent=rect,x=7,y=6,lu_colors=lu_col,label="Output:  ",format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg_bg}

    local avg_chg  = PowerIndicator{parent=rect,x=7,y=8,lu_colors=lu_col,label="Avg. Chg:",format="%8.2f",value=0,width=26,fg_bg=text_fg_bg}
    local avg_in   = PowerIndicator{parent=rect,x=7,y=9,lu_colors=lu_col,label="Avg. In: ",format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg_bg}
    local avg_out  = PowerIndicator{parent=rect,x=7,y=10,lu_colors=lu_col,label="Avg. Out:",format="%8.2f",rate=true,value=0,width=26,fg_bg=text_fg_bg}

    status.register(ps, "computed_status", status.update)
    energy.register(ps, "energy", function (val) energy.update(util.joules_to_fe(val)) end)
    capacity.register(ps, "max_energy", function (val) capacity.update(util.joules_to_fe(val)) end)
    input.register(ps, "last_input", function (val) input.update(util.joules_to_fe(val)) end)
    output.register(ps, "last_output", function (val) output.update(util.joules_to_fe(val)) end)

    avg_chg.register(ps, "avg_charge", avg_chg.update)
    avg_in.register(ps, "avg_inflow", avg_in.update)
    avg_out.register(ps, "avg_outflow", avg_out.update)

    local fill      = DataIndicator{parent=rect,x=11,y=12,lu_colors=lu_col,label="Fill:",unit="%",format="%8.2f",value=0,width=18,fg_bg=text_fg_bg}

    local cells     = DataIndicator{parent=rect,x=11,y=14,lu_colors=lu_col,label="Cells:    ",format="%7d",value=0,width=18,fg_bg=text_fg_bg}
    local providers = DataIndicator{parent=rect,x=11,y=15,lu_colors=lu_col,label="Providers:",format="%7d",value=0,width=18,fg_bg=text_fg_bg}

    TextBox{parent=rect,text="Transfer Capacity",x=11,y=17,height=1,width=17,fg_bg=label_fg_bg}
    local trans_cap = PowerIndicator{parent=rect,x=19,y=18,lu_colors=lu_col,label="",format="%5.2f",rate=true,value=0,width=12,fg_bg=text_fg_bg}

    cells.register(ps, "cells", cells.update)
    providers.register(ps, "providers", providers.update)
    fill.register(ps, "energy_fill", function (val) fill.update(val * 100) end)
    trans_cap.register(ps, "transfer_cap", function (val) trans_cap.update(util.joules_to_fe(val)) end)

    local charge  = VerticalBar{parent=rect,x=2,y=2,fg_bg=cpair(colors.green,colors.gray),height=17,width=4}
    local in_cap  = VerticalBar{parent=rect,x=7,y=12,fg_bg=cpair(colors.red,colors.gray),height=7,width=1}
    local out_cap = VerticalBar{parent=rect,x=9,y=12,fg_bg=cpair(colors.blue,colors.gray),height=7,width=1}

    TextBox{parent=rect,text="FILL",x=2,y=20,height=1,width=4,fg_bg=text_fg_bg}
    TextBox{parent=rect,text="I/O",x=7,y=20,height=1,width=3,fg_bg=text_fg_bg}

    local function calc_saturation(val)
        if (type(data.build) == "table") and (type(data.build.transfer_cap) == "number") and (data.build.transfer_cap > 0) then
            return val / data.build.transfer_cap
        else
            return 0
        end
    end

    charge.register(ps, "energy_fill", charge.update)
    in_cap.register(ps, "last_input", function (val) in_cap.update(calc_saturation(val)) end)
    out_cap.register(ps, "last_output", function (val) out_cap.update(calc_saturation(val)) end)
end

return new_view
