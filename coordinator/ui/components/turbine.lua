local util           = require("scada-common.util")

local style          = require("coordinator.ui.style")

local core           = require("graphics.core")

local Rectangle      = require("graphics.elements.rectangle")

local DataIndicator  = require("graphics.elements.indicators.data")
local PowerIndicator = require("graphics.elements.indicators.power")
local StateIndicator = require("graphics.elements.indicators.state")
local VerticalBar    = require("graphics.elements.indicators.vbar")

local cpair = core.graphics.cpair
local border = core.graphics.border

-- new turbine view
---@param root graphics_element parent
---@param x integer top left x
---@param y integer top left y
---@param ps psil ps interface
local function new_view(root, x, y, ps)
    local turbine = Rectangle{parent=root,border=border(1, colors.gray, true),width=23,height=7,x=x,y=y}

    local text_fg_bg = cpair(colors.black, colors.lightGray)
    local lu_col = cpair(colors.gray, colors.gray)

    local status    = StateIndicator{parent=turbine,x=7,y=1,states=style.turbine.states,value=1,min_width=12}
    local prod_rate = PowerIndicator{parent=turbine,x=5,y=3,lu_colors=lu_col,label="",format="%10.2f",value=0,width=16,fg_bg=text_fg_bg}
    local flow_rate = DataIndicator{parent=turbine,x=5,y=4,lu_colors=lu_col,label="",unit="mB/t",format="%10.0f",value=0,commas=true,width=16,fg_bg=text_fg_bg}

    ps.subscribe("computed_status", status.update)
    ps.subscribe("prod_rate", function (val) prod_rate.update(util.joules_to_fe(val)) end)
    ps.subscribe("flow_rate", flow_rate.update)

    local steam = VerticalBar{parent=turbine,x=2,y=1,fg_bg=cpair(colors.white,colors.gray),height=5,width=2}

    ps.subscribe("steam_fill", steam.update)
end

return new_view
