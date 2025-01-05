--
-- Facility Overview App
--

local util          = require("scada-common.util")

local iocontrol     = require("pocket.iocontrol")
local pocket        = require("pocket.pocket")

local style         = require("pocket.ui.style")

local dyn_tank      = require("pocket.ui.pages.dynamic_tank")
local induction_mtx = require("pocket.ui.pages.facility_matrix")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local ListBox       = require("graphics.elements.ListBox")
local MultiPane     = require("graphics.elements.MultiPane")
local TextBox       = require("graphics.elements.TextBox")

local WaitingAnim    = require("graphics.elements.animations.Waiting")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local IconIndicator  = require("graphics.elements.indicators.IconIndicator")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

local text_fg      = style.text_fg
local label_fg_bg  = style.label
local lu_col       = style.label_unit_pair

local basic_states = style.icon_states.basic_states
local mode_states  = style.icon_states.mode_states
local red_ind_s    = style.icon_states.red_ind_s
local yel_ind_s    = style.icon_states.yel_ind_s
local grn_ind_s    = style.icon_states.grn_ind_s
local wht_ind_s    = style.icon_states.wht_ind_s

-- new unit page view
---@param root Container parent
local function new_view(root)
    local db  = iocontrol.get_db()
    local fac = db.facility

    local frame = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(APP_ID.FACILITY, frame, nil, false, true)

    local load_div = Div{parent=frame,x=1,y=1}
    local main = Div{parent=frame,x=1,y=1}

    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.orange,colors._INHERIT)}

    local load_pane = MultiPane{parent=main,x=1,y=1,panes={load_div,main}}

    app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })

    local btn_fg_bg = cpair(colors.orange, colors.black)
    local btn_active = cpair(colors.white, colors.black)

    local tank_page_navs = {}
    local page_div = nil ---@type Div|nil

    -- load the app (create the elements)
    local function load()
        local f_ps = fac.ps

        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {} ---@type Div[]

        -- refresh data callback, every 500ms it will re-send the query
        local last_update = 0
        local function update()
            if util.time_ms() - last_update >= 500 then
                -- db.api.get_fac()
                last_update = util.time_ms()
            end
        end

        --#region facility annunciator

        local a_pane = Div{parent=page_div}
        local a_div = Div{parent=a_pane,x=2,width=main.get_width()-2}
        table.insert(panes, a_pane)

        local f_annunc = app.new_page(nil, #panes)
        f_annunc.tasks = { update }

        TextBox{parent=a_div,y=1,text="Annunciator",alignment=ALIGN.CENTER}

        local all_ok  = IconIndicator{parent=a_div,y=3,label="Unit Systems Online",states=grn_ind_s}
        local ind_mat = IconIndicator{parent=a_div,label="Induction Matrix",states=grn_ind_s}
        local sps     = IconIndicator{parent=a_div,label="SPS Connected",states=grn_ind_s}

        all_ok.register(f_ps, "all_sys_ok", all_ok.update)
        ind_mat.register(fac.induction_ps_tbl[1], "computed_status", function (status) ind_mat.update(status > 1) end)
        sps.register(fac.sps_ps_tbl[1], "computed_status", function (status) sps.update(status > 1) end)

        a_div.line_break()

        local auto_ready = IconIndicator{parent=a_div,label="Configured Units Ready",states=grn_ind_s}
        local auto_act   = IconIndicator{parent=a_div,label="Process Active",states=grn_ind_s}
        local auto_ramp  = IconIndicator{parent=a_div,label="Process Ramping",states=wht_ind_s}
        local auto_sat   = IconIndicator{parent=a_div,label="Min/Max Burn Rate",states=yel_ind_s}

        auto_ready.register(f_ps, "auto_ready", auto_ready.update)
        auto_act.register(f_ps, "auto_active", auto_act.update)
        auto_ramp.register(f_ps, "auto_ramping", auto_ramp.update)
        auto_sat.register(f_ps, "auto_saturated", auto_sat.update)

        a_div.line_break()

        local auto_scram  = IconIndicator{parent=a_div,label="Automatic SCRAM",states=red_ind_s}
        local matrix_flt  = IconIndicator{parent=a_div,label="Induction Matrix Fault",states=yel_ind_s}
        local matrix_fill = IconIndicator{parent=a_div,label="Matrix Charge High",states=red_ind_s}
        local unit_crit   = IconIndicator{parent=a_div,label="Unit Critical Alarm",states=red_ind_s}
        local fac_rad_h   = IconIndicator{parent=a_div,label="Facility Radiation High",states=red_ind_s}
        local gen_fault   = IconIndicator{parent=a_div,label="Gen. Control Fault",states=yel_ind_s}

        auto_scram.register(f_ps, "auto_scram", auto_scram.update)
        matrix_flt.register(f_ps, "as_matrix_fault", matrix_flt.update)
        matrix_fill.register(f_ps, "as_matrix_fill", matrix_fill.update)
        unit_crit.register(f_ps, "as_crit_alarm", unit_crit.update)
        fac_rad_h.register(f_ps, "as_radiation", fac_rad_h.update)
        gen_fault.register(f_ps, "as_gen_fault", gen_fault.update)

        --#endregion

        --#region induction matrix

        local mtx_page_nav = induction_mtx(app, panes, Div{parent=page_div}, fac.induction_ps_tbl[1], update)

        --#endregion

        --#region SPS page

        local s_pane = Div{parent=page_div}
        local s_div = Div{parent=s_pane,x=2,width=main.get_width()-2}
        table.insert(panes, s_pane)

        local sps_page = app.new_page(nil, #panes)
        sps_page.tasks = { update }

        TextBox{parent=s_div,y=1,text="Facility SPS",alignment=ALIGN.CENTER}

        local sps_status = StateIndicator{parent=s_div,x=5,y=3,states=style.sps.states,value=1,min_width=12}

        sps_status.register(f_ps, "sps_computed_status", sps_status.update)

        TextBox{parent=s_div,y=5,text="Input Rate",width=10,fg_bg=label_fg_bg}
        local sps_in = DataIndicator{parent=s_div,label="",format="%16.2f",value=0,unit="mB/t",lu_colors=lu_col,width=21,fg_bg=text_fg}

        sps_in.register(f_ps, "po_am_rate", sps_in.update)

        TextBox{parent=s_div,y=8,text="Production Rate",width=15,fg_bg=label_fg_bg}
        local sps_rate = DataIndicator{parent=s_div,label="",format="%16d",value=0,unit="\xb5B/t",lu_colors=lu_col,width=21,fg_bg=text_fg}

        sps_rate.register(f_ps, "sps_process_rate", function (r) sps_rate.update(r * 1000) end)

        --#endregion

        --#region facility tank pages

        local t_pane = Div{parent=page_div}
        local t_div = Div{parent=t_pane,x=2,width=main.get_width()-2}
        table.insert(panes, t_pane)

        local tank_page = app.new_page(nil, #panes)
        tank_page.tasks = { update }

        TextBox{parent=t_div,y=1,text="Facility Tanks",alignment=ALIGN.CENTER}

        for i = 1, fac.tank_data_tbl do
            tank_page_navs[i] = dyn_tank(app, nil, panes, Div{parent=page_div}, i, fac.tank_ps_tbl[i], update)
        end

        --#endregion

        -- setup multipane
        local f_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(f_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = "FAC", color = core.cpair(colors.black, colors.orange), callback = f_annunc.nav_to },
            { label = "MTX", color = core.cpair(colors.black, colors.white), callback = mtx_page_nav },
            { label = "SPS", color = core.cpair(colors.black, colors.purple), callback = sps_page.nav_to },
            { label = "TNK", tall = true, color = core.cpair(colors.white, colors.gray), callback = tank_page.nav_to }
        }

        for i = 1, #fac.tank_data_tbl do
            table.insert(list, { label = "F-" .. i, color = core.cpair(colors.black, colors.lightGray), callback = tank_page_navs[i] })
        end

        app.set_sidebar(list)

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
