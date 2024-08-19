--
-- RTU ID Check Failure Entry
--

local databus       = require("supervisor.databus")

local style         = require("supervisor.panel.style")

local core          = require("graphics.core")

local Div           = require("graphics.elements.div")
local TextBox       = require("graphics.elements.textbox")

local ALIGN = core.ALIGN

local cpair = core.cpair

-- create an ID check list entry
---@param parent graphics_element parent
---@param unit unit_session RTU session
---@param fail_code integer failure code
local function init(parent, unit, fail_code, cmp_id)
    local s_hi_box = style.theme.highlight_box

    local label_fg = style.fp.label_fg

    -- root div
    local root = Div{parent=parent,x=2,y=2,height=4,width=parent.get_width()-2,hidden=true}
    local entry = Div{parent=root,x=2,y=1,height=3,fg_bg=style.theme.highlight_box_bright}

    if fail_code == 1 then
        TextBox{parent=entry,y=1,text="",width=11,fg_bg=cpair(colors.black,colors.orange)}
        TextBox{parent=entry,text="BAD INDEX",alignment=ALIGN.CENTER,width=11,nav_active=cpair(colors.black,colors.orange)}
        TextBox{parent=entry,text="",width=11,fg_bg=cpair(colors.black,colors.orange)}
    elseif fail_code == 2 then
        TextBox{parent=entry,y=1,text="",width=11,fg_bg=cpair(colors.black,colors.red)}
        TextBox{parent=entry,text="DUPLICATE",alignment=ALIGN.CENTER,width=11,nav_active=cpair(colors.black,colors.red)}
        TextBox{parent=entry,text="",width=11,fg_bg=cpair(colors.black,colors.red)}
    elseif fail_code == 4 then
        TextBox{parent=entry,y=1,text="",width=11,fg_bg=cpair(colors.black,colors.yellow)}
        TextBox{parent=entry,text="MISSING",alignment=ALIGN.CENTER,width=11,nav_active=cpair(colors.black,colors.yellow)}
        TextBox{parent=entry,text="",width=11,fg_bg=cpair(colors.black,colors.yellow)}
    end

    if fail_code ~= 4 and cmp_id then
        local rtu_addr = TextBox{parent=entry,x=1,y=2,text="@ C ??",alignment=ALIGN.CENTER,width=8,fg_bg=s_hi_box,nav_active=cpair(colors.gray,colors.black)}
    end

    if fail_code ~= 4 and cmp_id then
        local rtu_addr = TextBox{parent=entry,x=1,y=2,text="@ C ??",alignment=ALIGN.CENTER,width=8,fg_bg=s_hi_box,nav_active=cpair(colors.gray,colors.black)}
    end

    TextBox{parent=entry,x=21,y=2,text="FW:",width=3}
    local rtu_fw_v = TextBox{parent=entry,x=25,y=2,text=" ------- ",width=9,fg_bg=label_fg}

    return root
end

return init
