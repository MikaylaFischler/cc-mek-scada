--
-- Process Control Page
--

local types         = require("scada-common.types")
local util          = require("scada-common.util")

local iocontrol     = require("pocket.iocontrol")
local pocket        = require("pocket.pocket")
local process       = require("pocket.process")

local style         = require("pocket.ui.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local MultiPane     = require("graphics.elements.MultiPane")
local TextBox       = require("graphics.elements.TextBox")

local WaitingAnim   = require("graphics.elements.animations.Waiting")

local HazardButton  = require("graphics.elements.controls.HazardButton")
local PushButton    = require("graphics.elements.controls.PushButton")

local NumberField   = require("graphics.elements.form.NumberField")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")
local IconIndicator = require("graphics.elements.indicators.IconIndicator")

local AUTO_GROUP = types.AUTO_GROUP

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

local lu_col       = style.label_unit_pair
local text_fg      = style.text_fg
local mode_states  = style.icon_states.mode_states

local hzd_fg_bg = cpair(colors.white, colors.gray)
local dis_colors = cpair(colors.white, colors.lightGray)

-- new process control page view
---@param root Container parent
local function new_view(root)
    local db = iocontrol.get_db()

    local frame = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(APP_ID.PROCESS, frame, nil, false, true)

    local load_div = Div{parent=frame,x=1,y=1}
    local main = Div{parent=frame,x=1,y=1}

    TextBox{parent=load_div,y=12,text="Loading...",alignment=ALIGN.CENTER}
    WaitingAnim{parent=load_div,x=math.floor(main.get_width()/2)-1,y=8,fg_bg=cpair(colors.green,colors._INHERIT)}

    local load_pane = MultiPane{parent=main,x=1,y=1,panes={load_div,main}}

    app.set_sidebar({ { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home } })

    local btn_fg_bg = cpair(colors.green, colors.black)
    local btn_active = cpair(colors.white, colors.black)

    local page_div = nil ---@type Div|nil

    -- load the app (create the elements)
    local function load()
        page_div = Div{parent=main,y=2,width=main.get_width()}

        local panes = {} ---@type Div[]

        -- create all page divs
        -- for _ = 1, db.facility.num_units + 1 do
        --     local div = Div{parent=page_div}
        --     table.insert(panes, div)
        -- end

        local last_update = 0
        -- refresh data callback, every 500ms it will re-send the query
        local function update()
            if util.time_ms() - last_update >= 500 then
                -- db.api.get_ctrl()
                last_update = util.time_ms()
            end
        end

        for i = 1, db.facility.num_units do
            local u_pane = panes[i]
            local u_div = Div{parent=u_pane,x=2,width=main.get_width()-2}
            local unit = db.units[i]
            local u_ps = unit.unit_ps

            local u_page = app.new_page(nil, i)
            u_page.tasks = { update }

            TextBox{parent=u_div,y=1,text="Reactor Unit #"..i,alignment=ALIGN.CENTER}

            u_div.line_break()

            util.nop()
        end

        -- main process page

        -- local f_pane = panes[db.facility.num_units + 1]
        -- local f_div = Div{parent=f_pane,x=2,width=main.get_width()-2}

        -- app.new_page(nil, db.facility.num_units + 1)

        -- setup multipane
        local u_pane = MultiPane{parent=page_div,x=1,y=1,panes=panes}
        app.set_root_pane(u_pane)

        -- setup sidebar

        local list = {
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
            { label = " \x17 ", color = core.cpair(colors.black, colors.orange), callback = function () app.switcher(db.facility.num_units + 1) end },
            { label = "SET", color = core.cpair(colors.black, colors.orange), callback = function () app.switcher(db.facility.num_units + 1) end }
        }

        for i = 1, db.facility.num_units do
            table.insert(list, { label = "U-" .. i, color = core.cpair(colors.black, colors.lightGray), callback = function () app.switcher(i) end })
        end

        app.set_sidebar(list)

        -- done, show the app
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
