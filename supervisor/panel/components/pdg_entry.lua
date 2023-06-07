--
-- Pocket Diagnostics Connection Entry
--

local databus       = require("supervisor.databus")

local core          = require("graphics.core")

local Div           = require("graphics.elements.div")
local TextBox       = require("graphics.elements.textbox")

local DataIndicator = require("graphics.elements.indicators.data")

local TEXT_ALIGN = core.TEXT_ALIGN

local cpair = core.cpair

-- create a pocket diagnostics list entry
---@param parent graphics_element parent
---@param id integer PDG session ID
local function init(parent, id)
    -- root div
    local root = Div{parent=parent,x=2,y=2,height=4,width=parent.get_width()-2,hidden=true}
    local entry = Div{parent=root,x=2,y=1,height=3,fg_bg=cpair(colors.black,colors.white)}

    local ps_prefix = "pdg_" .. id .. "_"

    TextBox{parent=entry,x=1,y=1,text="",width=8,height=1,fg_bg=cpair(colors.black,colors.lightGray)}
    local pdg_addr = TextBox{parent=entry,x=1,y=2,text="@ C ??",alignment=TEXT_ALIGN.CENTER,width=8,height=1,fg_bg=cpair(colors.black,colors.lightGray),nav_active=cpair(colors.gray,colors.black)}
    TextBox{parent=entry,x=1,y=3,text="",width=8,height=1,fg_bg=cpair(colors.black,colors.lightGray)}
    pdg_addr.register(databus.ps, ps_prefix .. "addr", pdg_addr.set_value)

    TextBox{parent=entry,x=10,y=2,text="FW:",width=3,height=1}
    local pdg_fw_v = TextBox{parent=entry,x=14,y=2,text=" ------- ",width=20,height=1,fg_bg=cpair(colors.lightGray,colors.white)}
    pdg_fw_v.register(databus.ps, ps_prefix .. "fw", pdg_fw_v.set_value)

    TextBox{parent=entry,x=35,y=2,text="RTT:",width=4,height=1}
    local pdg_rtt = DataIndicator{parent=entry,x=40,y=2,label="",unit="",format="%5d",value=0,width=5,fg_bg=cpair(colors.lightGray,colors.white)}
    TextBox{parent=entry,x=46,y=2,text="ms",width=4,height=1,fg_bg=cpair(colors.lightGray,colors.white)}
    pdg_rtt.register(databus.ps, ps_prefix .. "rtt", pdg_rtt.update)
    pdg_rtt.register(databus.ps, ps_prefix .. "rtt_color", pdg_rtt.recolor)

    return root
end

return init
