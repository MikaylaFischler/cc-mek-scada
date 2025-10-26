--
-- Reactor Programmable Logic Controller
--

require("/initenv").init_env()
local backplane = require("reactor-plc.backplane")

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

local R_PLC_VERSION = "v1.9.0"

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
            fp_ok = false,
            shutdown = false,
            degraded = true,
            reactor_formed = true,
            no_reactor = true,
            no_modem = true
        },

        -- control setpoints
        ---@class plc_setpoints
        setpoints = {
            burn_rate_en = false,
            burn_rate = 0.0
        },

        -- global PLC devices, still initialized by the backplane
        ---@class plc_dev
        plc_dev = {
            reactor = nil       ---@type table
        },

        -- system objects
        ---@class plc_sys
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

    -- reactor and modem initialization
    backplane.init(config, __shared_memory)

    -- scram on boot if networked, otherwise leave the reactor be
    if __shared_memory.networked and (not plc_state.no_reactor) and plc_state.reactor_formed and smem_dev.reactor.getStatus() then
        log.debug("startup> power-on SCRAM")
        smem_dev.reactor.scram()
    end

    -- setup front panel
    local message
    plc_state.fp_ok, message = renderer.try_start_ui(config.FrontPanelTheme, config.ColorMode)

    -- ...or not
    if not plc_state.fp_ok then
        println_ts(util.c("UI error: ", message))
        println("startup> running without front panel")
        log.error(util.c("front panel GUI render failed with error ", message))
        log.info("startup> running in headless mode without front panel")
    end

    -- print a log message to the terminal as long as the UI isn't running
    local function _println_no_fp(msg) if not plc_state.fp_ok then println(msg) end end

    ----------------------------------------
    -- initialize PLC
    ----------------------------------------

    -- init reactor protection system
    smem_sys.rps = plc.rps_init(smem_dev.reactor, util.trinary(plc_state.no_reactor, nil, plc_state.reactor_formed))
    log.debug("startup> rps init")

    -- notify user of emergency coolant configuration status
    if config.EmerCoolEnable then
        _println_no_fp("startup> emergency coolant control ready")
        log.info("startup> emergency coolant control available")
    end

    -- conditionally init comms
    if __shared_memory.networked then
        -- comms watchdog
        smem_sys.conn_watchdog = util.new_watchdog(config.ConnTimeout)
        log.debug("startup> conn watchdog started")

        -- create network interface then setup comms
        smem_sys.nic = backplane.active_nic()
        smem_sys.plc_comms = plc.comms(R_PLC_VERSION, smem_sys.nic, smem_dev.reactor, smem_sys.rps, smem_sys.conn_watchdog)
        log.debug("startup> comms init")
    else
        _println_no_fp("startup> starting in non-networked mode")
        log.info("startup> starting without networking")
    end

    databus.tx_hw_status(plc_state)

    _println_no_fp("startup> completed")
    log.info("startup> completed")

    -- init threads
    local main_thread = threads.thread__main(__shared_memory)
    local rps_thread  = threads.thread__rps(__shared_memory)

    if __shared_memory.networked then
        -- init comms threads
        local comms_thread_tx = threads.thread__comms_tx(__shared_memory)
        local comms_thread_rx = threads.thread__comms_rx(__shared_memory)

        -- setpoint control only needed when networked
        local sp_ctrl_thread = threads.thread__setpoint_control(__shared_memory)

        -- run threads
        parallel.waitForAll(main_thread.p_exec, rps_thread.p_exec, comms_thread_tx.p_exec, comms_thread_rx.p_exec, sp_ctrl_thread.p_exec)

        -- send status one last time after RPS shutdown
        smem_sys.plc_comms.send_status(plc_state.no_reactor, plc_state.reactor_formed)
        smem_sys.plc_comms.send_rps_status()

        -- close connection
        smem_sys.plc_comms.close()
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
