--
-- RTU Connection Entry
--

local databus       = require("supervisor.databus")

local style         = require("supervisor.panel.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local TextBox       = require("graphics.elements.TextBox")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")

local ALIGN = core.ALIGN

local cpair = core.cpair

-- create an RTU list entry
---@param parent ListBox parent
---@param id integer RTU session ID
local function init(parent, id)
    local s_hi_box = style.theme.highlight_box

    local label_fg = style.fp.label_fg

    local term_w, _ = term.getSize()

    -- root div
    local root = Div{parent=parent,x=2,y=2,height=4,width=parent.get_width()-2}
    local entry = Div{parent=root,x=2,y=1,height=3,fg_bg=style.theme.highlight_box_bright}

    local ps_prefix = "rtu_" .. id .. "_"

    TextBox{parent=entry,x=1,y=1,text="",width=8,fg_bg=s_hi_box}
    local rtu_addr = TextBox{parent=entry,x=1,y=2,text="@ C ??",alignment=ALIGN.CENTER,width=8,fg_bg=s_hi_box,nav_active=cpair(colors.gray,colors.black)}
    TextBox{parent=entry,x=1,y=3,text="",width=8,fg_bg=s_hi_box}
    rtu_addr.register(databus.ps, ps_prefix .. "addr", rtu_addr.set_value)

    TextBox{parent=entry,x=10,y=2,text="UNITS:",width=7}
    local unit_count = DataIndicator{parent=entry,x=17,y=2,label="",unit="",format="%2d",value=0,width=2,fg_bg=style.fp.label_d_fg}
    unit_count.register(databus.ps, ps_prefix .. "units", unit_count.set_value)

    TextBox{parent=entry,x=term_w-30,y=2,text="FW:",width=3}
    local rtu_fw_v = TextBox{parent=entry,x=term_w-26,y=2,text=" ------- ",width=9,fg_bg=label_fg}
    rtu_fw_v.register(databus.ps, ps_prefix .. "fw", rtu_fw_v.set_value)

    TextBox{parent=entry,x=term_w-15,y=2,text="RTT:",width=4}
    local rtu_rtt = DataIndicator{parent=entry,x=term_w-11,y=2,label="",unit="",format="%5d",value=0,width=5,fg_bg=label_fg}
    TextBox{parent=entry,x=term_w-5,y=2,text="ms",width=4,fg_bg=label_fg}
    rtu_rtt.register(databus.ps, ps_prefix .. "rtt", rtu_rtt.update)
    rtu_rtt.register(databus.ps, ps_prefix .. "rtt_color", rtu_rtt.recolor)

    return root
end

return init
