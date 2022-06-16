--
-- Reactor Unit SCADA Coordinator GUI
--

local core   = require("graphics.core")

local style = require("coordinator.ui.style")

local DisplayBox = require("graphics.elements.displaybox")
local TextBox    = require("graphics.elements.textbox")

local TEXT_ALIGN = core.graphics.TEXT_ALIGN

local function init(monitor, id)
    local main = DisplayBox{window=monitor,fg_bg=style.root}

    TextBox{parent=main,text="Reactor Unit #" .. id,alignment=TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    return main
end

return init
