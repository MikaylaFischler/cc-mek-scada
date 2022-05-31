--
-- RTU: Remote Terminal Unit
--

require("/initenv").init_env()

local log    = require("scada-common.log")
local mqueue = require("scada-common.mqueue")
local ppm    = require("scada-common.ppm")
local rsio   = require("scada-common.rsio")
local types  = require("scada-common.types")
local util   = require("scada-common.util")

local config  = require("rtu.config")
local modbus  = require("rtu.modbus")
local rtu     = require("rtu.rtu")
local threads = require("rtu.threads")

local redstone_rtu      = require("rtu.dev.redstone_rtu")
local boiler_rtu        = require("rtu.dev.boiler_rtu")
local boilerv_rtu       = require("rtu.dev.boilerv_rtu")
local energymachine_rtu = require("rtu.dev.energymachine_rtu")
local imatrix_rtu       = require("rtu.dev.imatrix_rtu")
local turbine_rtu       = require("rtu.dev.turbine_rtu")
local turbinev_rtu      = require("rtu.dev.turbinev_rtu")

local RTU_VERSION = "beta-v0.7.4"

local rtu_t = types.rtu_t

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

log.init(config.LOG_PATH, config.LOG_MODE)

log.info("========================================")
log.info("BOOTING rtu.startup " .. RTU_VERSION)
log.info("========================================")
println(">> RTU " .. RTU_VERSION .. " <<")

----------------------------------------
-- startup
----------------------------------------

-- mount connected devices
ppm.mount_all()

---@class rtu_shared_memory
local __shared_memory = {
    -- RTU system state flags
    ---@class rtu_state
    rtu_state = {
        linked = false,
        shutdown = false
    },

    -- core RTU devices
    rtu_dev = {
        modem = ppm.get_wireless_modem()
    },

    -- system objects
    rtu_sys = {
        rtu_comms = nil,        ---@type rtu_comms
        conn_watchdog = nil,    ---@type watchdog
        units = {}              ---@type table
    },

    -- message queues
    q = {
        mq_comms = mqueue.new()
    }
}

local smem_dev = __shared_memory.rtu_dev
local smem_sys = __shared_memory.rtu_sys

-- get modem
if smem_dev.modem == nil then
    println("boot> wireless modem not found")
    log.fatal("no wireless modem on startup")
    return
end

----------------------------------------
-- interpret config and init units
----------------------------------------

local units = __shared_memory.rtu_sys.units

local rtu_redstone = config.RTU_REDSTONE
local rtu_devices = config.RTU_DEVICES

