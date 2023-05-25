--
-- SCADA System Access on a Pocket Computer
--

require("/initenv").init_env()

local crash        = require("scada-common.crash")
local log          = require("scada-common.log")
local ppm          = require("scada-common.ppm")
local tcallbackdsp = require("scada-common.tcallbackdsp")
local util         = require("scada-common.util")

local core         = require("graphics.core")

local config       = require("pocket.config")
local coreio       = require("pocket.coreio")
local pocket       = require("pocket.pocket")
local renderer     = require("pocket.renderer")

local POCKET_VERSION = "alpha-v0.3.3"

local println = util.println
local println_ts = util.println_ts

----------------------------------------
-- config validation
----------------------------------------

local cfv = util.new_validator()

cfv.assert_port(config.SCADA_SV_PORT)
cfv.assert_port(config.SCADA_API_PORT)
cfv.assert_port(config.LISTEN_PORT)
cfv.assert_type_int(config.TRUSTED_RANGE)
cfv.assert_type_num(config.COMMS_TIMEOUT)
cfv.assert_min(config.COMMS_TIMEOUT, 2)
cfv.assert_type_str(config.LOG_PATH)
cfv.assert_type_int(config.LOG_MODE)

assert(cfv.valid(), "bad config file: missing/invalid fields")

----------------------------------------
-- log init
----------------------------------------

log.init(config.LOG_PATH, config.LOG_MODE, config.LOG_DEBUG == true)

log.info("========================================")
log.info("BOOTING pocket.startup " .. POCKET_VERSION)
log.info("========================================")

crash.set_env("pocket", POCKET_VERSION)

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- system startup
    ----------------------------------------

    -- mount connected devices
    ppm.mount_all()

    ----------------------------------------
    -- setup communications & clocks
    ----------------------------------------

    coreio.report_link_state(coreio.LINK_STATE.UNLINKED)

    -- get the communications modem
    local modem = ppm.get_wireless_modem()
    if modem == nil then
        println("startup> wireless modem not found: please craft the pocket computer with a wireless modem")
        log.fatal("startup> no wireless modem on startup")
        return
    end

    -- create connection watchdogs
    local conn_wd = {
        sv = util.new_watchdog(config.COMMS_TIMEOUT),
        api = util.new_watchdog(config.COMMS_TIMEOUT)
    }

    conn_wd.sv.cancel()
    conn_wd.api.cancel()

    log.debug("startup> conn watchdogs created")

    -- start comms, open all channels
    local pocket_comms = pocket.comms(POCKET_VERSION, modem, config.LISTEN_PORT, config.SCADA_SV_PORT,
                                        config.SCADA_API_PORT, config.TRUSTED_RANGE, conn_wd.sv, conn_wd.api)
    log.debug("startup> comms init")

    -- base loop clock (2Hz, 10 ticks)
    local MAIN_CLOCK = 0.5
    local loop_clock = util.new_clock(MAIN_CLOCK)

    ----------------------------------------
    -- start the UI
    ----------------------------------------

    local ui_ok, message = pcall(renderer.start_ui)
    if not ui_ok then
        renderer.close_ui()
        println(util.c("UI error: ", message))
        log.error(util.c("startup> GUI crashed with error ", message))
    else
        -- start clock
        loop_clock.start()
    end

    ----------------------------------------
    -- main event loop
    ----------------------------------------

    if ui_ok then
        -- start connection watchdogs
        conn_wd.sv.feed()
        conn_wd.api.feed()
        log.debug("startup> conn watchdog started")

        -- main event loop
        while true do
            local event, param1, param2, param3, param4, param5 = util.pull_event()

            -- handle event
            if event == "timer" then
                if loop_clock.is_clock(param1) then
                    -- main loop tick

                    -- relink if necessary
                    pocket_comms.link_update()

                    loop_clock.start()
                elseif conn_wd.sv.is_timer(param1) then
                    -- supervisor watchdog timeout
                    log.info("supervisor server timeout")
                    pocket_comms.close_sv()
                elseif conn_wd.api.is_timer(param1) then
                    -- coordinator watchdog timeout
                    log.info("coordinator api server timeout")
                    pocket_comms.close_api()
                else
                    -- a non-clock/main watchdog timer event
                    -- notify timer callback dispatcher
                    tcallbackdsp.handle(param1)
                end
            elseif event == "modem_message" then
                -- got a packet
                local packet = pocket_comms.parse_packet(param1, param2, param3, param4, param5)
                pocket_comms.handle_packet(packet)
            elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" then
                -- handle a monitor touch event
                renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
            end

            -- check for termination request
            if event == "terminate" or ppm.should_terminate() then
                log.info("terminate requested, closing server connections...")
                pocket_comms.close()
                log.info("connections closed")
                break
            end
        end

        renderer.close_ui()
    end

    println_ts("exited")
    log.info("exited")
end

if not xpcall(main, crash.handler) then
    pcall(renderer.close_ui)
    crash.exit()
else
    log.close()
end
