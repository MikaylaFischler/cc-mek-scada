--
-- Loading Screen App
--

local iocontrol    = require("pocket.iocontrol")
local pocket       = require("pocket.pocket")

local conn_waiting = require("pocket.ui.components.conn_waiting")

local core         = require("graphics.core")

local Div          = require("graphics.elements.Div")
local MultiPane    = require("graphics.elements.MultiPane")
local TextBox      = require("graphics.elements.TextBox")

local APP_ID = pocket.APP_ID

local LINK_STATE = iocontrol.LINK_STATE

-- create the connecting to SV & API page
---@param root Container parent
local function create_pages(root)
    local db = iocontrol.get_db()

    local main = Div{parent=root,x=1,y=1}

    db.nav.register_app(APP_ID.LOADER, main).new_page(nil, function () end)

    local conn_sv_wait = conn_waiting(main, 6, false)
    local conn_api_wait = conn_waiting(main, 6, true)
    local main_pane = Div{parent=main,x=1,y=2}

    local root_pane = MultiPane{parent=main,x=1,y=1,panes={conn_sv_wait,conn_api_wait,main_pane}}

    local function update()
        local state = db.ps.get("link_state")

        if state == LINK_STATE.UNLINKED then
            root_pane.set_value(1)
        elseif state == LINK_STATE.API_LINK_ONLY then
            if not db.loader_require.sv then
                root_pane.set_value(3)
                db.nav.on_loader_connected()
            else root_pane.set_value(1) end
        elseif state == LINK_STATE.SV_LINK_ONLY then
            if not db.loader_require.api then
                root_pane.set_value(3)
                db.nav.on_loader_connected()
            else root_pane.set_value(2) end
        else
            root_pane.set_value(3)
            db.nav.on_loader_connected()
        end
    end

    root_pane.register(db.ps, "link_state", update)
    root_pane.register(db.ps, "loader_reqs", update)

    TextBox{parent=main_pane,text="Connected!",x=1,y=6,alignment=core.ALIGN.CENTER}
end

return create_pages
