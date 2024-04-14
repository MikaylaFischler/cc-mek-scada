--
-- System Apps
--

local comms      = require("scada-common.comms")
local lockbox    = require("lockbox")
local util       = require("scada-common.util")

local iocontrol  = require("pocket.iocontrol")

local core       = require("graphics.core")

local Div        = require("graphics.elements.div")
local ListBox    = require("graphics.elements.listbox")
local MultiPane  = require("graphics.elements.multipane")
local TextBox    = require("graphics.elements.textbox")

local PushButton = require("graphics.elements.controls.push_button")

local cpair = core.cpair

local ALIGN = core.ALIGN

-- create system app pages
---@param root graphics_element parent
local function create_pages(root)
    local db = iocontrol.get_db()

    ----------------
    -- About Page --
    ----------------

    local about_root = Div{parent=root,x=1,y=1}

    local about_app = db.nav.register_app(iocontrol.APP_ID.ABOUT, about_root)

    local about_page = about_app.new_page(nil, 1)
    local fw_page = about_app.new_page(about_page, 2)
    local hw_page = about_app.new_page(about_page, 3)

    local about = Div{parent=about_root,x=1,y=2}

    TextBox{parent=about,y=1,text="System Information",height=1,alignment=ALIGN.CENTER}

    local btn_fg_bg = cpair(colors.lightBlue, colors.black)
    local btn_active = cpair(colors.white, colors.black)
    local label = cpair(colors.lightGray, colors.black)

    PushButton{parent=about,x=2,y=3,text="Firmware            >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fw_page.nav_to}
    PushButton{parent=about,x=2,y=4,text="Host Details        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=hw_page.nav_to}

    local fw_div = Div{parent=about_root,x=1,y=2}
    TextBox{parent=fw_div,y=1,text="Firmware Versions",height=1,alignment=ALIGN.CENTER}

    PushButton{parent=fw_div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=about_page.nav_to}

    local fw_list_box = ListBox{parent=fw_div,x=1,y=3,scroll_height=100,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}

    local fw_list = Div{parent=fw_list_box,x=1,y=2,height=18}

    TextBox{parent=fw_list,x=2,text="Pocket Version",height=1,alignment=ALIGN.LEFT,fg_bg=label}
    TextBox{parent=fw_list,x=2,text=db.version,height=1,alignment=ALIGN.LEFT}

    fw_list.line_break()
    TextBox{parent=fw_list,x=2,text="Comms Version",height=1,alignment=ALIGN.LEFT,fg_bg=label}
    TextBox{parent=fw_list,x=2,text=comms.version,height=1,alignment=ALIGN.LEFT}

    fw_list.line_break()
    TextBox{parent=fw_list,x=2,text="API Version",height=1,alignment=ALIGN.LEFT,fg_bg=label}
    TextBox{parent=fw_list,x=2,text=comms.api_version,height=1,alignment=ALIGN.LEFT}

    fw_list.line_break()
    TextBox{parent=fw_list,x=2,text="Common Lib Version",height=1,alignment=ALIGN.LEFT,fg_bg=label}
    TextBox{parent=fw_list,x=2,text=util.version,height=1,alignment=ALIGN.LEFT}

    fw_list.line_break()
    TextBox{parent=fw_list,x=2,text="Graphics Version",height=1,alignment=ALIGN.LEFT,fg_bg=label}
    TextBox{parent=fw_list,x=2,text=core.version,height=1,alignment=ALIGN.LEFT}

    fw_list.line_break()
    TextBox{parent=fw_list,x=2,text="Lockbox Version",height=1,alignment=ALIGN.LEFT,fg_bg=label}
    TextBox{parent=fw_list,x=2,text=lockbox.version,height=1,alignment=ALIGN.LEFT}

    local hw_div = Div{parent=about_root,x=1,y=2}
    TextBox{parent=hw_div,y=1,text="Host Versions",height=1,alignment=ALIGN.CENTER}

    PushButton{parent=hw_div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=about_page.nav_to}

    hw_div.line_break()
    TextBox{parent=hw_div,x=2,text="Lua Version",height=1,alignment=ALIGN.LEFT,fg_bg=label}
    TextBox{parent=hw_div,x=2,text=_VERSION,height=1,alignment=ALIGN.LEFT}

    hw_div.line_break()
    TextBox{parent=hw_div,x=2,text="Environment",height=1,alignment=ALIGN.LEFT,fg_bg=label}
    TextBox{parent=hw_div,x=2,text=_HOST,height=6,alignment=ALIGN.LEFT}

    local root_pane = MultiPane{parent=about_root,x=1,y=1,panes={about,fw_div,hw_div}}

    about_app.set_root_pane(root_pane)
end

return create_pages
