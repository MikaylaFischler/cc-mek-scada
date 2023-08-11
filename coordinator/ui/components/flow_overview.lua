--
-- Basic Unit Flow Overview
--

local util              = require("scada-common.util")

local core              = require("graphics.core")

local Div               = require("graphics.elements.div")
local PipeNetwork       = require("graphics.elements.pipenet")
local TextBox           = require("graphics.elements.textbox")

local Rectangle         = require("graphics.elements.rectangle")

local DataIndicator     = require("graphics.elements.indicators.data")

local IndicatorLight    = require("graphics.elements.indicators.light")
local TriIndicatorLight = require("graphics.elements.indicators.trilight")

local TEXT_ALIGN = core.TEXT_ALIGN

local cpair = core.cpair
local border = core.border
local pipe = core.pipe

-- make a new unit overview window
---@param parent graphics_element parent
---@param x integer top left x
---@param y integer top left y
---@param unit ioctl_unit unit database entry
local function make(parent, x, y, unit)
    local height = 16

    local v_start = 1 + ((unit.unit_id - 1) * 4)
    local prv_start = 1 + ((unit.unit_id - 1) * 3)
    local v_names = {
        util.sprintf("PV%02d-PU", v_start),
        util.sprintf("PV%02d-PO", v_start + 1),
        util.sprintf("PV%02d-PL", v_start + 2),
        util.sprintf("PV%02d-AM", v_start + 3),
        util.sprintf("PRV%02d", prv_start),
        util.sprintf("PRV%02d", prv_start + 1),
        util.sprintf("PRV%02d", prv_start + 2)
    }

    assert(parent.get_height() >= (y + height), "flow display not of sufficient vertical resolution (add an additional row of monitors) " .. y .. "," .. parent.get_height())

    -- bounding box div
    local root = Div{parent=parent,x=x,y=y,width=114,height=height}

    local text_fg_bg = cpair(colors.black, colors.white)
    local lu_col = cpair(colors.gray, colors.gray)

    ------------------
    -- COOLING LOOP --
    ------------------

    local reactor = Rectangle{parent=root,x=1,y=1,border=border(1, colors.gray, true),width=19,height=5,fg_bg=cpair(colors.white,colors.gray)}
    TextBox{parent=reactor,y=1,text="FISSION REACTOR",alignment=TEXT_ALIGN.CENTER,height=1}
    TextBox{parent=reactor,y=3,text="UNIT #"..unit.unit_id,alignment=TEXT_ALIGN.CENTER,height=1}
    TextBox{parent=root,x=19,y=2,text="\x1b \x80 \x1a",width=1,height=3,fg_bg=cpair(colors.lightGray,colors.gray)}
    TextBox{parent=root,x=4,y=5,text="\x19",width=1,height=1,fg_bg=cpair(colors.lightGray,colors.gray)}

    local rc_pipes = {}

    table.insert(rc_pipes, pipe(0, 1, 19, 1, colors.lightBlue, true))
    table.insert(rc_pipes, pipe(0, 3, 19, 3, colors.orange, true))
    table.insert(rc_pipes, pipe(39, 1, 58, 1, colors.blue, true))
    table.insert(rc_pipes, pipe(39, 3, 58, 3, colors.white, true))

    table.insert(rc_pipes, pipe(78, 0, 83, 0, colors.white, true))
    table.insert(rc_pipes, pipe(78, 2, 83, 2, colors.white, true))
    table.insert(rc_pipes, pipe(78, 4, 83, 4, colors.white, true))

    PipeNetwork{parent=root,x=20,y=1,pipes=rc_pipes,bg=colors.lightGray}

    local hc_rate = DataIndicator{parent=root,x=22,y=3,lu_colors=lu_col,label="",unit="mB/t",format="%11.0f",value=287000000,commas=true,width=16,fg_bg=text_fg_bg}
    local cc_rate = DataIndicator{parent=root,x=22,y=5,lu_colors=lu_col,label="",unit="mB/t",format="%11.0f",value=287000000,commas=true,width=16,fg_bg=text_fg_bg}

    local boiler = Rectangle{parent=root,x=40,y=1,border=border(1, colors.gray, true),width=19,height=5,fg_bg=cpair(colors.white,colors.gray)}
    TextBox{parent=boiler,y=1,text="THERMO-ELECTRIC",alignment=TEXT_ALIGN.CENTER,height=1}
    TextBox{parent=boiler,y=3,text="BOILERS",alignment=TEXT_ALIGN.CENTER,height=1}
    TextBox{parent=root,x=40,y=2,text="\x1b \x80 \x1a",width=1,height=3,fg_bg=cpair(colors.lightGray,colors.gray)}
    TextBox{parent=root,x=58,y=2,text="\x1b \x80 \x1a",width=1,height=3,fg_bg=cpair(colors.lightGray,colors.gray)}

    local wt_rate = DataIndicator{parent=root,x=61,y=3,lu_colors=lu_col,label="",unit="mB/t",format="%11.0f",value=287000000,commas=true,width=16,fg_bg=text_fg_bg}
    local st_rate = DataIndicator{parent=root,x=61,y=5,lu_colors=lu_col,label="",unit="mB/t",format="%11.0f",value=287000000,commas=true,width=16,fg_bg=text_fg_bg}

    local turbine = Rectangle{parent=root,x=79,y=1,border=border(1, colors.gray, true),width=19,height=5,fg_bg=cpair(colors.white,colors.gray)}
    TextBox{parent=turbine,y=1,text="STEAM TURBINE",alignment=TEXT_ALIGN.CENTER,height=1}
    TextBox{parent=turbine,y=3,text="GENERATORS",alignment=TEXT_ALIGN.CENTER,height=1}
    TextBox{parent=root,x=79,y=2,text="\x1a \x80 \x1b",width=1,height=3,fg_bg=cpair(colors.lightGray,colors.gray)}

    local function _relief(rx, ry, name)
        TextBox{parent=root,x=rx,y=ry,text="\x10\x11\x7f",fg_bg=cpair(colors.black,colors.lightGray),width=3,height=1}
        local conn = TriIndicatorLight{parent=root,x=rx+4,y=ry,label=name,c1=colors.gray,c2=colors.yellow,c3=colors.red}
    end

    _relief(103, 1, v_names[5])
    _relief(103, 3, v_names[6])
    _relief(103, 5, v_names[7])

    ----------------------
    -- WASTE PROCESSING --
    ----------------------

    local waste = Div{parent=root,x=3,y=6}

    local waste_pipes = {
        pipe(0, 0, 16, 1, colors.brown, true),
        pipe(12, 1, 16, 5, colors.brown, true),
        pipe(18, 1, 44, 1, colors.brown, true),
        pipe(18, 5, 23, 5, colors.brown, true),
        pipe(52, 1, 80, 1, colors.green, true),
        pipe(42, 4, 60, 4, colors.cyan, true),
        pipe(56, 4, 60, 8, colors.cyan, true),
        pipe(62, 4, 80, 4, colors.cyan, true),
        pipe(62, 8, 110, 8, colors.cyan, true),
        pipe(93, 1, 94, 3, colors.black, true, true),
        pipe(93, 4, 109, 6, colors.black, true, true),
        pipe(109, 6, 107, 6, colors.black, true, true)
    }

    PipeNetwork{parent=waste,x=2,y=1,pipes=waste_pipes,bg=colors.lightGray}

    local function _valve(vx, vy, n)
        TextBox{parent=waste,x=vx,y=vy,text="\x10\x11",fg_bg=cpair(colors.black,colors.lightGray),width=2,height=1}
        local conn = IndicatorLight{parent=waste,x=vx-3,y=vy+1,label=v_names[n],colors=cpair(colors.green,colors.gray)}
        local state = IndicatorLight{parent=waste,x=vx-3,y=vy+2,label="STATE",colors=cpair(colors.white,colors.white)}
    end

    local function _machine(mx, my, name)
        local l = string.len(name) + 2
        TextBox{parent=waste,x=mx,y=my,text=util.strrep("\x8f",l),alignment=TEXT_ALIGN.CENTER,fg_bg=cpair(colors.lightGray,colors.gray),width=l,height=1}
        TextBox{parent=waste,x=mx,y=my+1,text=name,alignment=TEXT_ALIGN.CENTER,fg_bg=cpair(colors.white,colors.gray),width=l,height=1}
    end

    local waste_rate = DataIndicator{parent=waste,x=1,y=3,lu_colors=lu_col,label="",unit="mB/t",format="%7.2f",value=1234.56,width=12,fg_bg=text_fg_bg}
    local pu_rate = DataIndicator{parent=waste,x=70,y=3,lu_colors=lu_col,label="",unit="mB/t",format="%7.3f",value=123.456,width=12,fg_bg=text_fg_bg}
    local po_rate = DataIndicator{parent=waste,x=45,y=6,lu_colors=lu_col,label="",unit="mB/t",format="%7.3f",value=123.456,width=12,fg_bg=text_fg_bg}
    local popl_rate = DataIndicator{parent=waste,x=70,y=6,lu_colors=lu_col,label="",unit="mB/t",format="%7.3f",value=123.456,width=12,fg_bg=text_fg_bg}
    local poam_rate = DataIndicator{parent=waste,x=70,y=10,lu_colors=lu_col,label="",unit="mB/t",format="%7.3f",value=123.456,width=12,fg_bg=text_fg_bg}
    local spent_rate = DataIndicator{parent=waste,x=99,y=4,lu_colors=lu_col,label="",unit="mB/t",format="%7.3f",value=123.456,width=12,fg_bg=text_fg_bg}

    _valve(18, 2, 1)
    _valve(18, 6, 2)
    _valve(62, 5, 3)
    _valve(62, 9, 4)

    _machine(45, 1, "CENTRIFUGE \x1a");
    _machine(83, 1, "PRC [Pu] \x1a");
    _machine(83, 4, "PRC [Po] \x1a");
    _machine(94, 6, "SPENT WASTE \x1b")

    TextBox{parent=waste,x=25,y=3,text="SNAs [Po]",alignment=TEXT_ALIGN.CENTER,width=19,height=1,fg_bg=cpair(colors.white,colors.gray)}
    local sna_po  = Rectangle{parent=waste,x=25,y=4,border=border(1, colors.gray, true),width=19,height=7,thin=true,fg_bg=cpair(colors.black,colors.white)}
    local sna_act = IndicatorLight{parent=sna_po,label="ACTIVE",colors=cpair(colors.green,colors.gray)}
    local sna_cnt = DataIndicator{parent=sna_po,x=12,y=1,lu_colors=lu_col,label="CNT",unit="",format="%2d",value=99,width=7,fg_bg=text_fg_bg}
    local sna_pk = DataIndicator{parent=sna_po,y=3,lu_colors=lu_col,label="PEAK",unit="mB/t",format="%7.2f",value=1000,width=17,fg_bg=text_fg_bg}
    local sna_max = DataIndicator{parent=sna_po,lu_colors=lu_col,label="MAX ",unit="mB/t",format="%7.2f",value=1000,width=17,fg_bg=text_fg_bg}
    local sna_in = DataIndicator{parent=sna_po,lu_colors=lu_col,label="IN  ",unit="mB/t",format="%7.2f",value=1000,width=17,fg_bg=text_fg_bg}

    return root
end

return make
