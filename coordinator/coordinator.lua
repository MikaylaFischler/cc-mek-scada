
local comms = require("scada-common.comms")
local log = require("scada-common.log")
local ppm = require("scada-common.ppm")
local util = require("scada-common.util")

local dialog = require("coordinator.util.dialog")

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local coordinator = {}

local function ask_monitor(names)
    println("available monitors:")
    for i = 1, #names do
        print(" " .. names[i])
    end
    println("")
    println("select a monitor or type c to cancel")

    local iface = dialog.ask_options(names, "c")

    if iface ~= false and iface ~= nil then
        util.filter_table(names, function (x) return x ~= iface end)
    end

    return iface
end

function coordinator.configure_monitors(num_units)
    ---@class monitors_struct
    local monitors = {
        primary = nil,
        unit_displays = {}
    }

    local monitors_avail = ppm.get_monitor_list()
    local names = {}

    -- get all interface names
    for iface, _ in pairs(monitors_avail) do
        table.insert(names, iface)
    end

    -- we need a certain number of monitors (1 per unit + 1 primary display)
    if #names ~= num_units + 1 then
        println("not enough monitors connected (need " .. num_units + 1 .. ")")
        log.warning("insufficient monitors present (need " .. num_units + 1 .. ")")
        return false
    end

    -- attempt to load settings
    settings.load("/coord.settings")

    ---------------------
    -- PRIMARY DISPLAY --
    ---------------------

    local iface_primary_display = settings.get("PRIMARY_DISPLAY")

    if not util.table_contains(names, iface_primary_display) then
        println("primary display is not connected")
        local response = dialog.ask_y_n("would you like to change it", true)
        if response == false then return false end
        iface_primary_display = nil
    end

    while iface_primary_display == nil and #names > 0 do
        -- lets get a monitor
        iface_primary_display = ask_monitor(names)
    end

    if iface_primary_display == false then return false end

    settings.set("PRIMARY_DISPLAY", iface_primary_display)
    util.filter_table(names, function (x) return x ~= iface_primary_display end)

    monitors.primary = ppm.get_periph(iface_primary_display)

    -------------------
    -- UNIT DISPLAYS --
    -------------------

    local unit_displays = settings.get("UNIT_DISPLAYS")

    if unit_displays == nil then
        unit_displays = {}
        for i = 1, num_units do
            local display = nil

            while display == nil and #names > 0 do
                -- lets get a monitor
                println("please select monitor for unit " .. i)
                display = ask_monitor(names)
            end

            if display == false then return false end

            unit_displays[i] = display
        end
    else
        -- make sure all displays are connected
        for i = 1, num_units do
---@diagnostic disable-next-line: need-check-nil
            local display = unit_displays[i]

            if not util.table_contains(names, display) then
                local response = dialog.ask_y_n("unit display " .. i .. " is not connected, would you like to change it?", true)
                if response == false then return false end
                display = nil
            end

            while display == nil and #names > 0 do
                -- lets get a monitor
                display = ask_monitor(names)
            end

            if display == false then return false end

            unit_displays[i] = display
        end
    end

    settings.set("UNIT_DISPLAYS", unit_displays)
    settings.save("/coord.settings")

    for i = 1, #unit_displays do
        monitors.unit_displays[i] = ppm.get_periph(unit_displays[i])
    end

    return true, monitors
end

-- coordinator communications
function coordinator.coord_comms()
    local self = {
        reactor_struct_cache = nil
    }
end

return coordinator
