--
-- System Apps
--

local comms      = require("scada-common.comms")
local util       = require("scada-common.util")

local lockbox    = require("lockbox")

local iocontrol  = require("pocket.iocontrol")
local pocket     = require("pocket.pocket")

local core       = require("graphics.core")

local Div        = require("graphics.elements.Div")
local ListBox    = require("graphics.elements.ListBox")
local MultiPane  = require("graphics.elements.MultiPane")
local TextBox    = require("graphics.elements.TextBox")

local PushButton = require("graphics.elements.controls.PushButton")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

-- create system app pages
---@param root Container parent
local function create_pages(root)
    local db = iocontrol.get_db()

    ----------------
    -- About Page --
    ----------------

    local about_root = Div{parent=root,x=1,y=1}

    local about_app = db.nav.register_app(APP_ID.ABOUT, about_root)

    local about_page = about_app.new_page(nil, 1)
    local nt_page = about_app.new_page(about_page, 2)
    local fw_page = about_app.new_page(about_page, 3)
    local hw_page = about_app.new_page(about_page, 4)

    local about = Div{parent=about_root,x=1,y=2}

    TextBox{parent=about,y=1,text="System Information",alignment=ALIGN.CENTER}

    local btn_fg_bg = cpair(colors.lightBlue, colors.black)
    local btn_active = cpair(colors.white, colors.black)
    local label = cpair(colors.lightGray, colors.black)

    PushButton{parent=about,x=2,y=3,text="Network             >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=nt_page.nav_to}
    PushButton{parent=about,x=2,y=4,text="Firmware            >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=fw_page.nav_to}
    PushButton{parent=about,x=2,y=5,text="Host Details        >",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=hw_page.nav_to}

    --#region Network Details

    local config = pocket.config

    local nt_div = Div{parent=about_root,x=1,y=2}
    TextBox{parent=nt_div,y=1,text="Network Details",alignment=ALIGN.CENTER}

    PushButton{parent=nt_div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=about_page.nav_to}

    TextBox{parent=nt_div,x=2,y=3,text="Pocket Address",fg_bg=label}
---@diagnostic disable-next-line: undefined-field
    TextBox{parent=nt_div,x=2,text=util.c(os.getComputerID(),":",config.PKT_Channel)}

    nt_div.line_break()
    TextBox{parent=nt_div,x=2,text="Supervisor Address",fg_bg=label}
    local sv = TextBox{parent=nt_div,x=2,text=""}

    nt_div.line_break()
    TextBox{parent=nt_div,x=2,text="Coordinator Address",fg_bg=label}
    local coord = TextBox{parent=nt_div,x=2,text=""}

    sv.register(db.ps, "sv_addr", sv.set_value)
    coord.register(db.ps, "api_addr", coord.set_value)

    nt_div.line_break()
    TextBox{parent=nt_div,x=2,text="Message Authentication",fg_bg=label}
    local auth = util.trinary(type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0, "HMAC-MD5", "None")
    TextBox{parent=nt_div,x=2,text=auth}

    --#endregion

    --#region Firmware Versions

    local fw_div = Div{parent=about_root,x=1,y=2}
    TextBox{parent=fw_div,y=1,text="Firmware Versions",alignment=ALIGN.CENTER}

    PushButton{parent=fw_div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=about_page.nav_to}

    local fw_list_box = ListBox{parent=fw_div,x=1,y=3,scroll_height=100,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}

    local fw_list = Div{parent=fw_list_box,x=1,y=2,height=18}

    TextBox{parent=fw_list,x=2,text="Pocket Version",fg_bg=label}
    TextBox{parent=fw_list,x=2,text=db.version}

    fw_list.line_break()
    TextBox{parent=fw_list,x=2,text="Comms Version",fg_bg=label}
    TextBox{parent=fw_list,x=2,text=comms.version}

    fw_list.line_break()
    TextBox{parent=fw_list,x=2,text="API Version",fg_bg=label}
    TextBox{parent=fw_list,x=2,text=comms.api_version}

    fw_list.line_break()
    TextBox{parent=fw_list,x=2,text="Common Lib Version",fg_bg=label}
    TextBox{parent=fw_list,x=2,text=util.version}

    fw_list.line_break()
    TextBox{parent=fw_list,x=2,text="Graphics Version",fg_bg=label}
    TextBox{parent=fw_list,x=2,text=core.version}

    fw_list.line_break()
    TextBox{parent=fw_list,x=2,text="Lockbox Version",fg_bg=label}
    TextBox{parent=fw_list,x=2,text=lockbox.version}

    --#endregion

    --#region Host Versions

    local hw_div = Div{parent=about_root,x=1,y=2}
    TextBox{parent=hw_div,y=1,text="Host Versions",alignment=ALIGN.CENTER}

    PushButton{parent=hw_div,x=2,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=about_page.nav_to}

    hw_div.line_break()
    TextBox{parent=hw_div,x=2,text="Lua Version",fg_bg=label}
    TextBox{parent=hw_div,x=2,text=_VERSION}

    hw_div.line_break()
    TextBox{parent=hw_div,x=2,text="Environment",fg_bg=label}
    TextBox{parent=hw_div,x=2,text=_HOST,height=6}

    --#endregion

    local root_pane = MultiPane{parent=about_root,x=1,y=1,panes={about,nt_div,fw_div,hw_div}}

    about_app.set_root_pane(root_pane)
end

return create_pages
