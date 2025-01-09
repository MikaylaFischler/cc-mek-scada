--
-- Facility Overview App
--

local util          = require("scada-common.util")

local iocontrol     = require("pocket.iocontrol")
local pocket        = require("pocket.pocket")

local style         = require("pocket.ui.style")

local dyn_tank      = require("pocket.ui.pages.dynamic_tank")
local facility_sps  = require("pocket.ui.pages.facility_sps")
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
        local fac  = db.facility
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

        --#region facility overview

        local f_pane = Div{parent=page_div}
        local f_div = Div{parent=f_pane,x=2,width=main.get_width()-2}
        table.insert(panes, f_pane)

        local fac_page = app.new_page(nil, #panes)
        fac_page.tasks = { update }

        TextBox{parent=f_div,y=1,text="Facility",alignment=ALIGN.CENTER}

        local eta = TextBox{parent=f_div,x=1,y=17,text="ETA Unknown",alignment=ALIGN.CENTER,fg_bg=cpair(colors.white,colors.gray)}

        eta.register(fac.induction_ps_tbl[1], "eta_ms", function (eta_ms)
            local str, pre = "", util.trinary(eta_ms >= 0, "Full in ", "Empty in ")

            local seconds = math.abs(eta_ms) / 1000
            local minutes = seconds / 60
            local hours   = minutes / 60
            local days    = hours / 24

            if math.abs(eta_ms) < 1000 or (eta_ms ~= eta_ms) then
                -- really small or NaN
                str = "No ETA"
            elseif days < 1000 then
                days    = math.floor(days)
                hours   = math.floor(hours % 24)
                minutes = math.floor(minutes % 60)
                seconds = math.floor(seconds % 60)

                if days > 0 then
                    str = days .. "d"
                elseif hours > 0 then
                    str = hours .. "h " .. minutes .. "m"
                elseif minutes > 0 then
                    str = minutes .. "m " .. seconds .. "s"
                elseif seconds > 0 then
                    str = seconds .. "s"
                end

                str = pre .. str
            else
                local years = math.floor(days / 365.25)

                if years <= 99999999 then
                    str = pre .. years .. "y"
                else
                    str = pre .. "eras"
                end
            end

            eta.set_value(str)
        end)

        --#endregion

        --#region facility annunciator

        local a_pane = Div{parent=page_div}
        local a_div = Div{parent=a_pane,x=2,width=main.get_width()-2}
        table.insert(panes, a_pane)

        local annunc_page = app.new_page(nil, #panes)
        annunc_page.tasks = { update }

        TextBox{parent=a_div,y=1,text="Annunciator",alignment=ALIGN.CENTER}

        local all_ok  = IconIndicator{parent=a_div,y=3,label="Units Online",states=grn_ind_s}
        local ind_mat = IconIndicator{parent=a_div,label="Induction Matrix",states=grn_ind_s}
        local sps     = IconIndicator{parent=a_div,label="SPS Connected",states=grn_ind_s}

        all_ok.register(f_ps, "all_sys_ok", all_ok.update)
        -- ind_mat.register(fac.induction_ps_tbl[1], "computed_status", function (status) ind_mat.update(status > 1) end)
        -- sps.register(fac.sps_ps_tbl[1], "computed_status", function (status) sps.update(status > 1) end)

        a_div.line_break()

        local auto_scram  = IconIndicator{parent=a_div,label="Automatic SCRAM",states=red_ind_s}
        local matrix_flt  = IconIndicator{parent=a_div,label="Ind. Matrix Fault",states=yel_ind_s}
        local matrix_fill = IconIndicator{parent=a_div,label="Matrix Charge Hi",states=red_ind_s}
        local unit_crit   = IconIndicator{parent=a_div,label="Unit Crit. Alarm",states=red_ind_s}
        local fac_rad_h   = IconIndicator{parent=a_div,label="FAC Radiation Hi",states=red_ind_s}
        local gen_fault   = IconIndicator{parent=a_div,label="Gen Control Fault",states=yel_ind_s}

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

        --#region SPS

        local sps_page_nav = facility_sps(app, panes, Div{parent=page_div}, fac.sps_ps_tbl[1], update)

        --#endregion

        --#region facility tank pages

        local t_pane = Div{parent=page_div}
        local t_div = Div{parent=t_pane,x=2,width=main.get_width()-2}
        table.insert(panes, t_pane)

        local tank_page = app.new_page(nil, #panes)
        tank_page.tasks = { update }

        TextBox{parent=t_div,y=1,text="Facility Tanks",alignment=ALIGN.CENTER}

        for i = 1, #fac.tank_data_tbl do
            tank_page_navs[i] = dyn_tank(app, nil, panes, Div{parent=page_div}, i, fac.tank_ps_tbl[i], update)
        end

        --#endregion

        -- setup multipane
        local f_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(f_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = "FAC", color = core.cpair(colors.black, colors.orange), callback = fac_page.nav_to },
            { label = "ANN", color = core.cpair(colors.black, colors.yellow), callback = annunc_page.nav_to },
            { label = "MTX", color = core.cpair(colors.black, colors.white), callback = mtx_page_nav },
            { label = "SPS", color = core.cpair(colors.black, colors.purple), callback = sps_page_nav },
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
