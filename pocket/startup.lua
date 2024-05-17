--
-- SCADA System Access on a Pocket Computer
--

require("/initenv").init_env()

local crash     = require("scada-common.crash")
local log       = require("scada-common.log")
local network   = require("scada-common.network")
local ppm       = require("scada-common.ppm")
local tcd       = require("scada-common.tcd")
local util      = require("scada-common.util")

local core      = require("graphics.core")

local configure = require("pocket.configure")
local iocontrol = require("pocket.iocontrol")
local pocket    = require("pocket.pocket")
local renderer  = require("pocket.renderer")

local POCKET_VERSION = "v0.9.1-alpha"

local println = util.println
local println_ts = util.println_ts

----------------------------------------
-- get configuration
----------------------------------------

if not pocket.load_config() then
    -- try to reconfigure (user action)
    local success, error = configure.configure(true)
    if success then
        if not pocket.load_config() then
            println("failed to load a valid configuration, please reconfigure")
            return
        end
    else
        println("configuration error: " .. error)
        return
    end
end

local config = pocket.config

----------------------------------------
-- log init
----------------------------------------

log.init(config.LogPath, config.LogMode, config.LogDebug)

log.info("========================================")
log.info("BOOTING pocket.startup " .. POCKET_VERSION)
log.info("========================================")

crash.set_env("pocket", POCKET_VERSION)
crash.dbg_log_env()

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- system startup
    ----------------------------------------

    -- mount connected devices
    ppm.mount_all()

    -- record version for GUI
    iocontrol.get_db().version = POCKET_VERSION

    ----------------------------------------
    -- setup communications & clocks
    ----------------------------------------

    -- message authentication init
    if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
        network.init_mac(config.AuthKey)
    end

    iocontrol.report_link_state(iocontrol.LINK_STATE.UNLINKED)

    -- get the communications modem
    local modem = ppm.get_wireless_modem()
    if modem == nil then
        println("startup> wireless modem not found: please craft the pocket computer with a wireless modem")
        log.fatal("startup> no wireless modem on startup")
        return
    end

    -- create connection watchdogs
    local conn_wd = {
        sv = util.new_watchdog(config.ConnTimeout),
        api = util.new_watchdog(config.ConnTimeout)
    }

    conn_wd.sv.cancel()
    conn_wd.api.cancel()

    log.debug("startup> conn watchdogs created")

    -- create network interface then setup comms
    local nic = network.nic(modem)
    local pocket_comms = pocket.comms(POCKET_VERSION, nic, conn_wd.sv, conn_wd.api)
    log.debug("startup> comms init")

    -- base loop clock (2Hz, 10 ticks)
    local MAIN_CLOCK = 0.5
    local loop_clock = util.new_clock(MAIN_CLOCK)

    -- init I/O control
    iocontrol.init_core(pocket_comms)

    ----------------------------------------
    -- start the UI
    ----------------------------------------

    local ui_ok, message = renderer.try_start_ui()
    if not ui_ok then
        println(util.c("UI error: ", message))
        log.error(util.c("startup> GUI render failed with error ", message))
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
        log.debug("startup> conn watchdogs started")

        local io_db = iocontrol.get_db()
        local nav   = io_db.nav

        -- main event loop
        while true do
            local event, param1, param2, param3, param4, param5 = util.pull_event()

            -- handle event
            if event == "timer" then
                if loop_clock.is_clock(param1) then
                    -- main loop tick

                    -- relink if necessary
                    pocket_comms.link_update()

                    -- update any tasks for the active page
                    local page_tasks = nav.get_current_page().tasks
                    for i = 1, #page_tasks do page_tasks[i]() end

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
                    tcd.handle(param1)
                end
            elseif event == "modem_message" then
                -- got a packet
                local packet = pocket_comms.parse_packet(param1, param2, param3, param4, param5)
                pocket_comms.handle_packet(packet)
            elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or
                   event == "double_click" then
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
