--
-- Computer List App
--

local util         = require("scada-common.util")

local iocontrol    = require("pocket.iocontrol")
local pocket       = require("pocket.pocket")

local style        = require("pocket.ui.style")

local core         = require("graphics.core")

local Div          = require("graphics.elements.Div")
local ListBox      = require("graphics.elements.ListBox")
local MultiPane    = require("graphics.elements.MultiPane")
local Rectangle    = require("graphics.elements.Rectangle")
local TextBox      = require("graphics.elements.TextBox")

local WaitingAnim  = require("graphics.elements.animations.Waiting")

local RadIndicator = require("graphics.elements.indicators.RadIndicator")

local ALIGN  = core.ALIGN
local cpair  = core.cpair
local border = core.border

local APP_ID = pocket.APP_ID

local label_fg_bg = style.label
local lu_col      = style.label_unit_pair

-- new computer list page view
---@param root Container parent
local function new_view(root)
    local db = iocontrol.get_db()

    local frame = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(APP_ID.COMPS, frame, nil, true, false)

    local load_div = Div{parent=frame,x=1,y=1}
    local main = Div{parent=frame,x=1,y=1}

    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.orange,colors._INHERIT)}

    local load_pane = MultiPane{parent=main,x=1,y=1,panes={load_div,main}}

    app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })

    local page_div = nil ---@type Div|nil

    -- load the app (create the elements)
    local function load()
        local f_ps = db.facility.ps

        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {} ---@type Div[]

        -- create all page divs
        for _ = 1, 3 do
            local div = Div{parent=page_div}
            table.insert(panes, div)
        end

        local last_update = 0
        -- refresh data callback, every 500ms it will re-send the query
        local function update()
            if util.time_ms() - last_update >= 500 then
                db.diag.get_comps()
                last_update = util.time_ms()
            end
        end

        -- create a new radiation monitor list
        ---@param parent Container
        ---@param ps psil
        local function new_mon_list(parent, ps)
            local mon_list = ListBox{parent=parent,y=6,scroll_height=100,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}

            local elem_list = {}    ---@type graphics_element[]

            mon_list.register(ps, "radiation_monitors", function (data)
                local ids = textutils.unserialize(data)

                -- delete any disconnected monitors
                for id, elem in pairs(elem_list) do
                    if not util.table_contains(ids, id) then
                        elem.delete()
                        elem_list[id] = nil
                    end
                end

                -- add newly connected monitors
                for _, id in pairs(ids) do
                    if not elem_list[id] then
                        elem_list[id] = Div{parent=mon_list,height=5}
                        local mon_rect = Rectangle{parent=elem_list[id],height=4,x=2,width=20,border=border(1,colors.gray,true),thin=true,fg_bg=cpair(colors.black,colors.lightGray)}

                        TextBox{parent=mon_rect,text="Env. Detector "..id}
                        local mon_rad = RadIndicator{parent=mon_rect,x=2,label="",format="%13.3f",lu_colors=cpair(colors.gray,colors.gray),width=18}
                        mon_rad.register(ps, "radiation@" .. id, mon_rad.update)
                    end
                end
            end)
        end

        --#region overview page

        local m_pane = panes[1]
        local m_div = Div{parent=m_pane,x=2,width=main.get_width()-2}

        local main_page = app.new_page(nil, 1)
        main_page.tasks = { update }

        TextBox{parent=m_div,y=1,text="Connected Computers",alignment=ALIGN.CENTER}

        TextBox{parent=m_div,y=3,text="Networked Computers",fg_bg=label_fg_bg}
        local s_f_rad = RadIndicator{parent=m_div,label="",format="%17.3f",lu_colors=lu_col,width=21}
        s_f_rad.register(f_ps, "radiation", s_f_rad.update)

        --#endregion

        --#region overview page

        local f_pane = panes[db.facility.num_units + 2]
        local f_div = Div{parent=f_pane,width=main.get_width()}

        local fac_page = app.new_page(nil, db.facility.num_units + 2)
        fac_page.tasks = { update }

        TextBox{parent=f_div,y=1,text="Facility Monitors",alignment=ALIGN.CENTER}

        TextBox{parent=f_div,x=2,y=3,text="Max Radiation",fg_bg=label_fg_bg}
        local f_rad = RadIndicator{parent=f_div,x=2,label="",format="%17.3f",lu_colors=lu_col,width=21}
        f_rad.register(f_ps, "radiation", f_rad.update)

        new_mon_list(f_div, f_ps)

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
