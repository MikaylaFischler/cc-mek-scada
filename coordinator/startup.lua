--
-- Nuclear Generation Facility SCADA Coordinator
--

require("/initenv").init_env()

local comms       = require("scada-common.comms")
local crash       = require("scada-common.crash")
local log         = require("scada-common.log")
local network     = require("scada-common.network")
local ppm         = require("scada-common.ppm")
local tcd         = require("scada-common.tcd")
local util        = require("scada-common.util")

local core        = require("graphics.core")

local config      = require("coordinator.config")
local coordinator = require("coordinator.coordinator")
local iocontrol   = require("coordinator.iocontrol")
local renderer    = require("coordinator.renderer")
local sounder     = require("coordinator.sounder")

local apisessions = require("coordinator.session.apisessions")

local COORDINATOR_VERSION = "v1.1.0"

local println = util.println
local println_ts = util.println_ts

local log_graphics = coordinator.log_graphics
local log_sys = coordinator.log_sys
local log_boot = coordinator.log_boot
local log_comms = coordinator.log_comms
local log_crypto = coordinator.log_crypto

----------------------------------------
-- config validation
----------------------------------------

local cfv = util.new_validator()

cfv.assert_channel(config.SVR_CHANNEL)
cfv.assert_channel(config.CRD_CHANNEL)
cfv.assert_channel(config.PKT_CHANNEL)
cfv.assert_type_int(config.TRUSTED_RANGE)
cfv.assert_type_num(config.SV_TIMEOUT)
cfv.assert_min(config.SV_TIMEOUT, 2)
cfv.assert_type_num(config.API_TIMEOUT)
cfv.assert_min(config.API_TIMEOUT, 2)
cfv.assert_type_int(config.NUM_UNITS)
cfv.assert_type_num(config.SOUNDER_VOLUME)
cfv.assert_type_bool(config.TIME_24_HOUR)
cfv.assert_type_str(config.LOG_PATH)
cfv.assert_type_int(config.LOG_MODE)

assert(cfv.valid(), "bad config file: missing/invalid fields")

----------------------------------------
-- log init
----------------------------------------

log.init(config.LOG_PATH, config.LOG_MODE, config.LOG_DEBUG == true)

log.info("========================================")
log.info("BOOTING coordinator.startup " .. COORDINATOR_VERSION)
log.info("========================================")
println(">> SCADA Coordinator " .. COORDINATOR_VERSION .. " <<")

