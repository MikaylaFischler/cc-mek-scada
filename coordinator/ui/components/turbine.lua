local util           = require("scada-common.util")

local style          = require("coordinator.ui.style")

local core           = require("graphics.core")

local Rectangle      = require("graphics.elements.rectangle")
local TextBox        = require("graphics.elements.textbox")

local DataIndicator  = require("graphics.elements.indicators.data")
local PowerIndicator = require("graphics.elements.indicators.power")
local StateIndicator = require("graphics.elements.indicators.state")
local VerticalBar    = require("graphics.elements.indicators.vbar")

local cpair = core.cpair
local border = core.border

-- new turbine view
---@param root graphics_element parent
---@param x integer top left x
---@param y integer top left y
---@param ps psil ps interface
local function new_view(root, x, y, ps)
    local text_fg = style.theme.text_fg
    local lu_col = style.lu_colors

    local turbine = Rectangle{parent=root,border=border(1,colors.gray,true),width=23,height=7,x=x,y=y}

    local status    = StateIndicator{parent=turbine,x=7,y=1,states=style.turbine.states,value=1,min_width=12}
    local prod_rate = PowerIndicator{parent=turbine,x=5,y=3,lu_colors=lu_col,label="",format="%10.2f",value=0,rate=true,width=16,fg_bg=text_fg}
    local flow_rate = DataIndicator{parent=turbine,x=5,y=4,lu_colors=lu_col,label="",unit="mB/t",format="%10.0f",value=0,commas=true,width=16,fg_bg=text_fg}

    status.register(ps, "computed_status", status.update)
    prod_rate.register(ps, "prod_rate", function (val) prod_rate.update(util.joules_to_fe(val)) end)
    flow_rate.register(ps, "steam_input_rate", flow_rate.update)

    local steam  = VerticalBar{parent=turbine,x=2,y=1,fg_bg=cpair(colors.white,colors.gray),height=4,width=1}
    local energy = VerticalBar{parent=turbine,x=3,y=1,fg_bg=cpair(colors.green,colors.gray),height=4,width=1}

    TextBox{parent=turbine,text="S",x=2,y=5,height=1,width=1,fg_bg=text_fg}
    TextBox{parent=turbine,text="E",x=3,y=5,height=1,width=1,fg_bg=text_fg}

    steam.register(ps, "steam_fill", steam.update)
    energy.register(ps, "energy_fill", energy.update)
end

return new_view
