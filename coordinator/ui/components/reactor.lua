local util           = require("scada-common.util")

local core           = require("graphics.core")

local style          = require("coordinator.ui.style")

local Rectangle      = require("graphics.elements.rectangle")
local TextBox        = require("graphics.elements.textbox")

local DataIndicator  = require("graphics.elements.indicators.data")
local HorizontalBar  = require("graphics.elements.indicators.hbar")
local StateIndicator = require("graphics.elements.indicators.state")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border

-- create new reactor view
---@param root graphics_element parent
---@param x integer top left x
---@param y integer top left y
---@param data reactor_db reactor data
---@param ps psil ps interface
local function new_view(root, x, y, data, ps)
    local reactor = Rectangle{parent=root,border=border(1, colors.gray, true),width=30,height=7,x=x,y=y}

    local text_fg_bg = cpair(colors.black, colors.lightGray)
    local lu_col = cpair(colors.gray, colors.gray)

    local status    = StateIndicator{parent=reactor,x=6,y=1,states=style.reactor.states,value=1,min_width=16}
    local core_temp = DataIndicator{parent=reactor,x=2,y=3,lu_colors=lu_col,label="Core Temp:",unit="K",format="%10.2f",value=0,width=26,fg_bg=text_fg_bg}
    local burn_r    = DataIndicator{parent=reactor,x=2,y=4,lu_colors=lu_col,label="Burn Rate:",unit="mB/t",format="%10.1f",value=0,width=26,fg_bg=text_fg_bg}
    local heating_r = DataIndicator{parent=reactor,x=2,y=5,lu_colors=lu_col,label="Heating:",unit="mB/t",format="%12.0f",value=0,commas=true,width=26,fg_bg=text_fg_bg}

    ps.subscribe("computed_status", status.update)
    ps.subscribe("temp", core_temp.update)
    ps.subscribe("act_burn_rate", burn_r.update)
    ps.subscribe("heating_rate", heating_r.update)

    local reactor_fills = Rectangle{parent=root,border=border(1, colors.gray, true),width=24,height=7,x=(x + 29),y=y}

    TextBox{parent=reactor_fills,text="FUEL",x=2,y=1,height=1,fg_bg=text_fg_bg}
    TextBox{parent=reactor_fills,text="COOL",x=2,y=2,height=1,fg_bg=text_fg_bg}
    TextBox{parent=reactor_fills,text="HCOOL",x=2,y=4,height=1,fg_bg=text_fg_bg}
    TextBox{parent=reactor_fills,text="WASTE",x=2,y=5,height=1,fg_bg=text_fg_bg}

    -- local ccool_color = util.trinary(data.mek_status.ccool_type == "sodium", cpair(colors.lightBlue,colors.gray), cpair(colors.blue,colors.gray))
    -- local hcool_color = util.trinary(data.mek_status.hcool_type == "superheated_sodium", cpair(colors.orange,colors.gray), cpair(colors.white,colors.gray))
    local ccool_color = util.trinary(true, cpair(colors.lightBlue,colors.gray), cpair(colors.blue,colors.gray))
    local hcool_color = util.trinary(true, cpair(colors.orange,colors.gray), cpair(colors.white,colors.gray))

    local fuel  = HorizontalBar{parent=reactor_fills,x=8,y=1,show_percent=true,bar_fg_bg=cpair(colors.black,colors.gray),height=1,width=14}
    local ccool = HorizontalBar{parent=reactor_fills,x=8,y=2,show_percent=true,bar_fg_bg=ccool_color,height=1,width=14}
    local hcool = HorizontalBar{parent=reactor_fills,x=8,y=4,show_percent=true,bar_fg_bg=hcool_color,height=1,width=14}
    local waste = HorizontalBar{parent=reactor_fills,x=8,y=5,show_percent=true,bar_fg_bg=cpair(colors.brown,colors.gray),height=1,width=14}

    ps.subscribe("fuel_fill", fuel.update)
    ps.subscribe("ccool_fill", ccool.update)
    ps.subscribe("hcool_fill", hcool.update)
    ps.subscribe("waste_fill", waste.update)
end

return new_view
