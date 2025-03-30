--
-- Main Home Page
--

local iocontrol    = require("pocket.iocontrol")
local pocket       = require("pocket.pocket")

local core         = require("graphics.core")

local AppMultiPane = require("graphics.elements.AppMultiPane")
local Div          = require("graphics.elements.Div")
local TextBox      = require("graphics.elements.TextBox")

local App          = require("graphics.elements.controls.App")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

-- new home page view
---@param root Container parent
local function new_view(root)
    local db = iocontrol.get_db()

    local main = Div{parent=root,x=1,y=1,height=19}

    local app = db.nav.register_app(APP_ID.ROOT, main)

    local apps_1 = Div{parent=main,x=1,y=1,height=15}
    local apps_2 = Div{parent=main,x=1,y=1,height=15}

    local panes = { apps_1, apps_2 }

    local app_pane = AppMultiPane{parent=main,x=1,y=1,height=18,panes=panes,active_color=colors.lightGray,nav_colors=cpair(colors.lightGray,colors.gray),scroll_nav=true,drag_nav=true,callback=app.switcher}

    app.set_root_pane(app_pane)
    app.new_page(app.new_page(nil, 1), 2)

    local function open(id) db.nav.open_app(id) end

    app.set_sidebar({
        { label = " #\x10", tall = true, color = core.cpair(colors.black, colors.green), callback = function () open(APP_ID.ROOT) end }
    })

    local active_fg_bg = cpair(colors.white,colors.gray)

    App{parent=apps_1,x=2,y=2,text="U",title="Units",callback=function()open(APP_ID.UNITS)end,app_fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=active_fg_bg}
    App{parent=apps_1,x=9,y=2,text="F",title="Facil",callback=function()open(APP_ID.FACILITY)end,app_fg_bg=cpair(colors.black,colors.orange),active_fg_bg=active_fg_bg}
    App{parent=apps_1,x=16,y=2,text="\x15",title="Control",callback=function()open(APP_ID.CONTROL)end,app_fg_bg=cpair(colors.black,colors.green),active_fg_bg=active_fg_bg}
    App{parent=apps_1,x=2,y=7,text="\x17",title="Process",callback=function()open(APP_ID.PROCESS)end,app_fg_bg=cpair(colors.black,colors.purple),active_fg_bg=active_fg_bg}
    App{parent=apps_1,x=9,y=7,text="\x7f",title="Waste",callback=function()open(APP_ID.WASTE)end,app_fg_bg=cpair(colors.black,colors.brown),active_fg_bg=active_fg_bg}
    App{parent=apps_1,x=16,y=7,text="\x08",title="Devices",callback=function()open(APP_ID.DUMMY)end,app_fg_bg=cpair(colors.black,colors.lightGray),active_fg_bg=active_fg_bg}
    App{parent=apps_1,x=2,y=12,text="\xb6",title="Guide",callback=function()open(APP_ID.GUIDE)end,app_fg_bg=cpair(colors.black,colors.cyan),active_fg_bg=active_fg_bg}
    App{parent=apps_1,x=9,y=12,text="?",title="About",callback=function()open(APP_ID.ABOUT)end,app_fg_bg=cpair(colors.black,colors.white),active_fg_bg=active_fg_bg}

    TextBox{parent=apps_2,text="Diagnostic Apps",x=1,y=2,alignment=ALIGN.CENTER}

    App{parent=apps_2,x=2,y=4,text="\x0f",title="Alarm",callback=function()open(APP_ID.ALARMS)end,app_fg_bg=cpair(colors.black,colors.red),active_fg_bg=active_fg_bg}
    App{parent=apps_2,x=9,y=4,text="\x1e",title="LoopT",callback=function()open(APP_ID.DUMMY)end,app_fg_bg=cpair(colors.black,colors.cyan),active_fg_bg=active_fg_bg}
    App{parent=apps_2,x=16,y=4,text="@",title="Comps",callback=function()open(APP_ID.DUMMY)end,app_fg_bg=cpair(colors.black,colors.orange),active_fg_bg=active_fg_bg}

    return main
end

return new_view