-- redstone interfaces
for entry_idx = 1, #rtu_redstone do
    local rs_rtu = redstone_rtu.new()
    local io_table = rtu_redstone[entry_idx].io
    local io_reactor = rtu_redstone[entry_idx].for_reactor

    local capabilities = {}

    log.debug("init> starting redstone RTU I/O linking for reactor " .. io_reactor .. "...")

    local continue = true

    for i = 1, #units do
        local unit = units[i]   ---@type rtu_unit_registry_entry
        if unit.reactor == io_reactor and unit.type == rtu_t.redstone then
            -- duplicate entry
            log.warning("init> skipping definition block #" .. entry_idx .. " for reactor " .. io_reactor .. " with already defined redstone I/O")
            continue = false
            break
        end
    end

    if continue then
        for i = 1, #io_table do
            local valid = false
            local conf = io_table[i]

            -- verify configuration
            if rsio.is_valid_channel(conf.channel) and rsio.is_valid_side(conf.side) then
                if conf.bundled_color then
                    valid = rsio.is_color(conf.bundled_color)
                else
                    valid = true
                end
            end

            if not valid then
                local message = "init> invalid redstone definition at index " .. i .. " in definition block #" .. entry_idx ..
                    " (for reactor " .. io_reactor .. ")"
                println_ts(message)
                log.warning(message)
            else
                -- link redstone in RTU
                local mode = rsio.get_io_mode(conf.channel)
                if mode == rsio.IO_MODE.DIGITAL_IN then
                    -- can't have duplicate inputs
                    if util.table_contains(capabilities, conf.channel) then
                        log.warning("init> skipping duplicate input for channel " .. rsio.to_string(conf.channel) .. " on side " .. conf.side)
                    else
                        rs_rtu.link_di(conf.side, conf.bundled_color)
                    end
                elseif mode == rsio.IO_MODE.DIGITAL_OUT then
                    rs_rtu.link_do(conf.channel, conf.side, conf.bundled_color)
                elseif mode == rsio.IO_MODE.ANALOG_IN then
                    -- can't have duplicate inputs
                    if util.table_contains(capabilities, conf.channel) then
                        log.warning("init> skipping duplicate input for channel " .. rsio.to_string(conf.channel) .. " on side " .. conf.side)
                    else
                        rs_rtu.link_ai(conf.side)
                    end
                elseif mode == rsio.IO_MODE.ANALOG_OUT then
                    rs_rtu.link_ao(conf.side)
                else
                    -- should be unreachable code, we already validated channels
                    log.error("init> fell through if chain attempting to identify IO mode", true)
                    break
                end

                table.insert(capabilities, conf.channel)

                log.debug("init> linked redstone " .. #capabilities .. ": " .. rsio.to_string(conf.channel) .. " (" .. conf.side ..
                    ") for reactor " .. io_reactor)
            end
        end

        ---@class rtu_unit_registry_entry
        local unit = {
            name = "redstone_io",
            type = rtu_t.redstone,
            index = entry_idx,
            reactor = io_reactor,
            device = capabilities,  -- use device field for redstone channels
            rtu = rs_rtu,
            modbus_io = modbus.new(rs_rtu, false),
            pkt_queue = nil,
            thread = nil
        }

        table.insert(units, unit)

        log.debug("init> initialized RTU unit #" .. #units .. ": redstone_io (redstone) [1] for reactor " .. io_reactor)
    end
end

-- mounted peripherals
for i = 1, #rtu_devices do
    local device = ppm.get_periph(rtu_devices[i].name)

    if device == nil then
        local message = "init> '" .. rtu_devices[i].name .. "' not found"
        println_ts(message)
        log.warning(message)
    else
        local type = ppm.get_type(rtu_devices[i].name)
        local rtu_iface = nil   ---@type rtu_device
        local rtu_type = ""

        if type == "boiler" then
            -- boiler multiblock
            rtu_type = rtu_t.boiler
            rtu_iface = boiler_rtu.new(device)
        elseif type == "boilerValve" then
            -- boiler multiblock (10.1+)
            rtu_type = rtu_t.boiler_valve
            rtu_iface = boilerv_rtu.new(device)
        elseif type == "turbine" then
            -- turbine multiblock
            rtu_type = rtu_t.turbine
            rtu_iface = turbine_rtu.new(device)
        elseif type == "turbineValve" then
            -- turbine multiblock (10.1+)
            rtu_type = rtu_t.turbine_valve
            rtu_iface = turbinev_rtu.new(device)
        elseif type == "mekanismMachine" then
            -- assumed to be an induction matrix multiblock, pre Mekanism 10.1
            -- also works with energy cubes
            rtu_type = rtu_t.energy_machine
            rtu_iface = energymachine_rtu.new(device)
        elseif type == "inductionPort" then
            -- induction matrix multiblock (10.1+)
            rtu_type = rtu_t.induction_matrix
            rtu_iface = imatrix_rtu.new(device)
        else
            local message = "init> device '" .. rtu_devices[i].name .. "' is not a known type (" .. type .. ")"
            println_ts(message)
            log.warning(message)
        end

        if rtu_iface ~= nil then
            ---@class rtu_unit_registry_entry
            local rtu_unit = {
                name = rtu_devices[i].name,
                type = rtu_type,
                index = rtu_devices[i].index,
                reactor = rtu_devices[i].for_reactor,
                device = device,
                rtu = rtu_iface,
                modbus_io = modbus.new(rtu_iface, true),
                pkt_queue = mqueue.new(),
                thread = nil
            }

            rtu_unit.thread = threads.thread__unit_comms(__shared_memory, rtu_unit)

            table.insert(units, rtu_unit)

            log.debug("init> initialized RTU unit #" .. #units .. ": " .. rtu_devices[i].name .. " (" .. rtu_type .. ") [" ..
                rtu_devices[i].index .. "] for reactor " .. rtu_devices[i].for_reactor)
        end
    end
end

----------------------------------------
-- start system
----------------------------------------

-- start connection watchdog
smem_sys.conn_watchdog = util.new_watchdog(5)
log.debug("boot> conn watchdog started")

-- setup comms
smem_sys.rtu_comms = rtu.comms(RTU_VERSION, smem_dev.modem, config.LISTEN_PORT, config.SERVER_PORT, smem_sys.conn_watchdog)
log.debug("boot> comms init")

-- init threads
local main_thread  = threads.thread__main(__shared_memory)
local comms_thread = threads.thread__comms(__shared_memory)

-- assemble thread list
local _threads = { main_thread.p_exec, comms_thread.p_exec }
for i = 1, #units do
    if units[i].thread ~= nil then
        table.insert(_threads, units[i].thread.p_exec)
    end
end

-- run threads
parallel.waitForAll(table.unpack(_threads))

println_ts("exited")
log.info("exited")
