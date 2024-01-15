--
-- Main Home Page
--

local iocontrol  = require("pocket.iocontrol")

local diag_apps  = require("pocket.ui.apps.diag_apps")

local core       = require("graphics.core")

local Div        = require("graphics.elements.div")
local MultiPane  = require("graphics.elements.multipane")
local TextBox    = require("graphics.elements.textbox")

local AppPageSel = require("graphics.elements.controls.app_page_selector")
local App        = require("graphics.elements.controls.app")

local cpair = core.cpair

local ALIGN = core.ALIGN

-- new home page view
---@param root graphics_element parent
local function new_view(root)
    local db = iocontrol.get_db()

    local main = Div{parent=root,x=1,y=1}

    local apps = Div{parent=main,x=1,y=1,height=19}

    local apps_1 = Div{parent=apps,x=1,y=1,height=15}
    local apps_2 = Div{parent=apps,x=1,y=1,height=15}

    local panes = { apps_1, apps_2 }

    local app_pane = MultiPane{parent=apps,x=1,y=1,panes=panes,height=15}

    AppPageSel{parent=apps,x=11,y=18,page_count=2,active_color=colors.lightGray,callback=app_pane.set_value,fg_bg=cpair(colors.gray,colors.black)}

    local d_apps = diag_apps(main)

    local page_panes = { apps, d_apps.Alarm.e }

    local page_pane = MultiPane{parent=main,x=1,y=1,panes=page_panes}

    local npage_home = db.nav.new_page(nil, 1, page_pane)
    local npage_apps = db.nav.new_page(npage_home, 1)

    local npage_alarm = db.nav.new_page(npage_apps, 2)
    npage_alarm.tasks = d_apps.Alarm.tasks

    App{parent=apps_1,x=3,y=2,text="\x17",title="PRC",callback=function()end,app_fg_bg=cpair(colors.black,colors.purple)}
    App{parent=apps_1,x=10,y=2,text="\x15",title="CTL",callback=function()end,app_fg_bg=cpair(colors.black,colors.green)}
    App{parent=apps_1,x=17,y=2,text="\x08",title="DEV",callback=function()end,app_fg_bg=cpair(colors.black,colors.lightGray)}
    App{parent=apps_1,x=3,y=7,text="\x7f",title="Waste",callback=function()end,app_fg_bg=cpair(colors.black,colors.brown)}
    App{parent=apps_1,x=10,y=7,text="\xb6",title="Guide",callback=function()end,app_fg_bg=cpair(colors.black,colors.cyan)}

    TextBox{parent=apps_2,text="Diagnostic Apps",x=1,y=2,height=1,alignment=ALIGN.CENTER}

    App{parent=apps_2,x=3,y=4,text="\x0f",title="Alarm",callback=npage_alarm.nav_to,app_fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}
    App{parent=apps_2,x=10,y=4,text="\x1e",title="LoopT",callback=function()end,app_fg_bg=cpair(colors.black,colors.cyan)}
    App{parent=apps_2,x=17,y=4,text="@",title="Comps",callback=function()end,app_fg_bg=cpair(colors.black,colors.orange)}

    return main
end

return new_view
