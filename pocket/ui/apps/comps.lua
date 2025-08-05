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

local DataIndicator = require("graphics.elements.indicators.DataIndicator")

local ALIGN  = core.ALIGN
local cpair  = core.cpair
local border = core.border

local APP_ID = pocket.APP_ID

local label_fg_bg = style.label
local lu_col      = style.label_unit_pair

-- nominal RTT is ping (0ms to 10ms usually) + 150ms for SV main loop tick
-- ensure in sync with supervisor databus file
local WARN_RTT = 300    -- 2x as long as expected w/ 0 ping
local HIGH_RTT = 500    -- 3.33x as long as expected w/ 0 ping

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

        --#region main computer page

        local m_pane = panes[1]
        local m_div = Div{parent=m_pane,x=2,width=main.get_width()-2}

        local main_page = app.new_page(nil, 1)
        main_page.tasks = { update }

        TextBox{parent=m_div,y=1,text="Connected Computers",alignment=ALIGN.CENTER}

        local conns = DataIndicator{parent=m_div,x=10,y=3,lu_colors=lu_col,label="Online",unit="",format="%3d",value=0,commas=true,width=21}
        conns.register(f_ps, "comp_online", conns.update)

        local svr_div = Div{parent=m_div,y=5,height=5}
        local svr_rect = Rectangle{parent=svr_div,height=5,x=2,width=21,border=border(1,colors.gray,true),thin=true,fg_bg=cpair(colors.black,colors.lightGray)}

        TextBox{parent=svr_rect,text="Supervisor"}
        TextBox{parent=svr_rect,x=12,y=1,width=6,text="Online",fg_bg=cpair(colors.green,colors._INHERIT)}
        TextBox{parent=svr_rect,text="Computer ID",fg_bg=label_fg_bg}
        TextBox{parent=svr_rect,text="Firmware",fg_bg=label_fg_bg}
        local svr_addr = TextBox{parent=svr_rect,x=13,y=2,text="---"}
        local svr_fw = TextBox{parent=svr_rect,x=13,y=3,text="---"}

        svr_addr.register(f_ps, "comp_svr_addr", svr_addr.set_value)
        svr_fw.register(f_ps, "comp_svr_fw", svr_fw.set_value)

        local crd_div = Div{parent=m_div,y=5,height=5}
        local crd_rect = Rectangle{parent=crd_div,height=6,x=2,width=21,border=border(1,colors.gray,true),thin=true,fg_bg=cpair(colors.black,colors.lightGray)}

        TextBox{parent=crd_rect,text="Coordinator"}
        local crd_online = TextBox{parent=svr_rect,x=12,y=1,width=7,text="Online",fg_bg=cpair(colors.green,colors._INHERIT)}
        TextBox{parent=crd_rect,text="Computer ID",fg_bg=label_fg_bg}
        TextBox{parent=crd_rect,text="Firmware",fg_bg=label_fg_bg}
        TextBox{parent=crd_rect,text="Round-Trip Time",fg_bg=label_fg_bg}
        local crd_addr = TextBox{parent=svr_rect,x=13,y=2,text="---"}
        local crd_fw = TextBox{parent=svr_rect,x=13,y=3,text="---"}
        local crd_rtt = TextBox{parent=svr_rect,x=13,y=3,text="---"}

        crd_addr.register(f_ps, "comp_crd_addr", crd_addr.set_value)
        crd_fw.register(f_ps, "comp_crd_fw", crd_fw.set_value)

        crd_online.register(f_ps, "comp_crd_online", function (online)
            if online then
                crd_online.set_value("Online")
                crd_online.recolor(colors.green)
            else
                crd_online.set_value("Off-line")
                crd_online.recolor(colors.red)
            end
        end)

        crd_rtt.register(f_ps, "comp_crd_rtt", function (rtt)
            crd_rtt.set_value(rtt)

            if type(rtt) ~= "number" then
                crd_rtt.recolor(label_fg_bg.fgd)
            else
                if rtt > HIGH_RTT then
                    crd_rtt.recolor(colors.red)
                elseif rtt > WARN_RTT then
                    crd_rtt.recolor(colors.yellow)
                else
                    crd_rtt.recolor(colors.green)
                end
            end
        end)

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
