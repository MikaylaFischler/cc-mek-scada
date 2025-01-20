--
-- Waste Control App
--

local util           = require("scada-common.util")

local iocontrol      = require("pocket.iocontrol")
local pocket         = require("pocket.pocket")
local process        = require("pocket.process")

local style          = require("pocket.ui.style")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local MultiPane      = require("graphics.elements.MultiPane")
local TextBox        = require("graphics.elements.TextBox")

local WaitingAnim    = require("graphics.elements.animations.Waiting")

local Checkbox       = require("graphics.elements.controls.Checkbox")
local PushButton     = require("graphics.elements.controls.PushButton")
local RadioButton    = require("graphics.elements.controls.RadioButton")

local DataIndicator  = require("graphics.elements.indicators.DataIndicator")
local IconIndicator  = require("graphics.elements.indicators.IconIndicator")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

local label_fg_bg = style.label
local text_fg     = style.text_fg
local lu_col      = style.label_unit_pair
local yel_ind_s   = style.icon_states.yel_ind_s
local wht_ind_s   = style.icon_states.wht_ind_s

-- new waste control page view
---@param root Container parent
local function new_view(root)
    local db = iocontrol.get_db()

    local frame = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(APP_ID.WASTE, frame, nil, false, true)

    local load_div = Div{parent=frame,x=1,y=1}
    local main = Div{parent=frame,x=1,y=1}

    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.brown,colors._INHERIT)}

    local load_pane = MultiPane{parent=main,x=1,y=1,panes={load_div,main}}

    app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })

    local page_div = nil ---@type Div|nil

    -- load the app (create the elements)
    local function load()
        local f_ps = db.facility.ps

        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes   = {} ---@type Div[]
        local u_pages = {} ---@type nav_tree_page[]

        local last_update = 0
        -- refresh data callback, every 500ms it will re-send the query
        local function update()
            if util.time_ms() - last_update >= 500 then
                db.api.get_waste()
                last_update = util.time_ms()
            end
        end

        --#region unit waste options/statistics

        for i = 1, db.facility.num_units do
            local u_pane = Div{parent=page_div}
            local u_div = Div{parent=u_pane,x=2,width=main.get_width()-2}
            local unit = db.units[i]
            local u_ps = unit.unit_ps

            table.insert(panes, u_div)

            local u_page = app.new_page(nil, #panes)
            u_page.tasks = { update }

            table.insert(u_pages, u_page)

            TextBox{parent=u_div,y=1,text="Reactor Unit #"..i,alignment=ALIGN.CENTER}

            local function set_waste(mode) process.set_unit_waste(i, mode) end

            local waste_prod = StateIndicator{parent=u_div,x=16,y=3,states=style.waste.states_abbrv,value=1,min_width=6}
            local waste_mode = RadioButton{parent=u_div,y=3,options=style.waste.unit_opts,callback=set_waste,radio_colors=cpair(colors.lightGray,colors.gray),select_color=colors.white}

            waste_prod.register(u_ps, "U_WasteProduct", waste_prod.update)
            waste_mode.register(u_ps, "U_WasteMode", waste_mode.set_value)

            TextBox{parent=u_div,y=8,text="Plutonium (Pellets)",fg_bg=label_fg_bg}
            local pu = DataIndicator{parent=u_div,label="",format="%16.3f",value=0,unit="mB/t",lu_colors=lu_col,width=21,fg_bg=text_fg}
            TextBox{parent=u_div,y=11,text="Polonium",fg_bg=label_fg_bg}
            local po = DataIndicator{parent=u_div,label="",format="%16.3f",value=0,unit="mB/t",lu_colors=lu_col,width=21,fg_bg=text_fg}
            TextBox{parent=u_div,y=14,text="Polonium (Pellets)",fg_bg=label_fg_bg}
            local popl = DataIndicator{parent=u_div,label="",format="%16.3f",value=0,unit="mB/t",lu_colors=lu_col,width=21,fg_bg=text_fg}

            pu.register(u_ps, "pu_rate", pu.update)
            po.register(u_ps, "po_rate", po.update)
            popl.register(u_ps, "po_pl_rate", popl.update)

            local sna_div = Div{parent=u_pane,x=2,width=page_div.get_width()-2}
            table.insert(panes, sna_div)

            local sps_page = app.new_page(u_page, #panes)
            sps_page.tasks = { update }

            PushButton{parent=u_div,x=6,y=18,text="SNA DATA",min_width=12,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=sps_page.nav_to}
            PushButton{parent=sna_div,x=9,y=18,text="BACK",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=u_page.nav_to}

            TextBox{parent=sna_div,y=1,text="Unit "..i.." SNAs",alignment=ALIGN.CENTER}
            TextBox{parent=sna_div,y=3,text="Connected",fg_bg=label_fg_bg}
            local count = DataIndicator{parent=sna_div,x=20,y=3,label="",format="%2d",value=0,unit="",lu_colors=lu_col,width=2,fg_bg=text_fg}

            TextBox{parent=sna_div,y=5,text="Peak Possible Rate\n In\n Out",fg_bg=label_fg_bg}
            local peak_i = DataIndicator{parent=sna_div,x=6,y=6,label="",format="%11.2f",value=0,unit="mB/t",lu_colors=lu_col,width=17,fg_bg=text_fg}
            local peak_o = DataIndicator{parent=sna_div,x=6,label="",format="%11.2f",value=0,unit="mB/t",lu_colors=lu_col,width=17,fg_bg=text_fg}

            TextBox{parent=sna_div,y=9,text="Current Maximum Rate\n In\n Out",fg_bg=label_fg_bg}
            local max_i = DataIndicator{parent=sna_div,x=6,y=10,label="",format="%11.2f",value=0,unit="mB/t",lu_colors=lu_col,width=17,fg_bg=text_fg}
            local max_o = DataIndicator{parent=sna_div,x=6,label="",format="%11.2f",value=0,unit="mB/t",lu_colors=lu_col,width=17,fg_bg=text_fg}

            TextBox{parent=sna_div,y=13,text="Current Rate\n In\n Out",fg_bg=label_fg_bg}
            local cur_i = DataIndicator{parent=sna_div,x=6,y=14,label="",format="%11.2f",value=0,unit="mB/t",lu_colors=lu_col,width=17,fg_bg=text_fg}
            local cur_o = DataIndicator{parent=sna_div,x=6,label="",format="%11.2f",value=0,unit="mB/t",lu_colors=lu_col,width=17,fg_bg=text_fg}

            count.register(u_ps, "sna_count", count.update)
            peak_i.register(u_ps, "sna_peak_rate", function (x) peak_i.update(x * 10) end)
            peak_o.register(u_ps, "sna_peak_rate", peak_o.update)
            max_i.register(u_ps, "sna_max_rate", function (x) max_i.update(x * 10) end)
            max_o.register(u_ps, "sna_max_rate", max_o.update)
            cur_i.register(u_ps, "sna_out_rate", function (x) cur_i.update(x * 10) end)
            cur_o.register(u_ps, "sna_out_rate", cur_o.update)
        end

        --#endregion

        --#region waste control page

        local c_pane = Div{parent=page_div}
        local c_div = Div{parent=c_pane,x=2,width=main.get_width()-2}
        table.insert(panes, c_div)

        local wst_ctrl = app.new_page(nil, #panes)
        wst_ctrl.tasks = { update }

        TextBox{parent=c_div,y=1,text="Waste Control",alignment=ALIGN.CENTER}

        local status = StateIndicator{parent=c_div,x=3,y=3,states=style.waste.states,value=1,min_width=17}
        local waste_prod = RadioButton{parent=c_div,y=5,options=style.waste.options,callback=process.set_process_waste,radio_colors=cpair(colors.lightGray,colors.gray),select_color=colors.white}

        status.register(f_ps, "current_waste_product", status.update)
        waste_prod.register(f_ps, "process_waste_product", waste_prod.set_value)

        local fb_active = IconIndicator{parent=c_div,y=9,label="Fallback Active",states=wht_ind_s}
        local sps_disabled = IconIndicator{parent=c_div,y=10,label="SPS Disabled LC",states=yel_ind_s}

        fb_active.register(f_ps, "pu_fallback_active", fb_active.update)
        sps_disabled.register(f_ps, "sps_disabled_low_power", sps_disabled.update)

        TextBox{parent=c_div,y=12,text="Nuclear Waste In",fg_bg=label_fg_bg}
        local sum_raw_waste = DataIndicator{parent=c_div,label="",format="%16.3f",value=0,unit="mB/t",lu_colors=lu_col,width=21,fg_bg=text_fg}

        sum_raw_waste.register(f_ps, "burn_sum", sum_raw_waste.update)

        TextBox{parent=c_div,y=15,text="Spent Waste Out",fg_bg=label_fg_bg}
        local sum_sp_waste = DataIndicator{parent=c_div,label="",format="%16.3f",value=0,unit="mB/t",lu_colors=lu_col,width=21,fg_bg=text_fg}

        sum_sp_waste.register(f_ps, "spent_waste_rate", sum_sp_waste.update)

        local stats_div = Div{parent=c_pane,x=2,width=page_div.get_width()-2}
        table.insert(panes, stats_div)

        local stats_page = app.new_page(wst_ctrl, #panes)
        stats_page.tasks = { update }

        PushButton{parent=c_div,x=6,y=18,text="PROD RATES",min_width=12,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=stats_page.nav_to}
        PushButton{parent=stats_div,x=9,y=18,text="BACK",min_width=6,fg_bg=cpair(colors.lightGray,colors.gray),active_fg_bg=cpair(colors.gray,colors.lightGray),callback=wst_ctrl.nav_to}

        TextBox{parent=stats_div,y=1,text="Production Rates",alignment=ALIGN.CENTER}

        TextBox{parent=stats_div,y=3,text="Plutonium (Pellets)",fg_bg=label_fg_bg}
        local pu = DataIndicator{parent=stats_div,label="",format="%16.3f",value=0,unit="mB/t",lu_colors=lu_col,width=21,fg_bg=text_fg}
        TextBox{parent=stats_div,y=6,text="Polonium",fg_bg=label_fg_bg}
        local po = DataIndicator{parent=stats_div,label="",format="%16.3f",value=0,unit="mB/t",lu_colors=lu_col,width=21,fg_bg=text_fg}
        TextBox{parent=stats_div,y=9,text="Polonium (Pellets)",fg_bg=label_fg_bg}
        local popl = DataIndicator{parent=stats_div,label="",format="%16.3f",value=0,unit="mB/t",lu_colors=lu_col,width=21,fg_bg=text_fg}

        pu.register(f_ps, "pu_rate", pu.update)
        po.register(f_ps, "po_rate", po.update)
        popl.register(f_ps, "po_pl_rate", popl.update)

        TextBox{parent=stats_div,y=12,text="Antimatter",fg_bg=label_fg_bg}
        local am = DataIndicator{parent=stats_div,label="",format="%16d",value=0,unit="\xb5B/t",lu_colors=lu_col,width=21,fg_bg=text_fg}

        am.register(f_ps, "sps_process_rate", function (r) am.update(r * 1000) end)

        --#endregion

        --#region waste options page

        local o_pane = Div{parent=page_div}
        local o_div = Div{parent=o_pane,x=2,width=main.get_width()-2}
        table.insert(panes, o_pane)

        local opt_page = app.new_page(nil, #panes)
        opt_page.tasks = { update }

        TextBox{parent=o_div,y=1,text="Waste Options",alignment=ALIGN.CENTER}

        local pu_fallback = Checkbox{parent=o_div,x=2,y=3,label="Pu Fallback",callback=process.set_pu_fallback,box_fg_bg=cpair(colors.white,colors.gray)}

        TextBox{parent=o_div,x=2,y=5,height=3,text="Switch to Pu when SNAs cannot keep up with waste.",fg_bg=label_fg_bg}

        local lc_sps = Checkbox{parent=o_div,x=2,y=9,label="Low Charge SPS",callback=process.set_sps_low_power,box_fg_bg=cpair(colors.white,colors.gray)}

        TextBox{parent=o_div,x=2,y=11,height=3,text="Use SPS at low charge, otherwise switches to Po.",fg_bg=label_fg_bg}

        pu_fallback.register(f_ps, "process_pu_fallback", pu_fallback.set_value)
        lc_sps.register(f_ps, "process_sps_low_power", lc_sps.set_value)

        --#endregion

        --#region SPS page

        local s_pane = Div{parent=page_div}
        local s_div = Div{parent=s_pane,x=2,width=main.get_width()-2}
        table.insert(panes, s_pane)

        local sps_page = app.new_page(nil, #panes)
        sps_page.tasks = { update }

        TextBox{parent=s_div,y=1,text="Facility SPS",alignment=ALIGN.CENTER}

        local sps_status = StateIndicator{parent=s_div,x=5,y=3,states=style.sps.states,value=1,min_width=12}

        sps_status.register(db.facility.sps_ps_tbl[1], "SPSStateStatus", sps_status.update)

        TextBox{parent=s_div,y=5,text="Input Rate",width=10,fg_bg=label_fg_bg}
        local sps_in = DataIndicator{parent=s_div,label="",format="%16.2f",value=0,unit="mB/t",lu_colors=lu_col,width=21,fg_bg=text_fg}

        sps_in.register(f_ps, "po_am_rate", sps_in.update)

        TextBox{parent=s_div,y=8,text="Production Rate",width=15,fg_bg=label_fg_bg}
        local sps_rate = DataIndicator{parent=s_div,label="",format="%16d",value=0,unit="\xb5B/t",lu_colors=lu_col,width=21,fg_bg=text_fg}

        sps_rate.register(f_ps, "sps_process_rate", function (r) sps_rate.update(r * 1000) end)

        --#endregion

        -- setup multipane
        local w_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(w_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = "WST", color = core.cpair(colors.black, colors.brown), callback = wst_ctrl.nav_to },
            { label = "OPT", color = core.cpair(colors.black, colors.white), callback = opt_page.nav_to },
            { label = "SPS", color = core.cpair(colors.black, colors.purple), callback = sps_page.nav_to }
        }

        for i = 1, db.facility.num_units do
            table.insert(list, { label = "U-" .. i, color = core.cpair(colors.black, colors.lightGray), callback = u_pages[i].nav_to })
        end

        app.set_sidebar(list)

        -- done, show the app
        wst_ctrl.nav_to()
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
