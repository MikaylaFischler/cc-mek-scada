--
-- Basic Unit Overview
--

local core         = require("graphics.core")

local style        = require("coordinator.ui.style")

local reactor_view = require("coordinator.ui.components.reactor")
local boiler_view  = require("coordinator.ui.components.boiler")
local turbine_view = require("coordinator.ui.components.turbine")

local Div          = require("graphics.elements.Div")
local PipeNetwork  = require("graphics.elements.PipeNetwork")
local TextBox      = require("graphics.elements.TextBox")

local ALIGN = core.ALIGN

local pipe = core.pipe
local log         = require("scada-common.log")
-- make a new unit overview window
---@param parent Container parent
---@param x integer top left x
---@param y integer top left y
---@param unit ioctl_unit unit database entry
local function make(parent, x, y, unit)
    local num_boilers = #unit.boiler_data_tbl
    local num_turbines = #unit.turbine_data_tbl

    assert(num_boilers  >= 0 and num_boilers  <= 20, "minimum 0 boilers, maximum 2 boilers")
    assert(num_turbines >= 1 and num_turbines <= 20, "minimum 1 turbine, maximum 3 turbines")

    local height = 33

    if num_boilers == 0 and num_turbines == 1 then
        height = 9
    elseif num_boilers <= 1 and num_turbines <= 2 then
        height = 17
    end

    assert(parent.get_height() >= (y + height), "main display not of sufficient vertical resolution (add an additional row of monitors)")

    -- bounding box div
    local root = Div{parent=parent,x=x,y=y,width=80,height=height}

    -- unit header message
    TextBox{parent=root,text="Unit #"..unit.unit_id,alignment=ALIGN.CENTER,fg_bg=style.theme.header}

    -------------
    -- REACTOR --
    -------------

    reactor_view(root, 1, 3, unit.unit_ps)

    -- if num_boilers > 0 then
    --     local coolant_pipes = {}

    --     if num_boilers >= 2 then
    --         table.insert(coolant_pipes, pipe(0, 0, 11, 12, colors.lightBlue))
    --     end

    --     table.insert(coolant_pipes, pipe(0, 0, 11, 3, colors.lightBlue))
    --     table.insert(coolant_pipes, pipe(2, 0, 11, 2, colors.orange))

    --     if num_boilers >= 2 then
    --         table.insert(coolant_pipes, pipe(2, 0, 11, 11, colors.orange))
    --     end

    --     PipeNetwork{parent=root,x=4,y=10,pipes=coolant_pipes,bg=style.theme.bg}
    -- end

    -------------
    -- BOILERS --
    -------------
    if num_boilers > 0 then
        local coolant_pipes = {}
        local boiler_pipes = {}
        local boiler_turbine_pipes = {}
        for i = 0,num_boilers-1,1
        do
            local pos_y = 11 + (i*8)
            boiler_view(root, 16, pos_y, unit.boiler_ps_tbl[i+1])
            table.insert(coolant_pipes, pipe(0, 0, 11, 3+(i*9), colors.lightBlue))
            table.insert(coolant_pipes, pipe(2, 0, 11, 2+(i*9), colors.orange))

            table.insert(boiler_pipes, pipe(8, 1+((i-1)*9), 8, 1+(i*9), colors.white, false, true))
            table.insert(boiler_pipes, pipe(9, 2+((i-1)*9), 9, 2+(i*9), colors.blue, false, true))

            table.insert(boiler_pipes, pipe(0, 1+(i*9), 8, 1+(i*9), colors.white, false, true))
            table.insert(boiler_pipes, pipe(0, 2+(i*9), 9, 2+(i*9), colors.blue, false, true))
            -- table.insert(boiler_pipes, pipe(8, 1+((i-1)*9), 8, 1+(i*9), colors.white, false, false))
            -- table.insert(boiler_pipes, pipe(9, 2+((i-1)*9), 9, 2+(i*9), colors.blue, false, false))
        end
        PipeNetwork{parent=root,x=4,y=10,pipes=coolant_pipes,bg=style.theme.bg}
        -- PipeNetwork{parent=root,x=47,y=11,pipes=boiler_turbine_pipes}
        PipeNetwork{parent=root,x=47,y=11,pipes=boiler_pipes}

        end
    --------------
    -- TURBINES --
    --------------

    local t_idx = 1
    local no_boilers = num_boilers == 0

    -- if (num_turbines >= 3) or no_boilers or (num_boilers == 1 and num_turbines >= 2) then
    --     turbine_view(root, 58, 3, unit.turbine_ps_tbl[t_idx])
    --     t_idx = t_idx + 1
    -- end

    -- if (num_turbines >= 1 and not no_boilers) or num_turbines >= 2 then
    --     turbine_view(root, 58, 11, unit.turbine_ps_tbl[t_idx])
    --     t_idx = t_idx + 1
    -- end

    -- if (num_turbines >= 2 and num_boilers >= 2) or num_turbines >= 3 then
    --     turbine_view(root, 58, 19, unit.turbine_ps_tbl[t_idx])
    -- end
    local steam_pipes_b = {}

    -- boiler_view(root, 16, pos_y, unit.boiler_ps_tbl[i+1])
    turbine_view(root, 58, 3, unit.turbine_ps_tbl[1])
    if no_boilers then 
        table.insert(steam_pipes_b, pipe(0, 1, 3, 1, colors.white))         -- steam to turbine 1
        table.insert(steam_pipes_b, pipe(0, 3, 3, 2, colors.blue)) 
    end
    local turbine_pipes = {}
    for i = 1,num_turbines-1,1
    do
        local pos_y = 3 + (i*8)

        turbine_view(root, 58, pos_y, unit.turbine_ps_tbl[i+1])
        if no_boilers then 
            table.insert(steam_pipes_b, pipe(0, 2, 3, 1+(i*8), colors.white))         -- steam to turbine 1
            table.insert(steam_pipes_b, pipe(1, 3, 3, 2+(i*8), colors.blue)) 
        else

            table.insert(turbine_pipes, pipe(0, 0+((i-1)*8), 0, 0+((i-1)*8), colors.white))         -- steam to turbine 1
            table.insert(turbine_pipes, pipe(0, 1+((i-1)*8), 0, 1+((i-1)*8), colors.blue)) 
            PipeNetwork{parent=root,x=57,y=14,pipes=turbine_pipes,bg=style.theme.bg}
        end
    end

    if not no_boilers then
        table.insert(steam_pipes_b, pipe(1, 8.999999, 1, 2, colors.white, false, false))    -- steam boiler 1 to turbine 1 junction start
        table.insert(steam_pipes_b, pipe(1, 1, 3, 1, colors.white, false, false))   -- steam boiler 1 to turbine 1 junction end

        table.insert(steam_pipes_b, pipe(2, 8.9999999, 2, 3, colors.blue, false, false))    -- water boiler 1 to turbine 1 junction start
        table.insert(steam_pipes_b, pipe(2, 2, 3, 2, colors.blue, false, false))    -- water boiler 1 to turbine 1 junction end
    end

    PipeNetwork{parent=root,x=54,y=3,pipes=steam_pipes_b,bg=style.theme.bg}

    return root
end

return make
