--
-- Unit Overview Page
--

local iocontrol = require("pocket.iocontrol")
local util      = require("scada-common.util")

local core      = require("graphics.core")

local Div       = require("graphics.elements.div")
local MultiPane  = require("graphics.elements.multipane")
local TextBox   = require("graphics.elements.textbox")

local AlarmLight        = require("graphics.elements.indicators.alight")
local CoreMap           = require("graphics.elements.indicators.coremap")
local DataIndicator     = require("graphics.elements.indicators.data")
local IconIndicator     = require("graphics.elements.indicators.icon")
local IndicatorLight    = require("graphics.elements.indicators.light")
local RadIndicator      = require("graphics.elements.indicators.rad")
local TriIndicatorLight = require("graphics.elements.indicators.trilight")
local VerticalBar       = require("graphics.elements.indicators.vbar")

local HazardButton      = require("graphics.elements.controls.hazard_button")
local MultiButton       = require("graphics.elements.controls.multi_button")
local PushButton        = require("graphics.elements.controls.push_button")
local RadioButton       = require("graphics.elements.controls.radio_button")
local SpinboxNumeric    = require("graphics.elements.controls.spinbox_numeric")

local ALIGN = core.ALIGN
local cpair = core.cpair

-- new unit page view
---@param root graphics_element parent
local function new_view(root)
    local db = iocontrol.get_db()

    local main = Div{parent=root,x=1,y=1}

    local app = db.nav.register_app(iocontrol.APP_ID.UNITS, main)
    app.new_page(nil, function () end)

    TextBox{parent=main,y=2,text="Units App",height=1,alignment=ALIGN.CENTER}

    TextBox{parent=main,y=4,text="Loading...",height=1,alignment=ALIGN.CENTER}

    local page_div = Div{parent=main,x=2,y=2,width=main.get_width()-2}

    local btn_fg_bg = cpair(colors.yellow, colors.black)
    local btn_active = cpair(colors.white, colors.black)
    local label = cpair(colors.lightGray, colors.black)

    local function set_sidebar(unit)
        app.set_sidebar({
            { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = function () db.nav.open_app(iocontrol.APP_ID.ROOT) end },
            { label = "U#" .. unit, color = core.cpair(colors.black, colors.yellow), callback = function () end },
            { label = "RPS", color = core.cpair(colors.black, colors.red), callback = function () end },
            { label = "RCS", color = core.cpair(colors.black, colors.blue), callback = function () end },
            { label = " R ", tall = true, color = core.cpair(colors.black, colors.orange), callback = function () end },
        })
    end

    local function load()
        local u_pages = {}

        local active_unit = 1
        set_sidebar(active_unit)

        for _ = 1, db.facility.num_units do
            local div = Div{parent=page_div}
            table.insert(u_pages, div)
        end

        local u_pane = MultiPane{parent=page_div,x=1,y=1,panes=u_pages}

        local function prev(x)
            active_unit = util.trinary(x == 1, db.facility.num_units, x - 1)
            u_pane.set_value(active_unit)
            set_sidebar(active_unit)
        end

        local function next(x)
            active_unit = util.trinary(x == db.facility.num_units, 1, x + 1)
            u_pane.set_value(active_unit)
            set_sidebar(active_unit)
        end

        for i = 1, db.facility.num_units do
            local u_div = u_pages[i] ---@type graphics_element
            local unit = db.units[i] ---@type pioctl_unit

            TextBox{parent=u_div,y=1,text="Reactor Unit #"..i,height=1,alignment=ALIGN.CENTER}
            PushButton{parent=u_div,x=1,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()prev(i)end}
            PushButton{parent=u_div,x=21,y=1,text=">",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=function()next(i)end}

            local type = util.trinary(unit.num_boilers > 0, "Sodium Cooled Reactor", "Boiling Water Reactor")
            TextBox{parent=u_div,y=3,text=type,height=1,alignment=ALIGN.CENTER,fg_bg=cpair(colors.gray,colors.black)}

            local lu_col = cpair(colors.lightGray, colors.lightGray)
            local text_fg = cpair(colors.white, colors._INHERIT)

            local rate = DataIndicator{parent=u_div,y=5,lu_colors=lu_col,label="Rate",unit="mB/t",format="%10.2f",value=0,commas=true,width=26,fg_bg=text_fg}
            local temp = DataIndicator{parent=u_div,lu_colors=lu_col,label="Temp",unit="K",format="%10.2f",value=0,commas=true,width=26,fg_bg=text_fg}

            local basic_states = {
                { color = cpair(colors.black,colors.lightGray), symbol = "\x07" },
                { color = cpair(colors.black,colors.red), symbol = "-" },
                { color = cpair(colors.black,colors.yellow), symbol = "\x1e" },
                { color = cpair(colors.black,colors.green), symbol = "+" }
            }

            local mode_states = {
                { color = cpair(colors.black,colors.lightGray), symbol = "\x07" },
                { color = cpair(colors.black,colors.red), symbol = "-" },
                { color = cpair(colors.black,colors.green), symbol = "+" },
                { color = cpair(colors.black,colors.purple), symbol = "A" }
            }

            local ctrl = IconIndicator{parent=u_div,x=1,y=8,label="Control State",states=mode_states}

            ctrl.update(i+1)

            u_div.line_break()

            local rct = IconIndicator{parent=u_div,x=1,label="Fission Reactor",states=basic_states}
            local rps = IconIndicator{parent=u_div,x=1,label="Protection System",states=basic_states}

            u_div.line_break()

            local rcs = IconIndicator{parent=u_div,x=1,label="Coolant System",states=basic_states}

            for b = 1, unit.num_boilers do
                local blr = IconIndicator{parent=u_div,x=1,label="Boiler "..b,states=basic_states}
                blr.update(b+2)
            end

            for t = 1, unit.num_turbines do
                local trb = IconIndicator{parent=u_div,x=1,label="Turbine "..t,states=basic_states}
                trb.update(t)
            end

            rct.update(4)
            rps.update(3)
            rcs.update(3)
        end
    end

    app.set_on_load(load)

    return main
end

return new_view
