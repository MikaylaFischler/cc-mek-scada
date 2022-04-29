--
-- Reactor Programmable Logic Controller
--

os.loadAPI("scada-common/log.lua")
os.loadAPI("scada-common/util.lua")
os.loadAPI("scada-common/ppm.lua")
os.loadAPI("scada-common/comms.lua")
os.loadAPI("scada-common/mqueue.lua")

os.loadAPI("config.lua")
os.loadAPI("plc.lua")
os.loadAPI("threads.lua")

local R_PLC_VERSION = "alpha-v0.4.7"

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

log._info("========================================")
log._info("BOOTING reactor-plc.startup " .. R_PLC_VERSION)
log._info("========================================")
println(">> Reactor PLC " .. R_PLC_VERSION .. " <<")

-- mount connected devices
ppm.mount_all()

-- shared memory across threads
local __shared_memory = {
    -- networked setting
    networked = config.NETWORKED,

    -- PLC system state flags
    plc_state = {
        init_ok = true,
        shutdown = false,
        scram = true,
        degraded = false,
        no_reactor = false,
        no_modem = false
    },
    
    -- core PLC devices
    plc_dev = {
        reactor = ppm.get_fission_reactor(),
        modem = ppm.get_wireless_modem()
    },

    -- system objects
    plc_sys = {
        iss = nil,
        plc_comms = nil,
        conn_watchdog = nil
    },

    -- message queues
    q = {
        mq_iss = mqueue.new(),
        mq_comms_tx = mqueue.new(),
        mq_comms_rx = mqueue.new()
    }
}

local smem_dev = __shared_memory.plc_dev
local smem_sys = __shared_memory.plc_sys

local plc_state = __shared_memory.plc_state

-- we need a reactor and a modem
if smem_dev.reactor == nil then
    println("boot> fission reactor not found");
    log._warning("no reactor on startup")

    plc_state.init_ok = false
    plc_state.degraded = true
    plc_state.no_reactor = true
end
if networked and smem_dev.modem == nil then
    println("boot> wireless modem not found")
    log._warning("no wireless modem on startup")

    if smem_dev.reactor ~= nil then
        smem_dev.reactor.scram()
    end

    plc_state.init_ok = false
    plc_state.degraded = true
    plc_state.no_modem = true
end

function init()
    if plc_state.init_ok then
        -- just booting up, no fission allowed (neutrons stay put thanks)
        smem_dev.reactor.scram()

        -- init internal safety system
        smem_sys.iss = plc.iss_init(smem_dev.reactor)
        log._debug("iss init")

        if __shared_memory.networked then
            -- start comms
            smem_sys.plc_comms = plc.comms_init(config.REACTOR_ID, smem_dev.modem, config.LISTEN_PORT, config.SERVER_PORT, smem_dev.reactor, smem_sys.iss)
            log._debug("comms init")

            -- comms watchdog, 3 second timeout
            smem_sys.conn_watchdog = util.new_watchdog(3)
            log._debug("conn watchdog started")
        else
            println("boot> starting in offline mode");
            log._debug("running without networking")
        end

        os.queueEvent("clock_start")

        println("boot> completed");
    else
        println("boot> system in degraded state, awaiting devices...")
        log._warning("booted in a degraded state, awaiting peripheral connections...")
    end
end

-- initialize PLC
init()

-- init threads
local main_thread  = threads.thread__main(__shared_memory, init)
local iss_thread   = threads.thread__iss(__shared_memory)

if __shared_memory.networked then
    -- init comms threads
    local comms_thread_tx = threads.thread__comms_tx(__shared_memory)
    local comms_thread_rx = threads.thread__comms_rx(__shared_memory)

    -- run threads
    parallel.waitForAll(main_thread.exec, iss_thread.exec, comms_thread_tx.exec, comms_thread_rx.exec)
else
    -- run threads, excluding comms
    parallel.waitForAll(main_thread.exec, iss_thread.exec)
end

-- send an alarm: plc_comms.send_alarm(ALARMS.PLC_SHUTDOWN) ?
println_ts("exited")
log._info("exited")
