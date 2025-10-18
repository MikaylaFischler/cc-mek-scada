--
-- RTU Gateway: Remote Terminal Unit Gateway
--

require("/initenv").init_env()

local audio     = require("scada-common.audio")
local comms     = require("scada-common.comms")
local crash     = require("scada-common.crash")
local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local network   = require("scada-common.network")
local ppm       = require("scada-common.ppm")
local util      = require("scada-common.util")

local backplane = require("rtu.backplane")
local configure = require("rtu.configure")
local databus   = require("rtu.databus")
local renderer  = require("rtu.renderer")
local rtu       = require("rtu.rtu")
local threads   = require("rtu.threads")
local uinit     = require("rtu.uinit")

local RTU_VERSION = "v1.13.0"

local println = util.println
local println_ts = util.println_ts

----------------------------------------
-- get configuration
----------------------------------------

if not rtu.load_config() then
    -- try to reconfigure (user action)
    local success, error = configure.configure(true)
    if success then
        if not rtu.load_config() then
            println("failed to load a valid configuration, please reconfigure")
            return
        end
    else
        println("configuration error: " .. error)
        return
    end
end

local config = rtu.config

----------------------------------------
-- log init
----------------------------------------

log.init(config.LogPath, config.LogMode, config.LogDebug)

log.info("========================================")
log.info("BOOTING rtu.startup " .. RTU_VERSION)
log.info("========================================")
println(">> RTU GATEWAY " .. RTU_VERSION .. " <<")

crash.set_env("rtu", RTU_VERSION)
crash.dbg_log_env()

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- startup
    ----------------------------------------

    -- record firmware versions and ID
    databus.tx_versions(RTU_VERSION, comms.version)

    -- mount connected devices
    ppm.mount_all()

    -- message authentication init
    if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
        network.init_mac(config.AuthKey)
    end

    -- generate alarm tones
    audio.generate_tones()

    ---@class rtu_shared_memory
    local __shared_memory = {
        -- RTU system state flags
        ---@class rtu_state
        rtu_state = {
            fp_ok = false,
            linked = false,
            shutdown = false
        },

        -- system objects
        ---@class rtu_sys 
        rtu_sys = {
            rtu_comms = nil,     ---@type rtu_comms
            conn_watchdog = nil, ---@type watchdog
            units = {}           ---@type rtu_registry_entry[]
        },

        -- message queues
        q = {
            mq_comms = mqueue.new()
        }
    }

    local smem_sys  = __shared_memory.rtu_sys
    local rtu_state = __shared_memory.rtu_state
    local units     = __shared_memory.rtu_sys.units

    ----------------------------------------
    -- start system
    ----------------------------------------

    log.debug("boot> running uinit()")

    if uinit(config, __shared_memory) then
        -- init backplane peripherals
        backplane.init(config, __shared_memory)

        -- start UI
        local message
        rtu_state.fp_ok, message = renderer.try_start_ui(units, config.FrontPanelTheme, config.ColorMode)

        if not rtu_state.fp_ok then
            println_ts(util.c("UI error: ", message))
            println("startup> running without front panel")
            log.error(util.c("front panel GUI render failed with error ", message))
            log.info("startup> running in headless mode without front panel")
        end

        -- start connection watchdog
        smem_sys.conn_watchdog = util.new_watchdog(config.ConnTimeout)
        log.debug("startup> conn watchdog started")

        -- setup comms
        local nic = backplane.active_nic()
        smem_sys.rtu_comms = rtu.comms(RTU_VERSION, nic, smem_sys.conn_watchdog)
        if nic then
            log.debug("startup> comms init")
        else
            log.warning("startup> no comms modem on startup")
        end

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

        log.info("startup> completed")

        -- run threads
        parallel.waitForAll(table.unpack(_threads))
    else
        println("system initialization failed, exiting...")
    end

    renderer.close_ui()

    println_ts("exited")
    log.info("exited")
end

if not xpcall(main, crash.handler) then
    pcall(renderer.close_ui)
    crash.exit()
else
    log.close()
end
