--
-- Reactor Unit SCADA Coordinator GUI
--

local core   = require("graphics.core")
local layout = require("graphics.layout")

local style = require("coordinator.ui.style")

local displaybox = require("graphics.elements.displaybox")
local textbox    = require("graphics.elements.textbox")

local function init(monitor, id)
    local main = layout.create(monitor, displaybox{window=monitor,fg_bg=style.root})

    textbox{parent=main,text="Reactor Unit #" .. id,alignment=core.graphics.TEXT_ALIGN.CENTER,height=1,fg_bg=style.header}

    return main
end

return init