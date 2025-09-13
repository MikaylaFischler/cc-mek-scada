--
-- Computer List App
--

local comms         = require("scada-common.comms")
local const         = require("scada-common.constants")
local util          = require("scada-common.util")

local iocontrol     = require("pocket.iocontrol")
local pocket        = require("pocket.pocket")

local style         = require("pocket.ui.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local ListBox       = require("graphics.elements.ListBox")
local MultiPane     = require("graphics.elements.MultiPane")
local Rectangle     = require("graphics.elements.Rectangle")
local TextBox       = require("graphics.elements.TextBox")

local WaitingAnim   = require("graphics.elements.animations.Waiting")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")

local DEV_TYPE = comms.DEVICE_TYPE

local ALIGN  = core.ALIGN
local cpair  = core.cpair
local border = core.border

local APP_ID = pocket.APP_ID

local lu_col    = style.label_unit_pair
local box_label = cpair(colors.lightGray, colors.gray)

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
        local ps = db.ps

        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {} ---@type Div[]

        -- create all page divs
        for _ = 1, 4 do
            local div = Div{parent=page_div}
            table.insert(panes, div)
        end

        local last_update = 0
        -- refresh data callback, every 1s it will re-send the query
        local function update()
            if util.time_ms() - last_update >= 1000 then
                db.diag.get_comps()
                last_update = util.time_ms()
            end
        end

        -- create indicators for the ID, firmware, and RTT
        ---@param pfx string
        ---@param rect Rectangle
        local function create_common_indicators(pfx, rect)
            local first = TextBox{parent=rect,text="Computer",fg_bg=box_label}
            TextBox{parent=rect,text="Firmware",fg_bg=box_label}
            TextBox{parent=rect,text="RTT (ms)",fg_bg=box_label}

            local y = first.get_y()
            local addr = TextBox{parent=rect,x=10,y=y,text="---"}
            local fw = TextBox{parent=rect,x=10,y=y+1,text="---"}
            local rtt = TextBox{parent=rect,x=10,y=y+2,text="---"}

            addr.register(ps, pfx .. "_addr", function (v) addr.set_value(util.strval(v)) end)
            fw.register(ps, pfx .. "_fw", function (v) fw.set_value(util.strval(v)) end)

            rtt.register(ps, pfx .. "_rtt", function (value)
                rtt.set_value(util.strval(value))

                if value == "---" then
                    rtt.recolor(colors.white)
                elseif value > const.HIGH_RTT then
                    rtt.recolor(colors.red)
                elseif value > const.WARN_RTT then
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

        local conns = DataIndicator{parent=m_div,y=3,lu_colors=lu_col,label="Total Online",unit="",format="%8d",value=0,commas=true,width=21}
        conns.register(ps, "comp_online", conns.update)

        local svr_div = Div{parent=m_div,y=4,height=6}
        local svr_rect = Rectangle{parent=svr_div,height=6,width=22,border=border(1,colors.white,true),thin=true,fg_bg=cpair(colors.white,colors.gray)}

        TextBox{parent=svr_rect,text="Supervisor"}
        TextBox{parent=svr_rect,text="Status",fg_bg=box_label}
        TextBox{parent=svr_rect,x=10,y=2,text="Online",fg_bg=cpair(colors.green,colors._INHERIT)}
        TextBox{parent=svr_rect,text="Computer",fg_bg=box_label}
        TextBox{parent=svr_rect,text="Firmware",fg_bg=box_label}
        local svr_addr = TextBox{parent=svr_rect,x=10,y=3,text="?"}
        local svr_fw = TextBox{parent=svr_rect,x=10,y=4,text="?"}

        svr_addr.register(ps, "comp_svr_addr", function (v) svr_addr.set_value(util.strval(v)) end)
        svr_fw.register(ps, "comp_svr_fw", function (v) svr_fw.set_value(util.strval(v)) end)

        local crd_div = Div{parent=m_div,y=11,height=7}
        local crd_rect = Rectangle{parent=crd_div,height=7,width=21,border=border(1,colors.white,true),thin=true,fg_bg=cpair(colors.white,colors.gray)}

        TextBox{parent=crd_rect,text="Coordinator"}
        TextBox{parent=crd_rect,text="Status",fg_bg=box_label}
        local crd_online = TextBox{parent=crd_rect,x=10,y=2,width=8,text="Off-line",fg_bg=cpair(colors.red,colors._INHERIT)}

        create_common_indicators("comp_crd", crd_rect)

        crd_online.register(ps, "comp_crd_online", function (online)
            if online then
                crd_online.recolor(colors.green)
                crd_online.set_value("Online")
            else
                crd_online.recolor(colors.red)
                crd_online.set_value("Off-line")
            end
        end)

        --#endregion

        --#region PLC page

        local p_div = Div{parent=panes[2],width=main.get_width()}

        local plc_page = app.new_page(nil, 2)
        plc_page.tasks = { update }

        TextBox{parent=p_div,y=1,text="PLC Devices",alignment=ALIGN.CENTER}

        local plc_list = ListBox{parent=p_div,y=3,scroll_height=100,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
        local plc_elems = {}    ---@type graphics_element[]

        --#endregion

        --#region RTU gateway page

        local r_div = Div{parent=panes[3],width=main.get_width()}

        local rtu_page = app.new_page(nil, 3)
        rtu_page.tasks = { update }

        TextBox{parent=r_div,y=1,text="RTU Gateway Devices",alignment=ALIGN.CENTER}

        local rtu_list = ListBox{parent=r_div,y=3,scroll_height=100,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
        local rtu_elems = {}    ---@type graphics_element[]

        --#endregion

        --#region pocket computer page

        local pk_div = Div{parent=panes[4],width=main.get_width()}

        local pkt_page = app.new_page(nil, 4)
        pkt_page.tasks = { update }

        TextBox{parent=pk_div,y=1,text="Pocket Devices",alignment=ALIGN.CENTER}

        local pkt_list = ListBox{parent=pk_div,y=3,scroll_height=100,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
        local pkt_elems = {}    ---@type graphics_element[]

        --#endregion

        --#region connect/disconnect management

        ps.subscribe("comp_connect", function (id)
            if id == false then return end

            local pfx  = "comp_" .. id
            local type = ps.get(pfx .. "_type")

            if type == DEV_TYPE.PLC then
                plc_elems[id] = Div{parent=plc_list,height=7}
                local rect = Rectangle{parent=plc_elems[id],height=6,x=2,width=20,border=border(1,colors.white,true),thin=true,fg_bg=cpair(colors.white,colors.gray)}

                local title = TextBox{parent=rect,text="PLC (Unit ?)"}
                title.register(ps, pfx .. "_unit", function (unit) title.set_value("PLC (Unit " .. unit .. ")") end)

                create_common_indicators(pfx, rect)
            elseif type == DEV_TYPE.RTU then
                rtu_elems[id] = Div{parent=rtu_list,height=7}
                local rect = Rectangle{parent=rtu_elems[id],height=6,x=2,width=20,border=border(1,colors.white,true),thin=true,fg_bg=cpair(colors.white,colors.gray)}

                TextBox{parent=rect,text="RTU Gateway"}

                create_common_indicators(pfx, rect)
            elseif type == DEV_TYPE.PKT then
                pkt_elems[id] = Div{parent=pkt_list,height=7}
                local rect = Rectangle{parent=pkt_elems[id],height=6,x=2,width=20,border=border(1,colors.white,true),thin=true,fg_bg=cpair(colors.white,colors.gray)}

                TextBox{parent=rect,text="Pocket Computer"}

                create_common_indicators(pfx, rect)
            end
        end)

        ps.subscribe("comp_disconnect", function (id)
            if id == false then return end

            local type = ps.get("comp_" ..id .. "_type")

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
            { label = " @ ", color = core.cpair(colors.black, colors.blue), callback = main_page.nav_to },
            { label = "PLC", color = core.cpair(colors.black, colors.red), callback = plc_page.nav_to },
            { label = "RTU", color = core.cpair(colors.black, colors.orange), callback = rtu_page.nav_to },
            { label = "PKT", color = core.cpair(colors.black, colors.lightGray), callback = pkt_page.nav_to }
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

        -- clear the list of connected computers so that connections re-appear on reload of this app
        iocontrol.rx.clear_comp_record()
    end

    app.set_load(load)
    app.set_unload(unload)

    return main
end

return new_view
