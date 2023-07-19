--
-- Nuclear Generation Facility SCADA Supervisor
--

require("/initenv").init_env()

local crash      = require("scada-common.crash")
local comms      = require("scada-common.comms")
local log        = require("scada-common.log")
local network    = require("scada-common.network")
local ppm        = require("scada-common.ppm")
local tcd        = require("scada-common.tcd")
local util       = require("scada-common.util")

local core       = require("graphics.core")

local config     = require("supervisor.config")
local databus    = require("supervisor.databus")
local renderer   = require("supervisor.renderer")
local supervisor = require("supervisor.supervisor")

local svsessions = require("supervisor.session.svsessions")

local SUPERVISOR_VERSION = "v0.20.4"

local println = util.println
local println_ts = util.println_ts

----------------------------------------
-- config validation
----------------------------------------

local cfv = util.new_validator()

cfv.assert_channel(config.SVR_CHANNEL)
cfv.assert_channel(config.PLC_CHANNEL)
cfv.assert_channel(config.RTU_CHANNEL)
cfv.assert_channel(config.CRD_CHANNEL)
cfv.assert_channel(config.PKT_CHANNEL)
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

    -- message authentication init
    if type(config.AUTH_KEY) == "string" then
        network.init_mac(config.AUTH_KEY)
    end

    -- get modem
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
        log.error(util.c("front panel GUI render failed with error ", message))
    else
        -- redefine println_ts local to not print as we have the front panel running
        println_ts = function (_) end
    end

    -- create network interface then setup comms
    local nic = network.nic(modem)
    local superv_comms = supervisor.comms(SUPERVISOR_VERSION, nic, fp_ok)

    -- base loop clock (6.67Hz, 3 ticks)
    local MAIN_CLOCK = 0.15
    local loop_clock = util.new_clock(MAIN_CLOCK)

    -- start clock
    loop_clock.start()

    -- halve the rate heartbeat LED flash
    local heartbeat_toggle = true

    -- event loop
    while true do
        local event, param1, param2, param3, param4, param5 = util.pull_event()

        -- handle event
        if event == "peripheral_detach" then
            local type, device = ppm.handle_unmount(param1)

            if type ~= nil and device ~= nil then
                if type == "modem" then
                    -- we only care if this is our wireless modem
                    if nic.is_modem(device) then
                        nic.disconnect()

                        println_ts("wireless modem disconnected!")
                        log.warning("comms modem disconnected")

                        local other_modem = ppm.get_wireless_modem()
                        if other_modem then
                            log.info("found another wireless modem, using it for comms")
                            nic.connect(other_modem)
                        else
                            databus.tx_hw_modem(false)
                        end
                    else
                        log.warning("non-comms modem disconnected")
                    end
                end
            end
        elseif event == "peripheral" then
            local type, device = ppm.mount(param1)

            if type ~= nil and device ~= nil then
                if type == "modem" then
                    if device.isWireless() and not nic.is_connected() then
                        -- reconnected modem
                        nic.connect(device)

                        println_ts("wireless modem reconnected.")
                        log.info("comms modem reconnected")

                        databus.tx_hw_modem(true)
                    elseif device.isWireless() then
                        log.info("unused wireless modem reconnected")
                    else
                        log.info("wired modem reconnected")
                    end
                end
            end
        elseif event == "timer" and loop_clock.is_clock(param1) then
            -- main loop tick

            if heartbeat_toggle then databus.heartbeat() end
            heartbeat_toggle = not heartbeat_toggle

            -- iterate sessions
            svsessions.iterate_all()

            -- free any closed sessions
            svsessions.free_all_closed()

            loop_clock.start()
        elseif event == "timer" then
            -- a non-clock timer event, check watchdogs
            svsessions.check_all_watchdogs(param1)

            -- notify timer callback dispatcher
            tcd.handle(param1)
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
            println_ts("closing sessions...")
            log.info("terminate requested, closing sessions...")
            svsessions.close_all()
            log.info("sessions closed")
            break
        end
    end

    renderer.close_ui()

    util.println_ts("exited")
    log.info("exited")
end

if not xpcall(main, crash.handler) then
    pcall(renderer.close_ui)
    crash.exit()
else
    log.close()
end
