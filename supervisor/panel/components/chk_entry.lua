--
-- RTU ID Check Failure Entry
--

local types   = require("scada-common.types")

local style   = require("supervisor.panel.style")

local core    = require("graphics.core")

local Div     = require("graphics.elements.Div")
local TextBox = require("graphics.elements.TextBox")

local ALIGN = core.ALIGN

local cpair = core.cpair

-- create an ID check list entry
---@param parent ListBox parent
---@param msg string message
---@param fail_code integer failure code
local function init(parent, msg, fail_code)
    -- root div
    local root = Div{parent=parent,x=2,y=2,height=4,width=parent.get_width()-2,hidden=true}
    local entry = Div{parent=root,x=2,y=1,height=3,fg_bg=style.theme.highlight_box_bright}

    local fg_bg = cpair(colors.black,colors.yellow)
    local tag = "MISSING"

    if fail_code == types.RTU_ID_FAIL.OUT_OF_RANGE then
        fg_bg = cpair(colors.black,colors.orange)
        tag = "BAD INDEX"
    elseif fail_code == types.RTU_ID_FAIL.DUPLICATE then
        fg_bg = cpair(colors.black,colors.red)
        tag = "DUPLICATE"
    end

    TextBox{parent=entry,y=1,text="",width=11,fg_bg=fg_bg}
    TextBox{parent=entry,text=tag,alignment=ALIGN.CENTER,width=11,fg_bg=fg_bg}
    TextBox{parent=entry,text="",width=11,fg_bg=fg_bg}

    TextBox{parent=entry,x=13,y=2,text=msg}

    return root
end

return init
