--
-- Nuclear Generation Facility SCADA Supervisor
--

require("/initenv").init_env()

local crash      = require("scada-common.crash")
local comms      = require("scada-common.comms")
local log        = require("scada-common.log")
local ppm        = require("scada-common.ppm")
local util       = require("scada-common.util")

local core       = require("graphics.core")

local config     = require("supervisor.config")
local databus    = require("supervisor.databus")
local renderer   = require("supervisor.renderer")
local supervisor = require("supervisor.supervisor")

local svsessions = require("supervisor.session.svsessions")

local SUPERVISOR_VERSION = "v0.16.4"

local println = util.println
local println_ts = util.println_ts

----------------------------------------
-- config validation
----------------------------------------

local cfv = util.new_validator()

cfv.assert_port(config.SCADA_DEV_LISTEN)
cfv.assert_port(config.SCADA_SV_CTL_LISTEN)
cfv.assert_type_int(config.TRUSTED_RANGE)
cfv.assert_type_num(config.PLC_TIMEOUT)
cfv.assert_min(config.PLC_TIMEOUT, 2)
cfv.assert_type_num(config.RTU_TIMEOUT)
cfv.assert_min(config.RTU_TIMEOUT, 2)
cfv.assert_type_num(config.CRD_TIMEOUT)
cfv.assert_min(config.CRD_TIMEOUT, 2)
cfv.assert_type_num(config.PKT_TIMEOUT)
cfv.assert_min(config.PKT_TIMEOUT, 2)
cfv.assert_type_int(config.NUM_REACTORS)
cfv.assert_type_table(config.REACTOR_COOLING)
cfv.assert_type_str(config.LOG_PATH)
cfv.assert_type_int(config.LOG_MODE)

assert(cfv.valid(), "bad config file: missing/invalid fields")

cfv.assert_eq(#config.REACTOR_COOLING, config.NUM_REACTORS)
assert(cfv.valid(), "config: number of cooling configs different than number of units")

for i = 1, config.NUM_REACTORS do
    cfv.assert_type_table(config.REACTOR_COOLING[i])
    assert(cfv.valid(), "config: missing cooling entry for reactor " .. i)
    cfv.assert_type_int(config.REACTOR_COOLING[i].BOILERS)
    cfv.assert_type_int(config.REACTOR_COOLING[i].TURBINES)
    assert(cfv.valid(), "config: missing boilers/turbines for reactor " .. i)
    cfv.assert_min(config.REACTOR_COOLING[i].BOILERS, 0)
    cfv.assert_min(config.REACTOR_COOLING[i].TURBINES, 1)
    assert(cfv.valid(), "config: bad number of boilers/turbines for reactor " .. i)
end

----------------------------------------
-- log init
----------------------------------------

log.init(config.LOG_PATH, config.LOG_MODE, config.LOG_DEBUG == true)

log.info("========================================")
log.info("BOOTING supervisor.startup " .. SUPERVISOR_VERSION)
log.info("========================================")
println(">> SCADA Supervisor " .. SUPERVISOR_VERSION .. " <<")

crash.set_env("supervisor", SUPERVISOR_VERSION)

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- startup
    ----------------------------------------

    -- record firmware versions and ID
    databus.tx_versions(SUPERVISOR_VERSION, comms.version)

    -- mount connected devices
    ppm.mount_all()

    local modem = ppm.get_wireless_modem()
    if modem == nil then
        println("startup> wireless modem not found")
        log.fatal("no wireless modem on startup")
        return
    end

    databus.tx_hw_modem(true)

    -- start UI
    local fp_ok, message = pcall(renderer.start_ui)

    if not fp_ok then
        renderer.close_ui()
        println_ts(util.c("UI error: ", message))
        log.error(util.c("GUI crashed with error ", message))
    else
        -- start comms, open all channels
        local superv_comms = supervisor.comms(SUPERVISOR_VERSION, config.NUM_REACTORS, config.REACTOR_COOLING, modem,
                                                config.SCADA_DEV_LISTEN, config.SCADA_SV_CTL_LISTEN, config.TRUSTED_RANGE)

        -- base loop clock (6.67Hz, 3 ticks)
        local MAIN_CLOCK = 0.15
        local loop_clock = util.new_clock(MAIN_CLOCK)

        -- start clock
        loop_clock.start()

        -- event loop
        while true do
            local event, param1, param2, param3, param4, param5 = util.pull_event()

            -- handle event
            if event == "peripheral_detach" then
                local type, device = ppm.handle_unmount(param1)

                if type ~= nil and device ~= nil then
                    if type == "modem" then
                        -- we only care if this is our wireless modem
                        if device == modem then
                            log.warning("comms modem disconnected")
                            databus.tx_hw_modem(false)
                        else
                            log.warning("non-comms modem disconnected")
                        end
                    end
                end
            elseif event == "peripheral" then
                local type, device = ppm.mount(param1)

                if type ~= nil and device ~= nil then
                    if type == "modem" then
                        if device.isWireless() then
                            -- reconnected modem
                            modem = device
                            superv_comms.reconnect_modem(modem)

                            log.info("comms modem reconnected")

                            databus.tx_hw_modem(true)
                        else
                            log.info("wired modem reconnected")
                        end
                    end
                end
            elseif event == "timer" and loop_clock.is_clock(param1) then
                -- main loop tick
                databus.heartbeat()

                -- iterate sessions
                svsessions.iterate_all()

                -- free any closed sessions
                svsessions.free_all_closed()

                loop_clock.start()
            elseif event == "timer" then
                -- a non-clock timer event, check watchdogs
                svsessions.check_all_watchdogs(param1)
            elseif event == "modem_message" then
                -- got a packet
                local packet = superv_comms.parse_packet(param1, param2, param3, param4, param5)
                superv_comms.handle_packet(packet)
            elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" then
                -- handle a mouse event
                renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
            end

            -- check for termination request
            if event == "terminate" or ppm.should_terminate() then
                log.info("terminate requested, closing sessions...")
                svsessions.close_all()
                log.info("sessions closed")
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
