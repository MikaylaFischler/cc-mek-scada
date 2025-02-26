--
-- Nuclear Generation Facility SCADA Coordinator
--

require("/initenv").init_env()

local comms       = require("scada-common.comms")
local crash       = require("scada-common.crash")
local log         = require("scada-common.log")
local mqueue      = require("scada-common.mqueue")
local network     = require("scada-common.network")
local ppm         = require("scada-common.ppm")
local util        = require("scada-common.util")

local configure   = require("coordinator.configure")
local coordinator = require("coordinator.coordinator")
local iocontrol   = require("coordinator.iocontrol")
local renderer    = require("coordinator.renderer")
local sounder     = require("coordinator.sounder")
local threads     = require("coordinator.threads")

local COORDINATOR_VERSION = "v1.6.11"

local CHUNK_LOAD_DELAY_S = 30.0

local println    = util.println
local println_ts = util.println_ts

local log_render = coordinator.log_render
local log_sys    = coordinator.log_sys
local log_boot   = coordinator.log_boot
local log_comms  = coordinator.log_comms
local log_crypto = coordinator.log_crypto

----------------------------------------
-- get configuration
----------------------------------------

-- mount connected devices (required for monitor setup)
ppm.mount_all()

local wait_on_load = true
local loaded, monitors = coordinator.load_config()

-- if the computer just started, its chunk may have just loaded (...or the user rebooted)
-- if monitor config failed, maybe an adjacent chunk containing all or part of a monitor has not loaded yet, so keep trying
while wait_on_load and loaded == 2 and os.clock() < CHUNK_LOAD_DELAY_S do
    term.clear()
    term.setCursorPos(1, 1)
    println("There was a monitor configuration problem at boot.\n")
    println("Startup will keep trying every 2s in case of chunk load delays.\n")
    println(util.sprintf("The configurator will be started in %ds if all attempts fail.\n", math.max(0, CHUNK_LOAD_DELAY_S - os.clock())))
    println("(click to skip to the configurator)")

    local timer_id = util.start_timer(2)

    while true do
        local event, param1 = util.pull_event()
        if event == "timer" and param1 == timer_id then
            -- remount and re-attempt
            ppm.mount_all()
            loaded, monitors = coordinator.load_config()
            break
        elseif event == "mouse_click" or event == "terminate" then
            wait_on_load = false
            break
        end
    end
end

if loaded ~= 0 then
    -- try to reconfigure (user action)
    local success, error = configure.configure(loaded, monitors)
    if success then
        loaded, monitors = coordinator.load_config()
        if loaded ~= 0 then
            println(util.trinary(loaded == 2, "monitor configuration invalid", "failed to load a valid configuration") .. ", please reconfigure")
            return
        end
    else
        println("configuration error: " .. error)
        return
    end
end

-- passed checks, good now
---@cast monitors monitors_struct

local config = coordinator.config

----------------------------------------
-- log init
----------------------------------------

log.init(config.LogPath, config.LogMode, config.LogDebug)

log.info("========================================")
log.info("BOOTING coordinator.startup " .. COORDINATOR_VERSION)
log.info("========================================")
println(">> SCADA Coordinator " .. COORDINATOR_VERSION .. " <<")

