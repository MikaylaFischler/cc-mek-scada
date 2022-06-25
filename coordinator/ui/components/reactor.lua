local core = require("graphics.core")

local style = require("coordinator.ui.style")

local Div            = require("graphics.elements.div")
local HorizontalBar  = require("graphics.elements.indicators.hbar")
local DataIndicator  = require("graphics.elements.indicators.data")
local StateIndicator = require("graphics.elements.indicators.state")
local Rectangle      = require("graphics.elements.rectangle")
local TextBox        = require("graphics.elements.textbox")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local cpair = core.graphics.cpair
local border = core.graphics.border

local function new_view(root, x, y)
    local reactor = Rectangle{parent=root,border=border(1, colors.gray, true),width=30,height=7,x=x,y=y}

    local text_fg_bg = cpair(colors.black, colors.lightGray)
    local lu_col = cpair(colors.gray, colors.gray)

    local status    = StateIndicator{parent=reactor,x=8,y=1,states=style.reactor.states,value=3,min_width=14}
    local core_temp = DataIndicator{parent=reactor,x=2,y=3,lu_colors=lu_col,label="Core:   ",unit="K",format="%12.2f",value=451.12,width=26,fg_bg=text_fg_bg}
    local burn_r    = DataIndicator{parent=reactor,x=2,y=4,lu_colors=lu_col,label="Burn:   ",unit="mB/t",format="%12.1f",value=40.1,width=26,fg_bg=text_fg_bg}
    local heating_r = DataIndicator{parent=reactor,x=2,y=5,lu_colors=lu_col,label="Heating:",unit="mB/t",format="%12.0f",value=8015342,commas=true,width=26,fg_bg=text_fg_bg}

    local reactor_fills = Rectangle{parent=root,border=border(1, colors.gray, true),width=24,height=7,x=(x + 29),y=y}

    TextBox{parent=reactor_fills,text="FUEL",x=2,y=1,height=1,fg_bg=text_fg_bg}
    TextBox{parent=reactor_fills,text="COOL",x=2,y=2,height=1,fg_bg=text_fg_bg}
    TextBox{parent=reactor_fills,text="HCOOL",x=2,y=4,height=1,fg_bg=text_fg_bg}
    TextBox{parent=reactor_fills,text="WASTE",x=2,y=5,height=1,fg_bg=text_fg_bg}

    local fuel  = HorizontalBar{parent=reactor_fills,x=8,y=1,show_percent=true,bar_fg_bg=cpair(colors.black,colors.gray),height=1,width=14}
    local cool  = HorizontalBar{parent=reactor_fills,x=8,y=2,show_percent=true,bar_fg_bg=cpair(colors.lightBlue,colors.gray),height=1,width=14}
    local hcool = HorizontalBar{parent=reactor_fills,x=8,y=4,show_percent=true,bar_fg_bg=cpair(colors.orange,colors.gray),height=1,width=14}
    local waste = HorizontalBar{parent=reactor_fills,x=8,y=5,show_percent=true,bar_fg_bg=cpair(colors.brown,colors.gray),height=1,width=14}

    fuel.update(1)
    cool.update(0.85)
    hcool.update(0.08)
    waste.update(0.32)
end

return new_view
