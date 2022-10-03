--
-- Nuclear Generation Facility SCADA Coordinator
--

require("/initenv").init_env()

local log          = require("scada-common.log")
local ppm          = require("scada-common.ppm")
local tcallbackdsp = require("scada-common.tcallbackdsp")
local util         = require("scada-common.util")

local core         = require("graphics.core")

local apisessions  = require("coordinator.apisessions")
local config       = require("coordinator.config")
local coordinator  = require("coordinator.coordinator")
local renderer     = require("coordinator.renderer")

local COORDINATOR_VERSION = "alpha-v0.5.0"

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local log_graphics = coordinator.log_graphics
local log_sys = coordinator.log_sys
local log_boot = coordinator.log_boot
local log_comms = coordinator.log_comms
local log_comms_connecting = coordinator.log_comms_connecting

----------------------------------------
-- config validation
----------------------------------------

local cfv = util.new_validator()

cfv.assert_port(config.SCADA_SV_PORT)
cfv.assert_port(config.SCADA_SV_LISTEN)
cfv.assert_port(config.SCADA_API_LISTEN)
cfv.assert_type_int(config.NUM_UNITS)
cfv.assert_type_bool(config.RECOLOR)
cfv.assert_type_str(config.LOG_PATH)
cfv.assert_type_int(config.LOG_MODE)
cfv.assert_type_bool(config.SECURE)
cfv.assert_type_str(config.PASSWORD)
assert(cfv.valid(), "bad config file: missing/invalid fields")

----------------------------------------
-- log init
----------------------------------------

log.init(config.LOG_PATH, config.LOG_MODE)

log.info("========================================")
log.info("BOOTING coordinator.startup " .. COORDINATOR_VERSION)
log.info("========================================")
println(">> SCADA Coordinator " .. COORDINATOR_VERSION .. " <<")

----------------------------------------
-- system startup
----------------------------------------

-- mount connected devices
ppm.mount_all()

-- setup monitors
local configured, monitors = coordinator.configure_monitors(config.NUM_UNITS)
if not configured or monitors == nil then
    println("boot> monitor setup failed")
    log.fatal("monitor configuration failed")
    return
end

log.info("monitors ready, dmesg output incoming...")

-- init renderer
renderer.set_displays(monitors)
renderer.reset(config.RECOLOR)
renderer.init_dmesg()

log_graphics("displays connected and reset")
log_sys("system start on " .. os.date("%c"))
log_boot("starting " .. COORDINATOR_VERSION)

----------------------------------------
-- setup communications
----------------------------------------

-- get the communications modem
local modem = ppm.get_wireless_modem()
if modem == nil then
    log_comms("wireless modem not found")
    println("boot> wireless modem not found")
    log.fatal("no wireless modem on startup")
    return
else
    log_comms("wireless modem connected")
end

-- create connection watchdog
local conn_watchdog = util.new_watchdog(5)
conn_watchdog.cancel()
log.debug("boot> conn watchdog created")

-- start comms, open all channels
local coord_comms = coordinator.comms(COORDINATOR_VERSION, modem, config.SCADA_SV_PORT, config.SCADA_SV_LISTEN, config.SCADA_API_LISTEN, conn_watchdog)
log.debug("boot> comms init")
log_comms("comms initialized")

-- base loop clock (2Hz, 10 ticks)
local MAIN_CLOCK = 0.5
local loop_clock = util.new_clock(MAIN_CLOCK)

----------------------------------------
-- connect to the supervisor
----------------------------------------

-- attempt to connect to the supervisor or exit
local function init_connect_sv()
    local tick_waiting, task_done = log_comms_connecting("attempting to connect to configured supervisor on channel " .. config.SCADA_SV_PORT)

    -- attempt to establish a connection with the supervisory computer
    if not coord_comms.sv_connect(60, tick_waiting, task_done) then
        log_comms("supervisor connection failed")
        log.fatal("failed to connect to supervisor")
        return false
    end

    return true
end

if not init_connect_sv() then
    println("boot> failed to connect to supervisor")
    log_sys("system shutdown")
    return
else
    log_sys("supervisor connected, proceeding to UI start")
end

----------------------------------------
-- start the UI
----------------------------------------

