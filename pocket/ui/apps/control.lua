--
-- Unit Control Page
--

local util          = require("scada-common.util")

local iocontrol     = require("pocket.iocontrol")
local pocket        = require("pocket.pocket")

local style         = require("pocket.ui.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.div")
local ListBox       = require("graphics.elements.listbox")
local MultiPane     = require("graphics.elements.multipane")
local TextBox       = require("graphics.elements.textbox")

local WaitingAnim   = require("graphics.elements.animations.waiting")

local HazardButton  = require("graphics.elements.controls.hazard_button")
local PushButton    = require("graphics.elements.controls.push_button")

local NumberField   = require("graphics.elements.form.number_field")

local DataIndicator = require("graphics.elements.indicators.data")
local IconIndicator = require("graphics.elements.indicators.icon")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

-- local label        = style.label
local lu_col       = style.label_unit_pair
local text_fg      = style.text_fg
local basic_states = style.icon_states.basic_states
local mode_states  = style.icon_states.mode_states
local red_ind_s    = style.icon_states.red_ind_s
local yel_ind_s    = style.icon_states.yel_ind_s


local hzd_fg_bg = cpair(colors.white, colors.gray)
local dis_colors = cpair(colors.white, colors.lightGray)

local emc_ind_s = {
    { color = cpair(colors.black, colors.gray), symbol = "-" },
    { color = cpair(colors.black, colors.white), symbol = "\x07" },
    { color = cpair(colors.black, colors.green), symbol = "+" }
}

-- new unit control page view
---@param root graphics_element parent
local function new_view(root)
    local db = iocontrol.get_db()

    local frame = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(APP_ID.CONTROL, frame, nil, false, true)

    local load_div = Div{parent=frame,x=1,y=1}
    local main = Div{parent=frame,x=1,y=1}

    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.green,colors._INHERIT)}

    local load_pane = MultiPane{parent=main,x=1,y=1,panes={load_div,main}}

    app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = function () db.nav.open_app(APP_ID.ROOT) end } })

    local btn_fg_bg = cpair(colors.green, colors.black)
    local btn_active = cpair(colors.white, colors.black)

    local page_div = nil ---@type nil|graphics_element

    -- set sidebar to display unit-specific fields based on a specified unit
    local function set_sidebar()
        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = function () db.nav.open_app(APP_ID.ROOT) end },
        }

        for i = 1, db.facility.num_units do
            table.insert(list, { label = "U-" .. i, color = core.cpair(colors.black, colors.lightGray), callback = function () app.switcher(i) end })
        end

        app.set_sidebar(list)
    end

    -- load the app (create the elements)
    local function load()
        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {}

        local active_unit = 1

        -- create all page divs
        for _ = 1, db.facility.num_units do
            local div = Div{parent=page_div}
            table.insert(panes, div)
        end

        -- previous unit
        local function prev(x)
            active_unit = util.trinary(x == 1, db.facility.num_units, x - 1)
            app.switcher(active_unit)
        end

        -- next unit
        local function next(x)
            active_unit = util.trinary(x == db.facility.num_units, 1, x + 1)
            app.switcher(active_unit)
        end

        for i = 1, db.facility.num_units do
            local u_pane = panes[i]
            local u_div = Div{parent=u_pane,x=2,width=main.get_width()-2}
            local unit = db.units[i] ---@type pioctl_unit
            local u_ps = unit.unit_ps

            -- refresh data callback, every 500ms it will re-send the query
            local last_update = 0
            local function update()
                if util.time_ms() - last_update >= 500 then
                    db.api.get_unit(i)
                    last_update = util.time_ms()
                end
            end

            --#region Main Unit Overview

            local u_page = app.new_page(nil, i)
            u_page.tasks = { update }

            TextBox{parent=u_div,y=1,text="Reactor Unit #"..i,alignment=ALIGN.CENTER}
            PushButton{parent=u_div,x=1,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()prev(i)end}
            PushButton{parent=u_div,x=21,y=1,text=">",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()next(i)end}

            local rate = DataIndicator{parent=u_div,y=3,lu_colors=lu_col,label="Burn",unit="mB/t",format="%10.2f",value=0,commas=true,width=26,fg_bg=text_fg}
            local temp = DataIndicator{parent=u_div,lu_colors=lu_col,label="Temp",unit=db.temp_label,format="%10.2f",value=0,commas=true,width=26,fg_bg=text_fg}

            local ctrl = IconIndicator{parent=u_div,x=1,y=6,label="Control State",states=mode_states}

            rate.register(u_ps, "act_burn_rate", rate.update)
            temp.register(u_ps, "temp", function (t) temp.update(db.temp_convert(t)) end)
            ctrl.register(u_ps, "U_ControlStatus", ctrl.update)

            u_div.line_break()

            TextBox{parent=u_div,y=8,text="CMD",width=4,fg_bg=cpair(colors.lightGray,colors.black)}
            TextBox{parent=u_div,x=14,y=8,text="mB/t",width=4,fg_bg=cpair(colors.lightGray,colors.black)}
            local burn_cmd = NumberField{parent=u_div,x=5,y=8,width=8,default=0.01,min=0.01,max_frac_digits=2,max_chars=8,allow_decimal=true,align_right=true,fg_bg=cpair(colors.white,colors.gray)}

            local set_burn = function () unit.set_burn(burn_cmd.get_value()) end
            local set_burn_btn = PushButton{parent=u_div,x=19,y=8,text="SET",min_width=5,fg_bg=cpair(colors.green,colors.black),active_fg_bg=cpair(colors.white,colors.black),dis_fg_bg=cpair(colors.gray,colors.black),callback=set_burn}

            burn_cmd.register(u_ps, "max_burn", burn_cmd.set_max)

            local start = HazardButton{parent=u_div,x=2,y=11,text="START",accent=colors.lightBlue,dis_colors=dis_colors,callback=unit.start,fg_bg=hzd_fg_bg}
            local ack_a = HazardButton{parent=u_div,x=12,y=11,text="ACK \x13",accent=colors.orange,dis_colors=dis_colors,callback=unit.ack_alarms,fg_bg=hzd_fg_bg}
            local scram = HazardButton{parent=u_div,x=2,y=15,text="SCRAM",accent=colors.yellow,dis_colors=dis_colors,callback=unit.scram,fg_bg=hzd_fg_bg}
            local reset = HazardButton{parent=u_div,x=12,y=15,text="RESET",accent=colors.red,dis_colors=dis_colors,callback=unit.reset_rps,fg_bg=hzd_fg_bg}

            --#endregion

            util.nop()
        end

        -- setup multipane
        local u_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(u_pane)

        set_sidebar()

        -- done, show the app
        load_pane.set_value(2)
    end

    -- delete the elements and switch back to the loading screen
    local function unload()
        if page_div then
            page_div.delete()
            page_div = nil
        end

        app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = function () db.nav.open_app(APP_ID.ROOT) end } })
        app.delete_pages()

        -- show loading screen
        load_pane.set_value(1)
    end

    app.set_load(load)
    app.set_unload(unload)

    return main
end

return new_view