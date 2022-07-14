local core = require("graphics.core")

local style = require("coordinator.ui.style")

local DataIndicator  = require("graphics.elements.indicators.data")
local StateIndicator = require("graphics.elements.indicators.state")
local Rectangle      = require("graphics.elements.rectangle")
local TextBox        = require("graphics.elements.textbox")
local VerticalBar    = require("graphics.elements.indicators.vbar")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border

-- new boiler view
---@param root graphics_element
---@param x integer
---@param y integer
---@param ps psil
local function new_view(root, x, y, ps)
    local boiler = Rectangle{parent=root,border=border(1, colors.gray, true),width=31,height=7,x=x,y=y}

    local text_fg_bg = cpair(colors.black, colors.lightGray)
    local lu_col = cpair(colors.gray, colors.gray)

    local status = StateIndicator{parent=boiler,x=10,y=1,states=style.boiler.states,value=3,min_width=10}
    local temp   = DataIndicator{parent=boiler,x=5,y=3,lu_colors=lu_col,label="Temp:",unit="K",format="%10.2f",value=1900,width=22,fg_bg=text_fg_bg}
    local boil_r = DataIndicator{parent=boiler,x=5,y=4,lu_colors=lu_col,label="Boil:",unit="mB/t",format="%10.0f",value=801523,commas=true,width=22,fg_bg=text_fg_bg}

    ps.subscribe("status", status.update)
    ps.subscribe("temp", temp.update)
    ps.subscribe("boil_rate", boil_r.update)

    TextBox{parent=boiler,text="H",x=2,y=5,height=1,width=1,fg_bg=text_fg_bg}
    TextBox{parent=boiler,text="W",x=3,y=5,height=1,width=1,fg_bg=text_fg_bg}
    TextBox{parent=boiler,text="S",x=27,y=5,height=1,width=1,fg_bg=text_fg_bg}
    TextBox{parent=boiler,text="C",x=28,y=5,height=1,width=1,fg_bg=text_fg_bg}

    local hcool = VerticalBar{parent=boiler,x=2,y=1,fg_bg=cpair(colors.orange,colors.gray),height=4,width=1}
    local water = VerticalBar{parent=boiler,x=3,y=1,fg_bg=cpair(colors.blue,colors.gray),height=4,width=1}
    local steam = VerticalBar{parent=boiler,x=27,y=1,fg_bg=cpair(colors.white,colors.gray),height=4,width=1}
    local ccool = VerticalBar{parent=boiler,x=28,y=1,fg_bg=cpair(colors.lightBlue,colors.gray),height=4,width=1}

    ps.subscribe("hcool", hcool.update)
    ps.subscribe("water", water.update)
    ps.subscribe("steam", steam.update)
    ps.subscribe("ccool", ccool.update)

    hcool.update(0.22)
    water.update(1)
    steam.update(0.05)
    ccool.update(0.13)
end

return new_view
