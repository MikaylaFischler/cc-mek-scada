--
-- System Guide
--

-- local util       = require("scada-common.util")
-- local log        = require("scada-common.log")

local iocontrol  = require("pocket.iocontrol")

local core       = require("graphics.core")

local Div        = require("graphics.elements.div")
-- local ListBox    = require("graphics.elements.listbox")
local MultiPane  = require("graphics.elements.multipane")
local TextBox    = require("graphics.elements.textbox")

local PushButton = require("graphics.elements.controls.push_button")

local ALIGN = core.ALIGN
local cpair = core.cpair

-- new system guide view
---@param root graphics_element parent
local function new_view(root)
    local db = iocontrol.get_db()

    local main = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(iocontrol.APP_ID.GUIDE, main)

    TextBox{parent=main,y=2,text="Guide",height=1,alignment=ALIGN.CENTER}
    TextBox{parent=main,y=4,text="Loading...",height=1,alignment=ALIGN.CENTER}

    local btn_fg_bg = cpair(colors.cyan, colors.black)
    local btn_active = cpair(colors.white, colors.black)

    local list = {
        { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = function () db.nav.open_app(iocontrol.APP_ID.ROOT) end },
        { label = "Use", tall = true, color = core.cpair(colors.black, colors.purple), callback = function () app.switcher(1) end },
        { label = "UIs", tall = true, color = core.cpair(colors.black, colors.blue), callback = function () app.switcher(2) end },
        { label = "FPs", tall = true, color = core.cpair(colors.black, colors.lightGray), callback = function () app.switcher(3) end }
    }

    app.set_sidebar(list)

    local function load()
        local page_div = Div{parent=main,y=2}
        local p_width = page_div.get_width() - 2
        local sub_panes = {}

        local main_page = app.new_page(nil, 1)
        local use_page = app.new_page(main_page, 2)
        local uis_page = app.new_page(main_page, 3)
        local fps_page = app.new_page(main_page, 4)

        local home = Div{parent=page_div,x=2,width=p_width}

        TextBox{parent=home,y=1,text="cc-mek-scada Guide",height=1,alignment=ALIGN.CENTER}

        PushButton{parent=home,y=3,text="System Usage        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=use_page.nav_to}
        PushButton{parent=home,text="Operator UIs        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=uis_page.nav_to}
        PushButton{parent=home,text="Front Panels        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fps_page.nav_to}

        local use = Div{parent=page_div,x=2,width=p_width}

        TextBox{parent=use,y=1,text="System Usage",height=1,alignment=ALIGN.CENTER}

        PushButton{parent=use,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        PushButton{parent=use,y=3,text="Configuring Devices >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}
        PushButton{parent=use,text="Connecting Devices  >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}
        PushButton{parent=use,text="Manual Control      >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}
        PushButton{parent=use,text="Automatic Control   >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}
        PushButton{parent=use,text="Waste Control       >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}

        local uis = Div{parent=page_div,x=2,width=p_width}

        TextBox{parent=uis,y=1,text="Operator UIs",height=1,alignment=ALIGN.CENTER}

        PushButton{parent=uis,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        PushButton{parent=uis,y=3,text="Annunciators        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}
        PushButton{parent=uis,text="Pocket UI           >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}
        PushButton{parent=uis,text="Coordinator UI      >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}

        local fps = Div{parent=page_div,x=2,width=p_width}

        TextBox{parent=fps,y=1,text="Front Panels",height=1,alignment=ALIGN.CENTER}

        PushButton{parent=fps,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=main_page.nav_to}

        PushButton{parent=fps,y=3,text="Common Items        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}
        PushButton{parent=fps,text="Reactor PLC         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}
        PushButton{parent=fps,text="RTU Gateway         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}
        PushButton{parent=fps,text="Supervisor          >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}
        PushButton{parent=fps,text="Coordinator         >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()end}

        -- setup multipane
        local u_pane = MultiPane{parent=page_div,x=1,y=1,panes={home,use,uis,fps,table.unpack(sub_panes)}}
        app.set_root_pane(u_pane)
    end

    app.set_on_load(load)

    return main
end

return new_view
