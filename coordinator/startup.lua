--
-- Nuclear Generation Facility SCADA Coordinator
--

require("/initenv").init_env()

local log  = require("scada-common.log")
local ppm  = require("scada-common.ppm")
local util = require("scada-common.util")

local apisessions = require("coordinator.apisessions")
local config      = require("coordinator.config")
local coordinator = require("coordinator.coordinator")
local renderer    = require("coordinator.renderer")

local COORDINATOR_VERSION = "alpha-v0.3.0"

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
-- startup
----------------------------------------

-- mount connected devices
ppm.mount_all()

-- setup monitors
local configured, monitors = coordinator.configure_monitors(config.NUM_UNITS)
if not configured then
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

local tick_waiting, task_done = log_comms_connecting("attempting to connect to configured supervisor on channel " .. config.SCADA_SV_PORT)

-- attempt to establish a connection with the supervisory computer
if not coord_comms.sv_connect(60, tick_waiting, task_done) then
    log_comms("supervisor connection failed")
    println("boot> failed to connect to supervisor")
    log.fatal("failed to connect to supervisor")
    log_sys("system shutdown")
    return
end

----------------------------------------
-- start the UI
----------------------------------------

log_graphics("starting UI...")
-- util.psleep(3)

local draw_start = util.time_ms()

local ui_ok, message = pcall(renderer.start_ui)
if not ui_ok then
    renderer.close_ui(config.RECOLOR)
    log_graphics(util.c("UI crashed: ", message))
    println_ts("UI crashed")
    log.fatal(util.c("ui crashed with error ", message))
else
    log_graphics("first UI draw took " .. (util.time_ms() - draw_start) .. "ms")

    -- start clock
    loop_clock.start()
end

----------------------------------------
-- main event loop
----------------------------------------

-- start connection watchdog
conn_watchdog.feed()
log.debug("boot> conn watchdog started")

-- event loop
-- ui_ok will never change in this loop, same as while true or exit if UI start failed
while ui_ok do
---@diagnostic disable-next-line: undefined-field
    local event, param1, param2, param3, param4, param5 = os.pullEventRaw()

    -- handle event
    if event == "peripheral_detach" then
        local type, device = ppm.handle_unmount(param1)

        if type ~= nil and device ~= nil then
            if type == "modem" then
                -- we only really care if this is our wireless modem
                if device == modem then
                    log_sys("comms modem disconnected")
                    println_ts("wireless modem disconnected!")
                    log.error("comms modem disconnected!")
                else
                    log_sys("non-comms modem disconnected")
                    log.warning("non-comms modem disconnected")
                end
            elseif type == "monitor" then
                -- @todo: handle monitor loss
            end
        end
    elseif event == "peripheral" then
        local type, device = ppm.mount(param1)

        if type ~= nil and device ~= nil then
            if type == "modem" then
                if device.isWireless() then
                    -- reconnected modem
                    modem = device
                    coord_comms.reconnect_modem(modem)

                    log_sys("comms modem reconnected")
                    println_ts("wireless modem reconnected.")
                else
                    log_sys("wired modem reconnected")
                end
            elseif type == "monitor" then
                -- @todo: handle monitor reconnect
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
        else
            -- a non-clock/main watchdog timer event, check API watchdogs
            --apisessions.check_all_watchdogs(param1)
        end
    elseif event == "modem_message" then
        -- got a packet
        local packet = coord_comms.parse_packet(param1, param2, param3, param4, param5)
        coord_comms.handle_packet(packet)
    end

    -- check for termination request
    if event == "terminate" or ppm.should_terminate() then
        log_comms("terminate requested, closing sessions...")
        println_ts("closing sessions...")
        apisessions.close_all()
        log_comms("api sessions closed")
        break
    end
end

renderer.close_ui(config.RECOLOR)
log_sys("system shutdown")

println_ts("exited")
log.info("exited")
