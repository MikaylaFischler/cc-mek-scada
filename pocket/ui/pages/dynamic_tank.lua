local util           = require("scada-common.util")

local iocontrol      = require("pocket.iocontrol")

local style          = require("pocket.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local TextBox        = require("graphics.elements.TextBox")

local PushButton     = require("graphics.elements.controls.PushButton")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local IconIndicator  = require("graphics.elements.indicators.IconIndicator")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")
local VerticalBar    = require("graphics.elements.indicators.VerticalBar")

local ALIGN = core.ALIGN
local cpair = core.cpair

local label     = style.label
local lu_col    = style.label_unit_pair
local text_fg   = style.text_fg
local tri_ind_s = style.icon_states.tri_ind_s
local red_ind_s = style.icon_states.red_ind_s
local yel_ind_s = style.icon_states.yel_ind_s

-- create a dynamic tank view for the unit or facility app
---@param app pocket_app
---@param page nav_tree_page
---@param panes Div[]
---@param tank_pane Div
---@param ps psil
---@param update function
return function (app, page, panes, tank_pane, u_id, ps, update)
    local db = iocontrol.get_db()

    local tank_div = Div{parent=tank_pane,x=2,width=tank_pane.get_width()-2}
    table.insert(panes, tank_div)

    local tank_page = app.new_page(page, #panes)
    tank_page.tasks = { update }

    TextBox{parent=tank_div,y=1,text="Dyn Tank",width=9}
    local status = StateIndicator{parent=tank_div,x=10,y=1,states=style.dtank.states,value=1,min_width=12}
    status.register(ps, "DynamicTankStateStatus", status.update)
end