crash.set_env("coordinator", COORDINATOR_VERSION)

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- system startup
    ----------------------------------------

    -- mount connected devices
    ppm.mount_all()

    -- report versions/init fp PSIL
    iocontrol.init_fp(COORDINATOR_VERSION, comms.version)

    -- setup monitors
    local configured, monitors = coordinator.configure_monitors(config.NUM_UNITS, config.DISABLE_FLOW_VIEW == true)
    if not configured or monitors == nil then
        println("startup> monitor setup failed")
        log.fatal("monitor configuration failed")
        return
    end

    -- init renderer
    renderer.legacy_disable_flow_view(config.DISABLE_FLOW_VIEW == true)
    renderer.set_displays(monitors)
    renderer.init_displays()

    if not renderer.validate_main_display_width() then
        println("startup> main display must be 8 blocks wide")
        log.fatal("main display not wide enough")
        return
    elseif (config.DISABLE_FLOW_VIEW ~= true) and not renderer.validate_flow_display_width() then
        println("startup> flow display must be 8 blocks wide")
        log.fatal("flow display not wide enough")
        return
    elseif not renderer.validate_unit_display_sizes() then
        println("startup> one or more unit display dimensions incorrect; they must be 4x4 blocks")
        log.fatal("unit display dimensions incorrect")
        return
    end

    renderer.init_dmesg()

    -- lets get started!
    log.info("monitors ready, dmesg output incoming...")

    log_graphics("displays connected and reset")
    log_sys("system start on " .. os.date("%c"))
    log_boot("starting " .. COORDINATOR_VERSION)

    ----------------------------------------
    -- setup alarm sounder subsystem
    ----------------------------------------

    local speaker = ppm.get_device("speaker")
    if speaker == nil then
        log_boot("annunciator alarm speaker not found")
        println("startup> speaker not found")
        log.fatal("no annunciator alarm speaker found")
        return
    else
        local sounder_start = util.time_ms()
        log_boot("annunciator alarm speaker connected")
        sounder.init(speaker, config.SOUNDER_VOLUME)
        log_boot("tone generation took " .. (util.time_ms() - sounder_start) .. "ms")
        log_sys("annunciator alarm configured")
        iocontrol.fp_has_speaker(true)
    end

    ----------------------------------------
    -- setup communications
    ----------------------------------------

    -- message authentication init
    if type(config.AUTH_KEY) == "string" then
        local init_time = network.init_mac(config.AUTH_KEY)
        log_crypto("HMAC init took " .. init_time .. "ms")
    end

    -- get the communications modem
    local modem = ppm.get_wireless_modem()
    if modem == nil then
        log_comms("wireless modem not found")
        println("startup> wireless modem not found")
        log.fatal("no wireless modem on startup")
        return
    else
        log_comms("wireless modem connected")
        iocontrol.fp_has_modem(true)
    end

    -- create connection watchdog
    local conn_watchdog = util.new_watchdog(config.SV_TIMEOUT)
    conn_watchdog.cancel()
    log.debug("startup> conn watchdog created")

    -- create network interface then setup comms
    local nic = network.nic(modem)
    local coord_comms = coordinator.comms(COORDINATOR_VERSION, nic, config.NUM_UNITS, config.CRD_CHANNEL,
                                            config.SVR_CHANNEL, config.PKT_CHANNEL, config.TRUSTED_RANGE, conn_watchdog)
    log.debug("startup> comms init")
    log_comms("comms initialized")

    -- base loop clock (2Hz, 10 ticks)
    local MAIN_CLOCK = 0.5
    local loop_clock = util.new_clock(MAIN_CLOCK)

    ----------------------------------------
    -- start front panel & UI start function
    ----------------------------------------

    log_graphics("starting front panel UI...")

    local fp_ok, fp_message = renderer.try_start_fp()
    if not fp_ok then
        log_graphics(util.c("front panel UI error: ", fp_message))
        println_ts("front panel UI creation failed")
        log.fatal(util.c("front panel GUI render failed with error ", fp_message))
        return
    else log_graphics("front panel ready") end

    -- start up the main UI
    ---@return boolean ui_ok started ok
    local function start_main_ui()
        log_graphics("starting main UI...")

        local draw_start = util.time_ms()

        local ui_ok, ui_message = renderer.try_start_ui()
        if not ui_ok then
            log_graphics(util.c("main UI error: ", ui_message))
            log.fatal(util.c("main GUI render failed with error ", ui_message))
        else
            log_graphics("main UI draw took " .. (util.time_ms() - draw_start) .. "ms")
        end

        return ui_ok
    end

    ----------------------------------------
    -- main event loop
    ----------------------------------------

    local link_failed = false
    local ui_ok = true
    local date_format = util.trinary(config.TIME_24_HOUR, "%X \x04 %A, %B %d %Y", "%r \x04 %A, %B %d %Y")

    -- start clock
    loop_clock.start()

    log_sys("system started successfully")

    -- main event loop
    while true do
        local event, param1, param2, param3, param4, param5 = util.pull_event()

        -- handle event
        if event == "peripheral_detach" then
            local type, device = ppm.handle_unmount(param1)

            if type ~= nil and device ~= nil then
                if type == "modem" then
                    -- we only really care if this is our wireless modem
                    -- if it is another modem, handle other peripheral losses separately
                    if nic.is_modem(device) then
                        nic.disconnect()
                        log_sys("comms modem disconnected")

                        local other_modem = ppm.get_wireless_modem()
                        if other_modem then
                            log_sys("found another wireless modem, using it for comms")
                            nic.connect(other_modem)
                        else
                            -- close out main UI
                            renderer.close_ui()

                            -- alert user to status
                            log_sys("awaiting comms modem reconnect...")

                            iocontrol.fp_has_modem(false)
                        end
                    else
                        log_sys("non-comms modem disconnected")
                    end
                elseif type == "monitor" then
                    if renderer.handle_disconnect(device) then
                        log_sys("lost a configured monitor")
                    else
                        log_sys("lost an unused monitor")
                    end
                elseif type == "speaker" then
                    log_sys("lost alarm sounder speaker")
                    iocontrol.fp_has_speaker(false)
                end
            end
        elseif event == "peripheral" then
            local type, device = ppm.mount(param1)

            if type ~= nil and device ~= nil then
                if type == "modem" then
                    if device.isWireless() and not nic.is_connected() then
                        -- reconnected modem
                        log_sys("comms modem reconnected")
                        nic.connect(device)
                        iocontrol.fp_has_modem(true)
                    elseif device.isWireless() then
                        log.info("unused wireless modem reconnected")
                    else
                        log_sys("wired modem reconnected")
                    end
                elseif type == "monitor" then
                    if renderer.handle_reconnect(param1, device) then
                        log_sys(util.c("configured monitor ", param1, " reconnected"))
                    else
                        log_sys(util.c("unused monitor ", param1, " connected"))
                    end
                elseif type == "speaker" then
                    log_sys("alarm sounder speaker reconnected")
                    sounder.reconnect(device)
                    iocontrol.fp_has_speaker(true)
                end
            end
        elseif event == "timer" then
            if loop_clock.is_clock(param1) then
                -- main loop tick

                -- toggle heartbeat
                iocontrol.heartbeat()

                -- maintain connection
                if nic.is_connected() then
                    local ok, start_ui = coord_comms.try_connect()
                    if not ok then
                        link_failed = true
                        log_sys("supervisor connection failed, shutting down...")
                        log.fatal("failed to connect to supervisor")
                        break
                    elseif start_ui then
                        log_sys("supervisor connected, proceeding to main UI start")
                        ui_ok = start_main_ui()
                        if not ui_ok then break end
                    end
                end

                -- iterate sessions
                apisessions.iterate_all()

                -- free any closed sessions
                apisessions.free_all_closed()

                -- update date and time string for main display
                if coord_comms.is_linked() then
                    iocontrol.get_db().facility.ps.publish("date_time", os.date(date_format))
                end

                loop_clock.start()
            elseif conn_watchdog.is_timer(param1) then
                -- supervisor watchdog timeout
                log_comms("supervisor server timeout")

                -- close connection, main UI, and stop sounder
                coord_comms.close()
                renderer.close_ui()
                sounder.stop()
            else
                -- a non-clock/main watchdog timer event

                -- check API watchdogs
                apisessions.check_all_watchdogs(param1)

                -- notify timer callback dispatcher
                tcd.handle(param1)
            end
        elseif event == "modem_message" then
            -- got a packet
            local packet = coord_comms.parse_packet(param1, param2, param3, param4, param5)

            -- handle then check if it was a disconnect
            if coord_comms.handle_packet(packet) then
                log_comms("supervisor closed connection")

                -- close connection, main UI, and stop sounder
                coord_comms.close()
                renderer.close_ui()
                sounder.stop()
            end
        elseif event == "monitor_touch" or event == "mouse_click" or event == "mouse_up" or
               event == "mouse_drag" or event == "mouse_scroll" or event == "double_click" then
            -- handle a mouse event
            renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
        elseif event == "speaker_audio_empty" then
            -- handle speaker buffer emptied
            sounder.continue()
        end

        -- check for termination request
        if event == "terminate" or ppm.should_terminate() then
            -- handle supervisor connection
            coord_comms.try_connect(true)

            if coord_comms.is_linked() then
                log_comms("terminate requested, closing supervisor connection...")
            else link_failed = true end

            coord_comms.close()
            log_comms("supervisor connection closed")

            -- handle API sessions
            log_comms("closing api sessions...")
            apisessions.close_all()
            log_comms("api sessions closed")
            break
        end
    end

    renderer.close_ui()
    renderer.close_fp()
    sounder.stop()
    log_sys("system shutdown")

    if link_failed then println_ts("failed to connect to supervisor") end
    if not ui_ok then println_ts("main UI creation failed") end

    -- close on error exit (such as UI error)
    if coord_comms.is_linked() then coord_comms.close() end

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
