--
-- Pocket Diagnostics Connection Entry
--

local databus       = require("supervisor.databus")

local style         = require("supervisor.panel.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local TextBox       = require("graphics.elements.TextBox")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")

local ALIGN = core.ALIGN

local cpair = core.cpair

-- create a pocket diagnostics list entry
---@param parent ListBox parent
---@param id integer PDG session ID
local function init(parent, id)
    local s_hi_box = style.theme.highlight_box

    local label_fg = style.fp.label_fg

    local term_w, _ = term.getSize()

    -- root div
    local root = Div{parent=parent,x=2,y=2,height=4,width=parent.get_width()-2}
    local entry = Div{parent=root,x=2,y=1,height=3,fg_bg=style.theme.highlight_box_bright}

    local ps_prefix = "pdg_" .. id .. "_"

    TextBox{parent=entry,x=1,y=1,text="",width=8,fg_bg=s_hi_box}
    local pdg_addr = TextBox{parent=entry,x=1,y=2,text="@ C ??",alignment=ALIGN.CENTER,width=8,fg_bg=s_hi_box,nav_active=cpair(colors.gray,colors.black)}
    TextBox{parent=entry,x=1,y=3,text="",width=8,fg_bg=s_hi_box}
    pdg_addr.register(databus.ps, ps_prefix .. "addr", pdg_addr.set_value)

    TextBox{parent=entry,x=10,y=2,text="FW:",width=3}
    local pdg_fw_v = TextBox{parent=entry,x=14,y=2,text=" ------- ",width=20,fg_bg=label_fg}
    pdg_fw_v.register(databus.ps, ps_prefix .. "fw", pdg_fw_v.set_value)

    TextBox{parent=entry,x=term_w-16,y=2,text="RTT:",width=4}
    local pdg_rtt = DataIndicator{parent=entry,x=term_w-11,y=2,label="",unit="",format="%5d",value=0,width=5,fg_bg=label_fg}
    TextBox{parent=entry,x=term_w-5,y=2,text="ms",width=4,fg_bg=label_fg}
    pdg_rtt.register(databus.ps, ps_prefix .. "rtt", pdg_rtt.update)
    pdg_rtt.register(databus.ps, ps_prefix .. "rtt_color", pdg_rtt.recolor)

    return root
end

return init
