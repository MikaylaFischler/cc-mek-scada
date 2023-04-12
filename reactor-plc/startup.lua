--
-- Reactor Programmable Logic Controller
--

require("/initenv").init_env()

local comms    = require("scada-common.comms")
local crash    = require("scada-common.crash")
local log      = require("scada-common.log")
local mqueue   = require("scada-common.mqueue")
local ppm      = require("scada-common.ppm")
local rsio     = require("scada-common.rsio")
local util     = require("scada-common.util")

local config   = require("reactor-plc.config")
local databus  = require("reactor-plc.databus")
local plc      = require("reactor-plc.plc")
local renderer = require("reactor-plc.renderer")
local threads  = require("reactor-plc.threads")

local R_PLC_VERSION = "v1.1.5"

local println = util.println
local println_ts = util.println_ts

----------------------------------------
-- config validation
----------------------------------------

local cfv = util.new_validator()

cfv.assert_type_bool(config.NETWORKED)
cfv.assert_type_int(config.REACTOR_ID)
cfv.assert_port(config.SERVER_PORT)
cfv.assert_port(config.LISTEN_PORT)
cfv.assert_type_int(config.TRUSTED_RANGE)
cfv.assert_type_num(config.COMMS_TIMEOUT)
cfv.assert_min(config.COMMS_TIMEOUT, 2)
cfv.assert_type_str(config.LOG_PATH)
cfv.assert_type_int(config.LOG_MODE)

assert(cfv.valid(), "bad config file: missing/invalid fields")

-- check emergency coolant configuration
if type(config.EMERGENCY_COOL) == "table" then
    if not rsio.is_valid_side(config.EMERGENCY_COOL.side) then
        assert(false, "bad config file: emergency coolant side unrecognized")
    elseif config.EMERGENCY_COOL.color ~= nil and not rsio.is_color(config.EMERGENCY_COOL.color) then
        assert(false, "bad config file: emergency coolant invalid redstone channel color provided")
    end
end

----------------------------------------
-- log init
----------------------------------------

log.init(config.LOG_PATH, config.LOG_MODE)

log.info("========================================")
log.info("BOOTING reactor-plc.startup " .. R_PLC_VERSION)
log.info("========================================")
println(">> Reactor PLC " .. R_PLC_VERSION .. " <<")

crash.set_env("plc", R_PLC_VERSION)

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- startup
    ----------------------------------------

    -- record firmware versions and ID
    databus.tx_versions(R_PLC_VERSION, comms.version)
    databus.tx_id(config.REACTOR_ID)

    -- mount connected devices
    ppm.mount_all()

    -- shared memory across threads
    ---@class plc_shared_memory
    local __shared_memory = {
        -- networked setting
        networked = config.NETWORKED,   ---@type boolean

        -- PLC system state flags
        ---@class plc_state
        plc_state = {
            init_ok = true,
            fp_ok = false,
            shutdown = false,
            degraded = false,
            reactor_formed = true,
            no_reactor = false,
            no_modem = false
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
            rps = nil,              ---@type rps
            plc_comms = nil,        ---@type plc_comms
            conn_watchdog = nil     ---@type watchdog
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

    -- we need a reactor, can at least do some things even if it isn't formed though
    if smem_dev.reactor == nil then
        println("init> fission reactor not found");
        log.warning("init> no reactor on startup")

        plc_state.init_ok = false
        plc_state.degraded = true
        plc_state.no_reactor = true
    elseif not smem_dev.reactor.isFormed() then
        println("init> fission reactor not formed");
        log.warning("init> reactor logic adapter present, but reactor is not formed")

        plc_state.degraded = true
        plc_state.reactor_formed = false
    end

    -- modem is required if networked
    if __shared_memory.networked and smem_dev.modem == nil then
        println("init> wireless modem not found")
        log.warning("init> no wireless modem on startup")

        -- scram reactor if present and enabled
        if (smem_dev.reactor ~= nil) and plc_state.reactor_formed and smem_dev.reactor.getStatus() then
            smem_dev.reactor.scram()
        end

        plc_state.init_ok = false
        plc_state.degraded = true
        plc_state.no_modem = true
    end

    -- print a log message to the terminal as long as the UI isn't running
    local function _println_no_fp(message) if not plc_state.fp_ok then println(message) end end

    -- PLC init<br>
    --- EVENT_CONSUMER: this function consumes events
    local function init()
        -- just booting up, no fission allowed (neutrons stay put thanks)
        if (not plc_state.no_reactor) and plc_state.reactor_formed and smem_dev.reactor.getStatus() then
            smem_dev.reactor.scram()
        end

        -- front panel time!
        if not renderer.ui_ready() then
            local message
            plc_state.fp_ok, message = pcall(renderer.start_ui)

            if not plc_state.fp_ok then
                renderer.close_ui()
                println_ts(util.c("UI error: ", message))
                println("init> running without front panel")
                log.error(util.c("GUI crashed with error ", message))
                log.info("init> running in headless mode without front panel")
            end
        end

        if plc_state.init_ok then
            -- init reactor protection system
            smem_sys.rps = plc.rps_init(smem_dev.reactor, plc_state.reactor_formed, config.EMERGENCY_COOL)
            log.debug("init> rps init")

            if __shared_memory.networked then
                -- comms watchdog
                smem_sys.conn_watchdog = util.new_watchdog(config.COMMS_TIMEOUT)
                log.debug("init> conn watchdog started")

                -- start comms
                smem_sys.plc_comms = plc.comms(config.REACTOR_ID, R_PLC_VERSION, smem_dev.modem, config.LISTEN_PORT, config.SERVER_PORT,
                                                config.TRUSTED_RANGE, smem_dev.reactor, smem_sys.rps, smem_sys.conn_watchdog)
                log.debug("init> comms init")
            else
                _println_no_fp("init> starting in offline mode")
                log.info("init> running without networking")
            end

            -- notify user of emergency coolant configuration status
            if config.EMERGENCY_COOL ~= nil then
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

if not xpcall(main, crash.handler) then crash.exit() end
