--
-- Pocket Connection Entry
--

local iocontrol     = require("coordinator.iocontrol")

local style         = require("coordinator.ui.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local TextBox       = require("graphics.elements.TextBox")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")

local ALIGN = core.ALIGN

local cpair = core.cpair

-- create a pocket list entry
---@param parent ListBox parent
---@param id integer PKT session ID
local function init(parent, id)
    local s_hi_box = style.fp_theme.highlight_box
    local s_hi_bright = style.fp_theme.highlight_box_bright

    local label_fg = style.fp.label_fg

    local ps = iocontrol.get_db().fp.ps

    local term_w, _ = term.getSize()

    -- root div
    local root = Div{parent=parent,x=2,y=2,height=4,width=parent.get_width()-2}
    local entry = Div{parent=root,x=2,y=1,height=3,fg_bg=s_hi_bright}

    local ps_prefix = "pkt_" .. id .. "_"

    TextBox{parent=entry,x=1,y=1,text="",width=8,fg_bg=s_hi_box}
    local pkt_addr = TextBox{parent=entry,x=1,y=2,text="@ C ??",alignment=ALIGN.CENTER,width=8,fg_bg=s_hi_box,nav_active=cpair(colors.gray,colors.black)}
    TextBox{parent=entry,x=1,y=3,text="",width=8,fg_bg=s_hi_box}
    pkt_addr.register(ps, ps_prefix .. "addr", pkt_addr.set_value)

    TextBox{parent=entry,x=10,y=2,text="FW:",width=3}
    local pkt_fw_v = TextBox{parent=entry,x=14,y=2,text=" ------- ",width=20,fg_bg=label_fg}
    pkt_fw_v.register(ps, ps_prefix .. "fw", pkt_fw_v.set_value)

    TextBox{parent=entry,x=term_w-16,y=2,text="RTT:",width=4}
    local pkt_rtt = DataIndicator{parent=entry,x=term_w-11,y=2,label="",unit="",format="%5d",value=0,width=5,fg_bg=label_fg}
    TextBox{parent=entry,x=term_w-5,y=2,text="ms",width=4,fg_bg=label_fg}
    pkt_rtt.register(ps, ps_prefix .. "rtt", pkt_rtt.update)
    pkt_rtt.register(ps, ps_prefix .. "rtt_color", pkt_rtt.recolor)

    return root
end

return init