-- start up the UI
---@return boolean ui_ok started ok
local function init_start_ui()
    log_graphics("starting UI...")
    -- util.psleep(3)

    local draw_start = util.time_ms()

    local ui_ok, message = pcall(renderer.start_ui)
    if not ui_ok then
        renderer.close_ui()
        log_graphics(util.c("UI crashed: ", message))
        println_ts("UI crashed")
        log.fatal(util.c("ui crashed with error ", message))
    else
        log_graphics("first UI draw took " .. (util.time_ms() - draw_start) .. "ms")

        -- start clock
        loop_clock.start()
    end

    return ui_ok
end

local ui_ok = init_start_ui()

----------------------------------------
-- main event loop
----------------------------------------

local no_modem = false

-- start connection watchdog
conn_watchdog.feed()
log.debug("boot> conn watchdog started")

log_sys("system started successfully")

-- event loop
-- ui_ok will never change in this loop, same as while true or exit if UI start failed
while ui_ok do
    local event, param1, param2, param3, param4, param5 = util.pull_event()

    -- handle event
    if event == "peripheral_detach" then
        local type, device = ppm.handle_unmount(param1)

        if type ~= nil and device ~= nil then
            if type == "modem" then
                -- we only really care if this is our wireless modem
                if device == modem then
                    no_modem = true
                    log_sys("comms modem disconnected")
                    println_ts("wireless modem disconnected!")
                    log.error("comms modem disconnected!")

                    -- close out UI
                    renderer.close_ui()

                    -- alert user to status
                    log_sys("awaiting comms modem reconnect...")
                else
                    log_sys("non-comms modem disconnected")
                    log.warning("non-comms modem disconnected")
                end
            elseif type == "monitor" then
                if renderer.is_monitor_used(device) then
                    -- "halt and catch fire" style handling
                    log_sys("lost a configured monitor, system will now exit")
                    break
                else
                    log_sys("lost unused monitor, ignoring")
                end
            end
        end
    elseif event == "peripheral" then
        local type, device = ppm.mount(param1)

        if type ~= nil and device ~= nil then
            if type == "modem" then
                if device.isWireless() then
                    -- reconnected modem
                    no_modem = false
                    modem = device
                    coord_comms.reconnect_modem(modem)

                    log_sys("comms modem reconnected")
                    println_ts("wireless modem reconnected.")

                    -- re-init system
                    if not init_connect_sv() then break end
                    ui_ok = init_start_ui()
                else
                    log_sys("wired modem reconnected")
                end
            elseif type == "monitor" then
                -- not supported, system will exit on loss of in-use monitors
            end
        end
    elseif event == "timer" then
        if loop_clock.is_clock(param1) then
            -- main loop tick

            -- free any closed sessions
            --apisessions.free_all_closed()

            loop_clock.start()
        elseif conn_watchdog.is_timer(param1) then
            -- supervisor watchdog timeout
            local msg = "supervisor server timeout"
            log_comms(msg)
            println_ts(msg)
            log.warning(msg)

            -- close connection and UI
            coord_comms.close()
            renderer.close_ui()

            if not no_modem then
                -- try to re-connect to the supervisor
                if not init_connect_sv() then break end
                ui_ok = init_start_ui()
            end
        else
            -- a non-clock/main watchdog timer event

            --check API watchdogs
            --apisessions.check_all_watchdogs(param1)

            -- notify timer callback dispatcher
            tcallbackdsp.handle(param1)
        end
    elseif event == "modem_message" then
        -- got a packet
        local packet = coord_comms.parse_packet(param1, param2, param3, param4, param5)
        coord_comms.handle_packet(packet)

        -- check if it was a disconnect
        if not coord_comms.is_linked() then
            log_comms("supervisor closed connection")

            -- close connection and UI
            coord_comms.close()
            renderer.close_ui()

            if not no_modem then
                -- try to re-connect to the supervisor
                if not init_connect_sv() then break end
                ui_ok = init_start_ui()
            end
        end
    elseif event == "monitor_touch" then
        -- handle a monitor touch event
        renderer.handle_touch(core.events.touch(param1, param2, param3))
    end

    -- check for termination request
    if event == "terminate" or ppm.should_terminate() then
        println_ts("terminate requested, closing connections...")
        log_comms("terminate requested, closing supervisor connection...")
        coord_comms.close()
        log_comms("supervisor connection closed")
        log_comms("closing api sessions...")
        apisessions.close_all()
        log_comms("api sessions closed")
        break
    end
end

renderer.close_ui()
log_sys("system shutdown")

println_ts("exited")
log.info("exited")
