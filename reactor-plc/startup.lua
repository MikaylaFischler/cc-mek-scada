--
-- Reactor Programmable Logic Controller
--

require("/initenv").init_env()

local comms     = require("scada-common.comms")
local crash     = require("scada-common.crash")
local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local network   = require("scada-common.network")
local ppm       = require("scada-common.ppm")
local util      = require("scada-common.util")

local configure = require("reactor-plc.configure")
local databus   = require("reactor-plc.databus")
local plc       = require("reactor-plc.plc")
local renderer  = require("reactor-plc.renderer")
local threads   = require("reactor-plc.threads")

local R_PLC_VERSION = "v1.8.19"

local println = util.println
local println_ts = util.println_ts

----------------------------------------
-- get configuration
----------------------------------------

if not plc.load_config() then
    -- try to reconfigure (user action)
    local success, error = configure.configure(true)
    if success then
        if not plc.load_config() then
            println("failed to load a valid configuration, please reconfigure")
            return
        end
    else
        println("configuration error: " .. error)
        return
    end
end

local config = plc.config

----------------------------------------
-- log init
----------------------------------------

log.init(config.LogPath, config.LogMode, config.LogDebug)

log.info("========================================")
log.info("BOOTING reactor-plc.startup " .. R_PLC_VERSION)
log.info("========================================")
println(">> Reactor PLC " .. R_PLC_VERSION .. " <<")

crash.set_env("reactor-plc", R_PLC_VERSION)
crash.dbg_log_env()

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- startup
    ----------------------------------------

    -- record firmware versions and ID
    databus.tx_versions(R_PLC_VERSION, comms.version)
    databus.tx_id(config.UnitID)

    -- mount connected devices
    ppm.mount_all()

    -- message authentication init
    if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
        network.init_mac(config.AuthKey)
    end

    -- shared memory across threads
    ---@class plc_shared_memory
    local __shared_memory = {
        -- networked setting
        networked = config.Networked,

        -- PLC system state flags
        ---@class plc_state
        plc_state = {
            init_ok = true,
            fp_ok = false,
            shutdown = false,
            degraded = true,
            reactor_formed = true,
            no_reactor = true,
            no_modem = true
        },

        -- control setpoints
        ---@class setpoints
        setpoints = {
            burn_rate_en = false,
            burn_rate = 0.0
        },

        -- core PLC devices
        plc_dev = {
            reactor = ppm.get_fission_reactor(),
            modem = ppm.get_wireless_modem()
        },

        -- system objects
        plc_sys = {
            rps = nil,          ---@type rps
            nic = nil,          ---@type nic
            plc_comms = nil,    ---@type plc_comms
            conn_watchdog = nil ---@type watchdog
        },

        -- message queues
        q = {
            mq_rps = mqueue.new(),
            mq_comms_tx = mqueue.new(),
            mq_comms_rx = mqueue.new()
        }
    }

    local smem_dev = __shared_memory.plc_dev
    local smem_sys = __shared_memory.plc_sys

    local plc_state = __shared_memory.plc_state

    -- initial state evaluation
    plc_state.no_reactor = smem_dev.reactor == nil
    plc_state.no_modem = smem_dev.modem == nil

    -- we need a reactor, can at least do some things even if it isn't formed though
    if plc_state.no_reactor then
        println("init> fission reactor not found")
        log.warning("init> no reactor on startup")

        plc_state.init_ok = false
        plc_state.degraded = true
    elseif not smem_dev.reactor.isFormed() then
        println("init> fission reactor is not formed")
        log.warning("init> reactor logic adapter present, but reactor is not formed")

        plc_state.degraded = true
        plc_state.reactor_formed = false
    end

    -- modem is required if networked
    if __shared_memory.networked and plc_state.no_modem then
        println("init> wireless modem not found")
        log.warning("init> no wireless modem on startup")

        -- scram reactor if present and enabled
        if (smem_dev.reactor ~= nil) and plc_state.reactor_formed and smem_dev.reactor.getStatus() then
            smem_dev.reactor.scram()
        end

        plc_state.init_ok = false
        plc_state.degraded = true
    end

    -- print a log message to the terminal as long as the UI isn't running
    local function _println_no_fp(message) if not plc_state.fp_ok then println(message) end end

    -- PLC init<br>
    --- EVENT_CONSUMER: this function consumes events
    local function init()
        -- scram on boot if networked, otherwise leave the reactor be
        if __shared_memory.networked and (not plc_state.no_reactor) and plc_state.reactor_formed and smem_dev.reactor.getStatus() then
            smem_dev.reactor.scram()
        end

        -- setup front panel
        if not renderer.ui_ready() then
            local message
            plc_state.fp_ok, message = renderer.try_start_ui(config.FrontPanelTheme, config.ColorMode)

            -- ...or not
            if not plc_state.fp_ok then
                println_ts(util.c("UI error: ", message))
                println("init> running without front panel")
                log.error(util.c("front panel GUI render failed with error ", message))
                log.info("init> running in headless mode without front panel")
            end
        end

        if plc_state.init_ok then
            -- init reactor protection system
            smem_sys.rps = plc.rps_init(smem_dev.reactor, plc_state.reactor_formed)
            log.debug("init> rps init")

            if __shared_memory.networked then
                -- comms watchdog
                smem_sys.conn_watchdog = util.new_watchdog(config.ConnTimeout)
                log.debug("init> conn watchdog started")

                -- create network interface then setup comms
                smem_sys.nic = network.nic(smem_dev.modem)
                smem_sys.plc_comms = plc.comms(R_PLC_VERSION, smem_sys.nic, smem_dev.reactor, smem_sys.rps, smem_sys.conn_watchdog)
                log.debug("init> comms init")
            else
                _println_no_fp("init> starting in offline mode")
                log.info("init> running without networking")
            end

            -- notify user of emergency coolant configuration status
            if config.EmerCoolEnable then
                println("init> emergency coolant control ready")
                log.info("init> running with emergency coolant control available")
            end

            util.push_event("clock_start")

            _println_no_fp("init> completed")
            log.info("init> startup completed")
        else
            _println_no_fp("init> system in degraded state, awaiting devices...")
            log.warning("init> started in a degraded state, awaiting peripheral connections...")
        end

        databus.tx_hw_status(plc_state)
    end

    ----------------------------------------
    -- start system
    ----------------------------------------

    -- initialize PLC
    init()

    -- init threads
    local main_thread = threads.thread__main(__shared_memory, init)
    local rps_thread  = threads.thread__rps(__shared_memory)

    if __shared_memory.networked then
        -- init comms threads
        local comms_thread_tx = threads.thread__comms_tx(__shared_memory)
        local comms_thread_rx = threads.thread__comms_rx(__shared_memory)

        -- setpoint control only needed when networked
        local sp_ctrl_thread = threads.thread__setpoint_control(__shared_memory)

        -- run threads
        parallel.waitForAll(main_thread.p_exec, rps_thread.p_exec, comms_thread_tx.p_exec, comms_thread_rx.p_exec, sp_ctrl_thread.p_exec)

        if plc_state.init_ok then
            -- send status one last time after RPS shutdown
            smem_sys.plc_comms.send_status(plc_state.no_reactor, plc_state.reactor_formed)
            smem_sys.plc_comms.send_rps_status()

            -- close connection
            smem_sys.plc_comms.close()
        end
    else
        -- run threads, excluding comms
        parallel.waitForAll(main_thread.p_exec, rps_thread.p_exec)
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
