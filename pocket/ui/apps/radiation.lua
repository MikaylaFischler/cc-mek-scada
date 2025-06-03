--
-- Radiation Monitor App
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

local HazardButton  = require("graphics.elements.controls.HazardButton")
local RadioButton   = require("graphics.elements.controls.RadioButton")

local NumberField   = require("graphics.elements.form.NumberField")

local IconIndicator = require("graphics.elements.indicators.IconIndicator")

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

-- new radiation monitor page view
---@param root Container parent
local function new_view(root)
    local db = iocontrol.get_db()

    local frame = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(APP_ID.RADMON, frame, nil, false, true)

    local load_div = Div{parent=frame,x=1,y=1}
    local main = Div{parent=frame,x=1,y=1}

    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.yellow,colors._INHERIT)}

    local load_pane = MultiPane{parent=main,x=1,y=1,panes={load_div,main}}

    app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })

    local page_div = nil ---@type Div|nil

    -- load the app (create the elements)
    local function load()
        local f_ps = db.facility.ps

        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {} ---@type Div[]

        -- create all page divs
        for _ = 1, db.facility.num_units + 2 do
            local div = Div{parent=page_div}
            table.insert(panes, div)
        end

        local last_update = 0
        -- refresh data callback, every 500ms it will re-send the query
        local function update()
            if util.time_ms() - last_update >= 500 then
                db.api.get_rad()
                last_update = util.time_ms()
            end
        end

        --#region unit radiation monitors

        for i = 1, db.facility.num_units do
            local u_pane = panes[i]
            local u_div = Div{parent=u_pane,x=2,width=main.get_width()-2}
            local unit = db.units[i]
            local u_ps = unit.unit_ps

            local u_page = app.new_page(nil, i)
            u_page.tasks = { update }

            TextBox{parent=u_div,y=1,text="Unit #"..i.." Monitors",alignment=ALIGN.CENTER}

            -- TextBox{parent=u_div,y=3,text="Auto Rate Limit",fg_bg=label_fg_bg}
            -- rate_limits[i] = NumberField{parent=u_div,x=1,y=4,width=16,default=0.01,min=0.01,max_frac_digits=2,max_chars=8,allow_decimal=true,align_right=true,fg_bg=field_fg_bg,dis_fg_bg=field_dis_fg_bg}
            -- TextBox{parent=u_div,x=18,y=4,text="mB/t",width=4,fg_bg=label_fg_bg}

            -- rate_limits[i].register(unit.unit_ps, "max_burn", rate_limits[i].set_max)
            -- rate_limits[i].register(unit.unit_ps, "burn_limit", rate_limits[i].set_value)

            -- local ready    = IconIndicator{parent=u_div,y=6,label="Auto Ready",states=grn_ind_s}
            -- local a_stb    = IconIndicator{parent=u_div,label="Auto Standby",states=wht_ind_s}
            -- local degraded = IconIndicator{parent=u_div,label="Unit Degraded",states=red_ind_s}

            -- ready.register(u_ps, "U_AutoReady", ready.update)
            -- degraded.register(u_ps, "U_AutoDegraded", degraded.update)

            -- -- update standby indicator
            -- a_stb.register(u_ps, "status", function (active)
            --     a_stb.update(unit.annunciator.AutoControl and (not active))
            -- end)
            -- a_stb.register(u_ps, "AutoControl", function (auto_active)
            --     if auto_active then
            --         a_stb.update(unit.reactor_data.mek_status.status == false)
            --     else a_stb.update(false) end
            -- end)

            -- local function _set_group(value) process.set_group(i, value - 1) end

            -- local group = RadioButton{parent=u_div,y=10,options=types.AUTO_GROUP_NAMES,callback=_set_group,radio_colors=cpair(colors.lightGray,colors.gray),select_color=colors.purple,dis_fg_bg=style.btn_disable}

            -- -- can't change group if auto is engaged regardless of if this unit is part of auto control
            -- group.register(f_ps, "auto_active", function (auto_active)
            --     if auto_active then group.disable() else group.enable() end
            -- end)

            -- group.register(u_ps, "auto_group_id", function (gid) group.set_value(gid + 1) end)

            -- TextBox{parent=u_div,y=16,text="Assigned Group",fg_bg=style.label}
            -- local auto_grp = TextBox{parent=u_div,text="Manual",width=11,fg_bg=text_fg}

            -- auto_grp.register(u_ps, "auto_group", auto_grp.set_value)

            util.nop()
        end

        --#endregion

        --#region overview page

        local s_pane = panes[db.facility.num_units + 1]
        local s_div = Div{parent=s_pane,x=2,width=main.get_width()-2}

        local stat_page = app.new_page(nil, db.facility.num_units + 1)
        stat_page.tasks = { update }

        TextBox{parent=s_div,y=1,text="Radiation Monitors",alignment=ALIGN.CENTER}

        --#endregion

        --#region overview page

        local f_pane = panes[db.facility.num_units + 2]
        local f_div = Div{parent=f_pane,x=2,width=main.get_width()-2}

        local fac_page = app.new_page(nil, db.facility.num_units + 2)
        fac_page.tasks = { update }

        TextBox{parent=f_div,y=1,text="Facility Monitors",alignment=ALIGN.CENTER}

        --#endregion

        -- setup multipane
        local u_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(u_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = " \x1e ", color = core.cpair(colors.black, colors.blue), callback = stat_page.nav_to },
            { label = "FAC", color = core.cpair(colors.black, colors.yellow), callback = fac_page.nav_to }
        }

        for i = 1, db.facility.num_units do
            table.insert(list, { label = "U-" .. i, color = core.cpair(colors.black, colors.lightGray), callback = function () app.switcher(i) end })
        end

        app.set_sidebar(list)

        -- done, show the app
        stat_page.nav_to()
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
