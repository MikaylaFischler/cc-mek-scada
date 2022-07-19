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
local envd_rtu          = require("rtu.dev.envd_rtu")
local imatrix_rtu       = require("rtu.dev.imatrix_rtu")
local turbine_rtu       = require("rtu.dev.turbine_rtu")
local turbinev_rtu      = require("rtu.dev.turbinev_rtu")

local RTU_VERSION = "beta-v0.7.10"

local rtu_t = types.rtu_t

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

----------------------------------------
-- config validation
----------------------------------------

local cfv = util.new_validator()

cfv.assert_port(config.SERVER_PORT)
cfv.assert_port(config.LISTEN_PORT)
cfv.assert_type_str(config.LOG_PATH)
cfv.assert_type_int(config.LOG_MODE)
cfv.assert_type_table(config.RTU_DEVICES)
cfv.assert_type_table(config.RTU_REDSTONE)
assert(cfv.valid(), "bad config file: missing/invalid fields")

----------------------------------------
-- log init
----------------------------------------

log.init(config.LOG_PATH, config.LOG_MODE)

log.info("========================================")
log.info("BOOTING rtu.startup " .. RTU_VERSION)
log.info("========================================")
println(">> RTU GATEWAY " .. RTU_VERSION .. " <<")

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

-- configure RTU gateway based on config file definitions
local function configure()
    -- redstone interfaces
    for entry_idx = 1, #rtu_redstone do
        local rs_rtu = redstone_rtu.new()
        local io_table = rtu_redstone[entry_idx].io
        local io_reactor = rtu_redstone[entry_idx].for_reactor

        -- CHECK: reactor ID must be >= to 1
        if (not util.is_int(io_reactor)) or (io_reactor <= 0) then
            println(util.c("configure> redstone entry #", entry_idx, " : ", io_reactor, " isn't an integer >= 1"))
            return false
        end

        -- CHECK: io table exists
        if type(io_table) ~= "table" then
            println(util.c("configure> redstone entry #", entry_idx, " no IO table found"))
            return false
        end

        local capabilities = {}

        log.debug(util.c("configure> starting redstone RTU I/O linking for reactor ", io_reactor, "..."))

        local continue = true

        -- check for duplicate entries
        for i = 1, #units do
            local unit = units[i]   ---@type rtu_unit_registry_entry
            if unit.reactor == io_reactor and unit.type == rtu_t.redstone then
                -- duplicate entry
                local message = util.c("configure> skipping definition block #", entry_idx, " for reactor ", io_reactor,
                    " with already defined redstone I/O")
                println(message)
                log.warning(message)
                continue = false
                break
            end
        end

        -- not a duplicate
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
                    local message = util.c("configure> invalid redstone definition at index ", i, " in definition block #", entry_idx,
                        " (for reactor ", io_reactor, ")")
                    println(message)
                    log.error(message)
                    return false
                else
                    -- link redstone in RTU
                    local mode = rsio.get_io_mode(conf.channel)
                    if mode == rsio.IO_MODE.DIGITAL_IN then
                        -- can't have duplicate inputs
                        if util.table_contains(capabilities, conf.channel) then
                            local message = util.c("configure> skipping duplicate input for channel ", rsio.to_string(conf.channel), " on side ", conf.side)
                            println(message)
                            log.warning(message)
                        else
                            rs_rtu.link_di(conf.side, conf.bundled_color)
                        end
                    elseif mode == rsio.IO_MODE.DIGITAL_OUT then
                        rs_rtu.link_do(conf.channel, conf.side, conf.bundled_color)
                    elseif mode == rsio.IO_MODE.ANALOG_IN then
                        -- can't have duplicate inputs
                        if util.table_contains(capabilities, conf.channel) then
                            local message = util.c("configure> skipping duplicate input for channel ", rsio.to_string(conf.channel), " on side ", conf.side)
                            println(message)
                            log.warning(message)
                        else
                            rs_rtu.link_ai(conf.side)
                        end
                    elseif mode == rsio.IO_MODE.ANALOG_OUT then
                        rs_rtu.link_ao(conf.side)
                    else
                        -- should be unreachable code, we already validated channels
                        log.error("configure> fell through if chain attempting to identify IO mode", true)
                        println("configure> encountered a software error, check logs")
                        return false
                    end

                    table.insert(capabilities, conf.channel)

                    log.debug(util.c("configure> linked redstone ", #capabilities, ": ", rsio.to_string(conf.channel),
                        " (", conf.side, ") for reactor ", io_reactor))
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

            log.debug(util.c("init> initialized RTU unit #", #units, ": redstone_io (redstone) [1] for reactor ", io_reactor))
        end
    end

    -- mounted peripherals
    for i = 1, #rtu_devices do
        local name = rtu_devices[i].name
        local index = rtu_devices[i].index
        local for_reactor = rtu_devices[i].for_reactor

        -- CHECK: name is a string
        if type(name) ~= "string" then
            println(util.c("configure> device entry #", i, ": device ", name, " isn't a string"))
            return false
        end

        -- CHECK: index is an integer >= 1
        if (not util.is_int(index)) or (index <= 0) then
            println(util.c("configure> device entry #", i, ": index ", index, " isn't an integer >= 1"))
            return false
        end

        -- CHECK: reactor is an integer >= 1
        if (not util.is_int(for_reactor)) or (for_reactor <= 0) then
            println(util.c("configure> device entry #", i, ": reactor ", for_reactor, " isn't an integer >= 1"))
            return false
        end

        local device = ppm.get_periph(name)

        if device == nil then
            local message = util.c("configure> '", name, "' not found")
            println(message)
            log.fatal(message)
            return false
        else
            local type = ppm.get_type(name)
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
            elseif type == "environmentDetector" then
                -- advanced peripherals environment detector
                rtu_type = rtu_t.env_detector
                rtu_iface = envd_rtu.new(device)
            else
                local message = util.c("configure> device '", name, "' is not a known type (", type, ")")
                println_ts(message)
                log.fatal(message)
                return false
            end

            if rtu_iface ~= nil then
                ---@class rtu_unit_registry_entry
                local rtu_unit = {
                    name = name,
                    type = rtu_type,
                    index = index,
                    reactor = for_reactor,
                    device = device,
                    rtu = rtu_iface,
                    modbus_io = modbus.new(rtu_iface, true),
                    pkt_queue = mqueue.new(),
                    thread = nil
                }

                rtu_unit.thread = threads.thread__unit_comms(__shared_memory, rtu_unit)

                table.insert(units, rtu_unit)

                log.debug(util.c("configure> initialized RTU unit #", #units, ": ", name, " (", rtu_type, ") [", index, "] for reactor ", for_reactor))
            end
        end
    end

    -- we made it through all that trusting-user-to-write-a-config-file chaos
    return true
end

----------------------------------------
-- start system
----------------------------------------

log.debug("boot> running configure()")

if configure() then
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
else
    println("configuration failed, exiting...")
end

println_ts("exited")
log.info("exited")
