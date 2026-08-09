--
-- About Page
--

local comms      = require("scada-common.comms")
local util       = require("scada-common.util")

local ioctl      = require("pocket.ioctl")
local pocket     = require("pocket.pocket")

local style      = require("pocket.ui.style")

local core       = require("graphics.core")

local Div        = require("graphics.elements.Div")
local ListBox    = require("graphics.elements.ListBox")
local MultiPane  = require("graphics.elements.MultiPane")
local TextBox    = require("graphics.elements.TextBox")

local WaitingAnim = require("graphics.elements.animations.Waiting")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")
local PushButton = require("graphics.elements.controls.PushButton")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

local label_fg_bg  = style.label
local lu_col       = style.label_unit_pair
local text_fg      = style.text_fg

-- create build page view
---@param root Container parent
local function new_view(root)
    local db = ioctl.get_db()

    local frame = Div{parent=root,y=1}

    local app = db.nav.register_app(APP_ID.BUILD, frame, nil, false, true)

    local load_div = Div{parent=frame,y=1}
    local main = Div{parent=frame,y=1}

    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.pink,colors._INHERIT)}

    local load_pane = MultiPane{parent=main,y=1,panes={load_div,main}}

    app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })

    local btn_fg_bg = cpair(colors.lightBlue, colors.black)
    local btn_active = cpair(colors.white, colors.black)

    local page_div = nil ---@type Div|nil

    -- load the app (create the elements)
    local function load()
        local fac  = db.facility
        local f_ps = fac.ps

        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {} ---@type Div[]

        -- refresh data callback, every 5s it will re-send the query
        local last_update = 0
        local function update()
            -- if util.time_ms() - last_update >= 5000 then
            --     db.api.get_fac()
            --     last_update = util.time_ms()
            -- end
        end

        local main_pane = Div{parent=page_div}
        local main_div = Div{parent=main_pane,x=2,width=main.get_width()-2}
        table.insert(panes, main_div)

        local main_page = app.new_page(nil, #panes)
        main_page.tasks = { update }

        TextBox{parent=main_div,y=1,text="Facility Construction",alignment=ALIGN.CENTER}
        TextBox{parent=main_div,y=3,text="Select a class of device from the left to view the build properties of those devices currently connected.",fg_bg=label_fg_bg}

        --#region reactors

        local rct_pane = Div{parent=page_div}
        local rct_div = Div{parent=rct_pane,x=2,width=main.get_width()-2}
        table.insert(panes, rct_div)

        local rct_page = app.new_page(nil, #panes)
        rct_page.tasks = { update }

        TextBox{parent=rct_div,y=1,height=2,text="Fission Reactors",alignment=ALIGN.CENTER}

        for i = 1, fac.num_units do
            local u_pane = Div{parent=page_div}
            local u_div = Div{parent=u_pane}
            table.insert(panes, u_div)

            local u_page = app.new_page(rct_page, #panes)
            u_page.tasks = { update }

            local u_ps = db.units[i].unit_ps

            PushButton{parent=rct_div,text="Unit "..i.." Reactor      >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=u_page.nav_to}

            TextBox{parent=u_div,y=1,text="Unit "..i.." Reactor",alignment=ALIGN.CENTER}

            local u_list_box = ListBox{parent=u_div,x=2,y=3,scroll_height=40,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
            local u_list = Div{parent=u_list_box,y=2,width=main.get_width()-2,height=39}

            TextBox{parent=u_list,text="Maximum Burn Rate",fg_bg=label_fg_bg}
            local max_burn = DataIndicator{parent=u_list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
            max_burn.register(u_ps, "max_burn", max_burn.update)

            u_list.line_break()
            TextBox{parent=u_list,text="Fuel Assemblies",fg_bg=label_fg_bg}
            local fuel_asm = DataIndicator{parent=u_list,lu_colors=lu_col,label="",format="%d",value=0,width=20,fg_bg=text_fg}
            fuel_asm.register(u_ps, "fuel_asm", fuel_asm.update)

            u_list.line_break()
            TextBox{parent=u_list,text="Fuel Surface Area",fg_bg=label_fg_bg}
            local fuel_sa = DataIndicator{parent=u_list,lu_colors=lu_col,label="",unit="m\xb2",format="%d",value=0,width=20,fg_bg=text_fg}
            fuel_sa.register(u_ps, "fuel_sa", fuel_sa.update)

            u_list.line_break()
            TextBox{parent=u_list,text="Fuel Capacity",fg_bg=label_fg_bg}
            local fuel_cap = DataIndicator{parent=u_list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            fuel_cap.register(u_ps, "fuel_cap", fuel_cap.update)

            u_list.line_break()
            TextBox{parent=u_list,text="Waste Capacity",fg_bg=label_fg_bg}
            local waste_cap = DataIndicator{parent=u_list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            waste_cap.register(u_ps, "waste_cap", waste_cap.update)

            u_list.line_break()
            TextBox{parent=u_list,text="Cooled Coolant Cap.",fg_bg=label_fg_bg}
            local cool_cap = DataIndicator{parent=u_list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            cool_cap.register(u_ps, "cool_cap", cool_cap.update)

            u_list.line_break()
            TextBox{parent=u_list,text="Heated Coolant Cap.",fg_bg=label_fg_bg}
            local hcool_cap = DataIndicator{parent=u_list,lu_colors=lu_col,label="",unit="mB",format="%d",value=0,width=20,fg_bg=text_fg}
            hcool_cap.register(u_ps, "hcool_cap", hcool_cap.update)

            u_list.line_break()
            TextBox{parent=u_list,text="Heat Capacity",fg_bg=label_fg_bg}
            local heat_cap = DataIndicator{parent=u_list,lu_colors=lu_col,label="",unit="J",format="%d",value=0,width=20,fg_bg=text_fg}
            heat_cap.register(u_ps, "heat_cap", heat_cap.update)

            u_list.line_break()
            TextBox{parent=u_list,text="Dimensions",fg_bg=label_fg_bg}
            local l = DataIndicator{parent=u_list,lu_colors=lu_col,label="Length:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local w = DataIndicator{parent=u_list,lu_colors=lu_col,label="Width: ",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local h = DataIndicator{parent=u_list,lu_colors=lu_col,label="Height:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            l.register(u_ps, "length", l.update)
            w.register(u_ps, "width", w.update)
            h.register(u_ps, "height", h.update)

            u_list.line_break()
            TextBox{parent=u_list,text="Minimum Position",fg_bg=label_fg_bg}
            local x1 = DataIndicator{parent=u_list,lu_colors=lu_col,label="X:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local y1 = DataIndicator{parent=u_list,lu_colors=lu_col,label="Y:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local z1 = DataIndicator{parent=u_list,lu_colors=lu_col,label="Z:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            x1.register(u_ps, "min_pos", function (crd)
                x1.update(crd.x); y1.update(crd.y); z1.update(crd.z)
            end)

            u_list.line_break()
            TextBox{parent=u_list,text="Maximum Position",fg_bg=label_fg_bg}
            local x2 = DataIndicator{parent=u_list,lu_colors=lu_col,label="X:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local y2 = DataIndicator{parent=u_list,lu_colors=lu_col,label="Y:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            local z2 = DataIndicator{parent=u_list,lu_colors=lu_col,label="Z:",format="%d",value=0,commas=true,width=13,fg_bg=text_fg}
            x2.register(u_ps, "min_pos", function (crd)
                x2.update(crd.x); y2.update(crd.y); z2.update(crd.z)
            end)
        end

        --#endregion

        local blr_page = app.new_page(nil, 3)
        local trb_page = app.new_page(nil, 4)
        local tnk_page = app.new_page(nil, 5)
        local sps_page = app.new_page(nil, 6)
        local ess_page = app.new_page(nil, 7)

        -- setup multipane
        local f_pane = MultiPane{parent=page_div,y=1,panes=panes}
        app.set_root_pane(f_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = " \x08 ", color = core.cpair(colors.black, colors.lightGray), callback = main_page.nav_to },
            { label = "RCT", color = core.cpair(colors.black, colors.cyan), callback = rct_page.nav_to },
            { label = "BLR", color = core.cpair(colors.black, colors.orange), callback = blr_page.nav_to },
            { label = "TRB", color = core.cpair(colors.black, colors.white), callback = trb_page.nav_to },
            { label = "TNK", color = core.cpair(colors.black, colors.blue), callback = tnk_page.nav_to },
            { label = "SPS", color = core.cpair(colors.black, colors.purple), callback = sps_page.nav_to },
            { label = "ESS", color = core.cpair(colors.black, colors.green), callback = ess_page.nav_to }
        }

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
