local style          = require("coordinator.ui.style")

local iocontrol      = require("coordinator.iocontrol")

local core           = require("graphics.core")

local Rectangle      = require("graphics.elements.rectangle")
local TextBox        = require("graphics.elements.textbox")

local DataIndicator  = require("graphics.elements.indicators.data")
local StateIndicator = require("graphics.elements.indicators.state")
local VerticalBar    = require("graphics.elements.indicators.vbar")

local cpair = core.cpair
local border = core.border

-- new boiler view
---@param root graphics_element parent
---@param x integer top left x
---@param y integer top left y
---@param ps psil ps interface
local function new_view(root, x, y, ps)
    local text_fg = style.theme.text_fg
    local lu_col = style.lu_colors

    local db = iocontrol.get_db()

    local boiler = Rectangle{parent=root,border=border(1,colors.gray,true),width=31,height=7,x=x,y=y}

    local status = StateIndicator{parent=boiler,x=9,y=1,states=style.boiler.states,value=1,min_width=12}
    local temp   = DataIndicator{parent=boiler,x=5,y=3,lu_colors=lu_col,label="Temp:",unit=db.temp_label,format="%10.2f",value=0,commas=true,width=22,fg_bg=text_fg}
    local boil_r = DataIndicator{parent=boiler,x=5,y=4,lu_colors=lu_col,label="Boil:",unit="mB/t",format="%10.0f",value=0,commas=true,width=22,fg_bg=text_fg}

    status.register(ps, "computed_status", status.update)
    temp.register(ps, "temperature", function (t) temp.update(db.temp_convert(t)) end)
    boil_r.register(ps, "boil_rate", boil_r.update)

    TextBox{parent=boiler,text="H",x=2,y=5,height=1,width=1,fg_bg=text_fg}
    TextBox{parent=boiler,text="W",x=3,y=5,height=1,width=1,fg_bg=text_fg}
    TextBox{parent=boiler,text="S",x=27,y=5,height=1,width=1,fg_bg=text_fg}
    TextBox{parent=boiler,text="C",x=28,y=5,height=1,width=1,fg_bg=text_fg}

    local hcool = VerticalBar{parent=boiler,x=2,y=1,fg_bg=cpair(colors.orange,colors.gray),height=4,width=1}
    local water = VerticalBar{parent=boiler,x=3,y=1,fg_bg=cpair(colors.blue,colors.gray),height=4,width=1}
    local steam = VerticalBar{parent=boiler,x=27,y=1,fg_bg=cpair(colors.white,colors.gray),height=4,width=1}
    local ccool = VerticalBar{parent=boiler,x=28,y=1,fg_bg=cpair(colors.lightBlue,colors.gray),height=4,width=1}

    hcool.register(ps, "hcool_fill", hcool.update)
    water.register(ps, "water_fill", water.update)
    steam.register(ps, "steam_fill", steam.update)
    ccool.register(ps, "ccool_fill", ccool.update)
end

return new_view
