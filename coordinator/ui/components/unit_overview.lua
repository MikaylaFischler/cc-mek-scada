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

---@param parent graphics_element
local function make(parent, x, y, unit_id)
    -- bounding box div
    local root = Div{parent=parent,x=x,y=y,width=75,height=50}

    -- unit header message
    TextBox{parent=root,text="Unit #" .. unit_id,alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    -- reactor
    local reactor = Rectangle{parent=root,border=border(1, colors.gray),width=30,height=10,x=1,y=3}

    local text_fg_bg = cpair(colors.black, colors.lightGray)
    local lu_col = cpair(colors.gray, colors.gray)

    local status    = StateIndicator{parent=reactor,x=9,y=2,states=style.reactor.states,value=1,min_width=14}
    local core_temp = DataIndicator{parent=reactor,x=3,y=4,lu_colors=lu_col,label="Core:   ",unit="K",format="%7.0f",value=295,width=26,fg_bg=text_fg_bg}
    local heating_r = DataIndicator{parent=reactor,x=3,y=5,lu_colors=lu_col,label="Heating:",unit="mB/t",format="%7.0f",value=359999,width=26,fg_bg=text_fg_bg}
    local burn_r    = DataIndicator{parent=reactor,x=3,y=6,lu_colors=lu_col,label="Burn:   ",unit="mB/t",format="%7.1f",value=40.1,width=26,fg_bg=text_fg_bg}

    local fuel    = HorizontalBar{parent=root,x=34,y=4,show_percent=true,bar_fg_bg=cpair(colors.brown,colors.white),height=1,width=14}
    local coolant = HorizontalBar{parent=root,x=34,y=5,show_percent=true,bar_fg_bg=cpair(colors.lightBlue,colors.white),height=1,width=14}

    fuel.update(0.85)
    coolant.update(0.75)
end

return make
