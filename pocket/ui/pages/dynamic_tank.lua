local types          = require("scada-common.types")
local util           = require("scada-common.util")

local iocontrol      = require("pocket.iocontrol")

local style          = require("pocket.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local TextBox        = require("graphics.elements.TextBox")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local HorizontalBar  = require("graphics.elements.indicators.HorizontalBar")
local IconIndicator  = require("graphics.elements.indicators.IconIndicator")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")

local CONTAINER_MODE = types.CONTAINER_MODE
local COOLANT_TYPE = types.COOLANT_TYPE

local ALIGN = core.ALIGN
local cpair = core.cpair

local label   = style.label
local lu_col  = style.label_unit_pair
local text_fg = style.text_fg

local mode_ind_s = {
    { color = cpair(colors.black, colors.lightGray), symbol = "-" },
    { color = cpair(colors.black, colors.white), symbol = "+" }
}

-- create a dynamic tank view for the unit or facility app
---@param app pocket_app
---@param page nav_tree_page|nil parent page, if applicable
---@param panes Div[]
---@param tank_pane Div
---@param tank_id integer global facility tank ID (as used for tank list, etc)
---@param ps psil
---@param update function
return function (app, page, panes, tank_pane, tank_id, ps, update)
    local fac = iocontrol.get_db().facility

    local tank_div = Div{parent=tank_pane,x=2,width=tank_pane.get_width()-2}
    table.insert(panes, tank_div)

    local tank_page = app.new_page(page, #panes)
    tank_page.tasks = { update }

    local tank_assign = ""
    local f_tank_count = 0

    for i = 1, #fac.tank_list do
        local is_fac = fac.tank_list[i] == 2
        if is_fac then f_tank_count = f_tank_count + 1 end

        if i == tank_id then
            tank_assign = util.trinary(is_fac, "F-" .. f_tank_count, "U-" .. i)
            break
        end
    end

    TextBox{parent=tank_div,y=1,text="Dynamic Tank "..tank_assign,alignment=ALIGN.CENTER}
    local status = StateIndicator{parent=tank_div,x=5,y=3,states=style.dtank.states,value=1,min_width=12}
    status.register(ps, "DynamicTankStateStatus", status.update)

    TextBox{parent=tank_div,y=5,text="Fill",width=10,fg_bg=label}
    local tank_pcnt = DataIndicator{parent=tank_div,x=14,y=5,label="",format="%5.2f",value=100,unit="%",lu_colors=lu_col,width=8,fg_bg=text_fg}
    local tank_amnt = DataIndicator{parent=tank_div,label="",format="%18d",value=0,commas=true,unit="mB",lu_colors=lu_col,width=21,fg_bg=text_fg}

    local is_water = fac.tank_fluid_types[tank_id] == COOLANT_TYPE.WATER

    TextBox{parent=tank_div,y=8,text=util.trinary(is_water,"Water","Sodium").." Level",width=12,fg_bg=label}
    local level = HorizontalBar{parent=tank_div,y=9,bar_fg_bg=cpair(util.trinary(is_water,colors.blue,colors.lightBlue),colors.gray),height=1,width=21}

    TextBox{parent=tank_div,y=11,text="Tank Fill Mode",width=14,fg_bg=label}
    local can_fill = IconIndicator{parent=tank_div,y=12,label="Fill",states=mode_ind_s}
    local can_empty = IconIndicator{parent=tank_div,y=13,label="Empty",states=mode_ind_s}

    local function _can_fill(mode)
        can_fill.update((mode == CONTAINER_MODE.BOTH) or (mode == CONTAINER_MODE.FILL))
    end

    local function _can_empty(mode)
        can_empty.update((mode == CONTAINER_MODE.BOTH) or (mode == CONTAINER_MODE.EMPTY))
    end

    tank_pcnt.register(ps, "fill", function (f) tank_pcnt.update(f * 100) end)
    tank_amnt.register(ps, "stored", function (sto) tank_amnt.update(sto.amount) end)

    level.register(ps, "fill", level.update)

    can_fill.register(ps, "container_mode", _can_fill)
    can_empty.register(ps, "container_mode", _can_empty)

    return tank_page.nav_to
end
