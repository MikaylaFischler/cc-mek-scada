--
-- Computer List App
--

local comms        = require("scada-common.comms")
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

local DEV_TYPE = comms.DEVICE_TYPE

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
        for _ = 1, 4 do
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

        -- create indicators for the ID, firmware, and RTT
        ---@param pfx string
        ---@param rect Rectangle
        local function create_common_indicators(pfx, rect)
            TextBox{parent=rect,text="Computer ID",fg_bg=label_fg_bg}
            TextBox{parent=rect,text="Firmware",fg_bg=label_fg_bg}
            TextBox{parent=rect,text="Round-Trip Time",fg_bg=label_fg_bg}
            local addr = TextBox{parent=rect,x=13,y=2,text="---"}
            local fw = TextBox{parent=rect,x=13,y=3,text="---"}
            local rtt = TextBox{parent=rect,x=13,y=3,text="---"}

            addr.register(f_ps, pfx .. "_addr", addr.set_value)
            fw.register(f_ps, pfx .. "_fw", fw.set_value)

            rtt.register(f_ps, pfx.. "_rtt", function (value)
                rtt.set_value(rtt)

                if value > HIGH_RTT then
                    rtt.recolor(colors.red)
                elseif value > WARN_RTT then
                    rtt.recolor(colors.yellow)
                else
                    rtt.recolor(colors.green)
                end
            end)
        end

        --#region main computer page

        local m_div = Div{parent=panes[1],x=2,width=main.get_width()-2}

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
        local crd_online = TextBox{parent=crd_rect,x=12,y=1,width=7,text="Online",fg_bg=cpair(colors.green,colors._INHERIT)}

        create_common_indicators("comp_crd", crd_rect)

        crd_online.register(f_ps, "comp_crd_online", function (online)
            if online then
                crd_online.set_value("Online")
                crd_online.recolor(colors.green)
            else
                crd_online.set_value("Off-line")
                crd_online.recolor(colors.red)
            end
        end)

        --#endregion

        --#region PLC page

        local p_div = Div{parent=panes[2],width=main.get_width()}

        local plc_page = app.new_page(nil, 2)
        plc_page.tasks = { update }

        TextBox{parent=p_div,y=1,text="PLC Devices",alignment=ALIGN.CENTER}

        local plc_list = ListBox{parent=p_div,y=6,scroll_height=100,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
        local plc_elems = {}    ---@type graphics_element[]

        --#endregion

        --#region RTU page

        local r_div = Div{parent=panes[2],width=main.get_width()}

        local rtu_page = app.new_page(nil, 3)
        rtu_page.tasks = { update }

        TextBox{parent=r_div,y=1,text="RTU Gateway Devices",alignment=ALIGN.CENTER}

        local rtu_list = ListBox{parent=p_div,y=6,scroll_height=100,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
        local rtu_elems = {}    ---@type graphics_element[]

        --#endregion

        --#region RTU page

        local pk_div = Div{parent=panes[2],width=main.get_width()}

        local pkt_page = app.new_page(nil, 4)
        pkt_page.tasks = { update }

        TextBox{parent=pk_div,y=1,text="Pocket Devices",alignment=ALIGN.CENTER}

        local pkt_list = ListBox{parent=p_div,y=6,scroll_height=100,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
        local pkt_elems = {}    ---@type graphics_element[]

        --#endregion

        --#region connect/disconnect management

        f_ps.subscribe("comp_connect", function (id)
            local pfx  = "comp_" .. id
            local type = f_ps.get(pfx .. "_type")

            if type == DEV_TYPE.PLC then
                plc_elems[id] = Div{parent=plc_list,height=5}
                local rect = Rectangle{parent=plc_elems[id],height=6,x=2,width=20,border=border(1,colors.gray,true),thin=true,fg_bg=cpair(colors.black,colors.lightGray)}

                local title = TextBox{parent=rect,text="PLC (Unit ?) @ "..id}
                title.register(f_ps, pfx .. "_unit", function (unit) title.set_value("PLC (Unit " .. unit .. ") @ " .. id) end)

                create_common_indicators(pfx, rect)
            elseif type == DEV_TYPE.RTU then
                rtu_elems[id] = Div{parent=rtu_list,height=5}
                local rect = Rectangle{parent=rtu_elems[id],height=6,x=2,width=20,border=border(1,colors.gray,true),thin=true,fg_bg=cpair(colors.black,colors.lightGray)}

                TextBox{parent=rect,text="RTU Gateway @ "..id}

                create_common_indicators(pfx, rect)
            elseif type == DEV_TYPE.PKT then
                pkt_elems[id] = Div{parent=pkt_list,height=5}
                local rect = Rectangle{parent=pkt_elems[id],height=6,x=2,width=20,border=border(1,colors.gray,true),thin=true,fg_bg=cpair(colors.black,colors.lightGray)}

                TextBox{parent=rect,text="Pocket @ "..id}

                create_common_indicators(pfx, rect)
            end
        end)

        f_ps.subscribe("comp_disconnect", function (id)
            local type = f_ps.get("comp_" ..id .. "_type")

            if type == DEV_TYPE.PLC then
                if plc_elems[id] then plc_elems[id].delete() end
                plc_elems[id] = nil
            elseif type == DEV_TYPE.RTU then
                if rtu_elems[id] then rtu_elems[id].delete() end
                rtu_elems[id] = nil
            elseif type == DEV_TYPE.PKT then
                if pkt_elems[id] then pkt_elems[id].delete() end
                pkt_elems[id] = nil
            end
        end)

        --#endregion

        -- setup multipane
        local u_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(u_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = " \x1e ", color = core.cpair(colors.black, colors.blue), callback = main_page.nav_to },
            { label = "PLC", color = core.cpair(colors.black, colors.red), callback = plc_page.nav_to },
            { label = "RTU", color = core.cpair(colors.black, colors.orange), callback = rtu_page.nav_to },
            { label = "PKT", color = core.cpair(colors.black, colors.gray), callback = pkt_page.nav_to }
        }

        app.set_sidebar(list)

        -- done, show the app
        main_page.nav_to()
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