crash.set_env("coordinator", COORDINATOR_VERSION)
crash.dbg_log_env()

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- system startup
    ----------------------------------------

    -- log mounts now since mounting was done before logging was ready
    ppm.log_mounts()

    -- report versions/init fp PSIL
    iocontrol.init_fp(COORDINATOR_VERSION, comms.version)

    -- init renderer
    renderer.configure(config)
    renderer.set_displays(monitors)
    renderer.init_displays()
    renderer.init_dmesg()

    -- lets get started!
    log.info("monitors ready, dmesg output incoming...")

    log_render("displays connected and reset")
    log_sys("system start on " .. os.date("%c"))
    log_boot("starting " .. COORDINATOR_VERSION)

    ----------------------------------------
    -- memory allocation
    ----------------------------------------

    -- shared memory across threads
    ---@class crd_shared_memory
    local __shared_memory = {
        -- time and date format for display
        date_format = util.trinary(config.Time24Hour, "%X \x04 %A, %B %d %Y", "%r \x04 %A, %B %d %Y"),

        -- coordinator system state flags
        ---@class crd_state
        crd_state = {
            fp_ok = false,
            ui_ok = true,       -- default true, used to abort on fail
            link_fail = false,
            shutdown = false
        },

        -- core coordinator devices
        crd_dev = {
            modem = ppm.get_wireless_modem(),
            speaker = ppm.get_device("speaker") ---@type Speaker|nil
        },

        -- system objects
        crd_sys = {
            nic = nil,          ---@type nic
            coord_comms = nil,  ---@type coord_comms
            conn_watchdog = nil ---@type watchdog
        },

        -- message queues
        q = {
            mq_render = mqueue.new()
        }
    }

    local smem_dev = __shared_memory.crd_dev
    local smem_sys = __shared_memory.crd_sys

    local crd_state = __shared_memory.crd_state

    ----------------------------------------
    -- setup alarm sounder subsystem
    ----------------------------------------

    if smem_dev.speaker == nil then
        log_boot("annunciator alarm speaker not found")
        println("startup> speaker not found")
        log.fatal("no annunciator alarm speaker found")
        return
    else
        local sounder_start = util.time_ms()
        log_boot("annunciator alarm speaker connected")
        sounder.init(smem_dev.speaker, config.SpeakerVolume)
        log_boot("tone generation took " .. (util.time_ms() - sounder_start) .. "ms")
        log_sys("annunciator alarm configured")
        iocontrol.fp_has_speaker(true)
    end

    ----------------------------------------
    -- setup communications
    ----------------------------------------

    -- message authentication init
    if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
        local init_time = network.init_mac(config.AuthKey)
        log_crypto("HMAC init took " .. init_time .. "ms")
    end

    -- get the communications modem
    if smem_dev.modem == nil then
        log_comms("wireless modem not found")
        println("startup> wireless modem not found")
        log.fatal("no wireless modem on startup")
        return
    else
        log_comms("wireless modem connected")
        iocontrol.fp_has_modem(true)
    end

    -- create connection watchdog
    smem_sys.conn_watchdog = util.new_watchdog(config.SVR_Timeout)
    smem_sys.conn_watchdog.cancel()
    log.debug("startup> conn watchdog created")

    -- create network interface then setup comms
    smem_sys.nic = network.nic(smem_dev.modem)
    smem_sys.coord_comms = coordinator.comms(COORDINATOR_VERSION, smem_sys.nic, smem_sys.conn_watchdog)
    log.debug("startup> comms init")
    log_comms("comms initialized")

    ----------------------------------------
    -- start front panel
    ----------------------------------------

    log_render("starting front panel UI...")

    local fp_message
    crd_state.fp_ok, fp_message = renderer.try_start_fp()
    if not crd_state.fp_ok then
        log_render(util.c("front panel UI error: ", fp_message))
        println_ts("front panel UI creation failed")
        log.fatal(util.c("front panel GUI render failed with error ", fp_message))
        return
    else log_render("front panel ready") end

    ----------------------------------------
    -- start system
    ----------------------------------------

    -- init threads
    local main_thread   = threads.thread__main(__shared_memory)
    local render_thread = threads.thread__render(__shared_memory)

    log.info("startup> completed")

    -- run threads
    parallel.waitForAll(main_thread.p_exec, render_thread.p_exec)

    renderer.close_ui()
    renderer.close_fp()
    sounder.stop()
    log_sys("system shutdown")

    if crd_state.link_fail then println_ts("failed to connect to supervisor") end
    if not crd_state.ui_ok then println_ts("main UI creation failed") end

    -- close on error exit (such as UI error)
    if smem_sys.coord_comms.is_linked() then smem_sys.coord_comms.close() end

    println_ts("exited")
    log.info("exited")
end

if not xpcall(main, crash.handler) then
    pcall(renderer.close_ui)
    pcall(renderer.close_fp)
    pcall(sounder.stop)
    crash.exit()
else
    log.close()
end
