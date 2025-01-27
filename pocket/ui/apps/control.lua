--
-- Facility & Unit Control App
--

local types         = require("scada-common.types")
local util          = require("scada-common.util")

local iocontrol     = require("pocket.iocontrol")
local pocket        = require("pocket.pocket")
local process       = require("pocket.process")

local style         = require("pocket.ui.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local MultiPane     = require("graphics.elements.MultiPane")
local TextBox       = require("graphics.elements.TextBox")

local WaitingAnim   = require("graphics.elements.animations.Waiting")

local HazardButton  = require("graphics.elements.controls.HazardButton")
local PushButton    = require("graphics.elements.controls.PushButton")

local NumberField   = require("graphics.elements.form.NumberField")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")
local IconIndicator = require("graphics.elements.indicators.IconIndicator")

local AUTO_GROUP = types.AUTO_GROUP

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

local label_fg_bg    = style.label
local lu_col         = style.label_unit_pair
local text_fg        = style.text_fg

local mode_states    = style.icon_states.mode_states

local btn_active     = cpair(colors.white, colors.black)
local hzd_fg_bg      = style.hzd_fg_bg
local hzd_dis_colors = style.hzd_dis_colors

-- new unit control page view
---@param root Container parent
local function new_view(root)
    local btn_fg_bg = cpair(colors.green, colors.black)

    local db = iocontrol.get_db()

    local frame = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(APP_ID.CONTROL, frame, nil, false, true)

    local load_div = Div{parent=frame,x=1,y=1}
    local main = Div{parent=frame,x=1,y=1}

    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.green,colors._INHERIT)}

    local load_pane = MultiPane{parent=main,x=1,y=1,panes={load_div,main}}

    app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })

    local page_div = nil ---@type Div|nil

    -- set sidebar to display unit-specific fields based on a specified unit
    local function set_sidebar()
        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = "FAC", color = core.cpair(colors.black, colors.orange), callback = function () app.switcher(db.facility.num_units + 1) end }
        }

        for i = 1, db.facility.num_units do
            table.insert(list, { label = "U-" .. i, color = core.cpair(colors.black, colors.lightGray), callback = function () app.switcher(i) end })
        end

        app.set_sidebar(list)
    end

    -- load the app (create the elements)
    local function load()
        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {} ---@type Div[]

        local active_unit = 1

        -- create all page divs
        for _ = 1, db.facility.num_units + 1 do
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

        local last_update = 0
        -- refresh data callback, every 500ms it will re-send the query
        local function update()
            if util.time_ms() - last_update >= 500 then
                db.api.get_ctrl()
                last_update = util.time_ms()
            end
        end

        for i = 1, db.facility.num_units do
            local u_pane = panes[i]
            local u_div = Div{parent=u_pane,x=2,width=main.get_width()-2}
            local unit = db.units[i]
            local u_ps = unit.unit_ps

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

            TextBox{parent=u_div,y=8,text="CMD",width=4,fg_bg=label_fg_bg}
            TextBox{parent=u_div,x=14,y=8,text="mB/t",width=4,fg_bg=label_fg_bg}
            local burn_cmd = NumberField{parent=u_div,x=5,y=8,width=8,default=0.01,min=0.01,max_frac_digits=2,max_chars=8,allow_decimal=true,align_right=true,fg_bg=style.field,dis_fg_bg=style.field_disable}

            local set_burn = function () unit.set_burn(burn_cmd.get_numeric()) end
            local set_burn_btn = PushButton{parent=u_div,x=19,y=8,text="SET",min_width=5,fg_bg=cpair(colors.green,colors.black),active_fg_bg=cpair(colors.white,colors.black),dis_fg_bg=style.btn_disable,callback=set_burn}

            -- enable/disable controls based on group assignment (start button is separate)
            burn_cmd.register(u_ps, "auto_group_id", function (gid)
                if gid == AUTO_GROUP.MANUAL then burn_cmd.enable() else burn_cmd.disable() end
            end)
            set_burn_btn.register(u_ps, "auto_group_id", function (gid)
                if gid == AUTO_GROUP.MANUAL then set_burn_btn.enable() else set_burn_btn.disable() end
            end)

            burn_cmd.register(u_ps, "burn_rate", burn_cmd.set_value)
            burn_cmd.register(u_ps, "max_burn", burn_cmd.set_max)

            local start = HazardButton{parent=u_div,x=2,y=11,text="START",accent=colors.lightBlue,callback=unit.start,timeout=3,fg_bg=hzd_fg_bg,dis_colors=hzd_dis_colors}
            local ack_a = HazardButton{parent=u_div,x=12,y=11,text="ACK \x13",accent=colors.orange,callback=unit.ack_alarms,timeout=3,fg_bg=hzd_fg_bg,dis_colors=hzd_dis_colors}
            local scram = HazardButton{parent=u_div,x=2,y=15,text="SCRAM",accent=colors.yellow,callback=unit.scram,timeout=3,fg_bg=hzd_fg_bg,dis_colors=hzd_dis_colors}
            local reset = HazardButton{parent=u_div,x=12,y=15,text="RESET",accent=colors.red,callback=unit.reset_rps,timeout=3,fg_bg=hzd_fg_bg,dis_colors=hzd_dis_colors}

            unit.start_ack = start.on_response
            unit.ack_alarms_ack = ack_a.on_response
            unit.scram_ack = scram.on_response
            unit.reset_rps_ack = reset.on_response

            local function start_button_en_check()
                local can_start = (not unit.reactor_data.mek_status.status) and
                                    (not unit.reactor_data.rps_tripped) and
                                    (unit.a_group == AUTO_GROUP.MANUAL)
                if can_start then start.enable() else start.disable() end
            end

            start.register(u_ps, "status", start_button_en_check)
            start.register(u_ps, "rps_tripped", start_button_en_check)
            start.register(u_ps, "auto_group_id", start_button_en_check)
            start.register(u_ps, "AutoControl", start_button_en_check)

            reset.register(u_ps, "rps_tripped", function (active) if active then reset.enable() else reset.disable() end end)

            util.nop()
        end

        -- facility controls

        local f_pane = panes[db.facility.num_units + 1]
        local f_div = Div{parent=f_pane,x=2,width=main.get_width()-2}

        app.new_page(nil, db.facility.num_units + 1)

        TextBox{parent=f_div,y=1,text="Facility Commands",alignment=ALIGN.CENTER}

        local scram = HazardButton{parent=f_div,x=5,y=6,text="FAC SCRAM",accent=colors.yellow,dis_colors=hzd_dis_colors,callback=process.fac_scram,timeout=3,fg_bg=hzd_fg_bg}
        local ack_a = HazardButton{parent=f_div,x=7,y=11,text="ACK \x13",accent=colors.orange,dis_colors=hzd_dis_colors,callback=process.fac_ack_alarms,timeout=3,fg_bg=hzd_fg_bg}

        db.facility.scram_ack = scram.on_response
        db.facility.ack_alarms_ack = ack_a.on_response

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

        app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })
        app.delete_pages()

        -- show loading screen
        load_pane.set_value(1)
    end

    app.set_load(load)
    app.set_unload(unload)

    return main
end

return new_view
