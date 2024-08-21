--
-- RTU ID Check Failure Entry
--

local style   = require("supervisor.panel.style")

local core    = require("graphics.core")

local Div     = require("graphics.elements.div")
local TextBox = require("graphics.elements.textbox")

local ALIGN = core.ALIGN

local cpair = core.cpair

-- create an ID check list entry
---@param parent graphics_element parent
---@param msg string message
---@param fail_code integer failure code
local function init(parent, msg, fail_code)
    -- root div
    local root = Div{parent=parent,x=2,y=2,height=4,width=parent.get_width()-2,hidden=true}
    local entry = Div{parent=root,x=2,y=1,height=3,fg_bg=style.theme.highlight_box_bright}

    if fail_code == 1 then
        TextBox{parent=entry,y=1,text="",width=11,fg_bg=cpair(colors.black,colors.orange)}
        TextBox{parent=entry,text="BAD INDEX",alignment=ALIGN.CENTER,width=11,fg_bg=cpair(colors.black,colors.orange)}
        TextBox{parent=entry,text="",width=11,fg_bg=cpair(colors.black,colors.orange)}
    elseif fail_code == 2 then
        TextBox{parent=entry,y=1,text="",width=11,fg_bg=cpair(colors.black,colors.red)}
        TextBox{parent=entry,text="DUPLICATE",alignment=ALIGN.CENTER,width=11,fg_bg=cpair(colors.black,colors.red)}
        TextBox{parent=entry,text="",width=11,fg_bg=cpair(colors.black,colors.red)}
    elseif fail_code == 4 then
        TextBox{parent=entry,y=1,text="",width=11,fg_bg=cpair(colors.black,colors.yellow)}
        TextBox{parent=entry,text="MISSING",alignment=ALIGN.CENTER,width=11,fg_bg=cpair(colors.black,colors.yellow)}
        TextBox{parent=entry,text="",width=11,fg_bg=cpair(colors.black,colors.yellow)}
    end

    TextBox{parent=entry,x=13,y=2,text=msg}

    return root
end

return init
