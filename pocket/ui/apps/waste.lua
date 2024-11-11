--
-- Waste Control Page
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
local Rectangle     = require("graphics.elements.Rectangle")
local TextBox       = require("graphics.elements.TextBox")

local WaitingAnim   = require("graphics.elements.animations.Waiting")

local Checkbox      = require("graphics.elements.controls.Checkbox")
local HazardButton  = require("graphics.elements.controls.HazardButton")
local RadioButton   = require("graphics.elements.controls.RadioButton")

local NumberField   = require("graphics.elements.form.NumberField")

local IconIndicator = require("graphics.elements.indicators.IconIndicator")
local StateIndicator = require("graphics.elements.indicators.StateIndicator")

local ALIGN  = core.ALIGN
local cpair  = core.cpair
local border = core.border

local APP_ID = pocket.APP_ID

local label_fg_bg     = style.label
local text_fg         = style.text_fg

local field_fg_bg     = style.field
local field_dis_fg_bg = style.field_disable

local red_ind_s       = style.icon_states.red_ind_s
local yel_ind_s       = style.icon_states.yel_ind_s
local grn_ind_s       = style.icon_states.grn_ind_s
local wht_ind_s       = style.icon_states.wht_ind_s

local hzd_fg_bg       = style.hzd_fg_bg
local dis_colors      = cpair(colors.white, colors.lightGray)

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

        local panes = {} ---@type Div[]

        -- create all page divs
        for _ = 1, db.facility.num_units + 3 do
            local div = Div{parent=page_div}
            table.insert(panes, div)
        end

        local last_update = 0
        -- refresh data callback, every 500ms it will re-send the query
        local function update()
            if util.time_ms() - last_update >= 500 then
                -- db.api.get_waste()
                last_update = util.time_ms()
            end
        end

        --#region unit settings/status

        for i = 1, db.facility.num_units do
            local u_pane = panes[i]
            local u_div = Div{parent=u_pane,x=2,width=main.get_width()-2}
            local unit = db.units[i]
            local u_ps = unit.unit_ps

            local u_page = app.new_page(nil, i)
            u_page.tasks = { update }

            TextBox{parent=u_div,y=1,text="Reactor Unit #"..i,alignment=ALIGN.CENTER}
        end

        --#endregion

        --#region waste options page

        local o_pane = panes[db.facility.num_units + 2]
        local o_div = Div{parent=o_pane,x=2,width=main.get_width()-2}

        local opt_page = app.new_page(nil, db.facility.num_units + 2)
        opt_page.tasks = { update }

        TextBox{parent=o_div,y=1,text="Waste Options",alignment=ALIGN.CENTER}

        local pu_fallback = Checkbox{parent=o_div,x=2,y=3,label="Pu Fallback",callback=function()end,box_fg_bg=cpair(colors.white,colors.gray)}

        TextBox{parent=o_div,x=2,y=5,height=3,text="Switch to Pu when SNAs cannot keep up with waste.",fg_bg=style.label}

        local lc_sps = Checkbox{parent=o_div,x=2,y=9,label="Low Charge SPS",callback=function()end,box_fg_bg=cpair(colors.white,colors.gray)}

        TextBox{parent=o_div,x=2,y=11,height=3,text="Use SPS at low charge, otherwise switches to Po.",fg_bg=style.label}

        pu_fallback.register(f_ps, "process_pu_fallback", pu_fallback.set_value)
        lc_sps.register(f_ps, "process_sps_low_power", lc_sps.set_value)

        --#endregion

        --#region process control page

        local c_pane = panes[db.facility.num_units + 1]
        local c_div = Div{parent=c_pane,x=2,width=main.get_width()-2}

        local wst_ctrl = app.new_page(nil, db.facility.num_units + 1)
        wst_ctrl.tasks = { update }

        TextBox{parent=c_div,y=1,text="Waste Control",alignment=ALIGN.CENTER}

        local status = StateIndicator{parent=c_div,x=3,y=3,states=style.waste.states,value=1,min_width=17}

        status.register(f_ps, "current_waste_product", status.update)

        local waste_prod = RadioButton{parent=c_div,x=2,y=5,options=style.waste.options,callback=function()end,radio_colors=cpair(colors.white,colors.black),select_color=colors.brown}

        waste_prod.register(f_ps, "process_waste_product", waste_prod.set_value)

        local fb_active    = IconIndicator{parent=c_div,x=2,y=9,label="Fallback Active",states=wht_ind_s}
        local sps_disabled = IconIndicator{parent=c_div,x=2,y=10,label="SPS Disabled LC",states=yel_ind_s}

        fb_active.register(f_ps, "pu_fallback_active", fb_active.update)
        sps_disabled.register(f_ps, "sps_disabled_low_power", sps_disabled.update)

        --#endregion

        --#region auto-SCRAM annunciator page

        local a_pane = panes[db.facility.num_units + 3]
        local a_div = Div{parent=a_pane,x=2,width=main.get_width()-2}

        local annunc_page = app.new_page(nil, db.facility.num_units + 3)
        annunc_page.tasks = { update }

        TextBox{parent=a_div,y=1,text="Automatic SCRAM",alignment=ALIGN.CENTER}

        --#endregion

        -- setup multipane
        local u_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(u_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = "WST", color = core.cpair(colors.black, colors.brown), callback = wst_ctrl.nav_to },
            { label = "OPT", color = core.cpair(colors.black, colors.white), callback = opt_page.nav_to },
            { label = "SPS", color = core.cpair(colors.black, colors.purple), callback = annunc_page.nav_to }
        }

        for i = 1, db.facility.num_units do
            table.insert(list, { label = "U-" .. i, color = core.cpair(colors.black, colors.lightGray), callback = function () app.switcher(i) end })
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
