--
-- Nuclear Generation Facility SCADA Supervisor
--

require("/initenv").init_env()

local crash      = require("scada-common.crash")
local log        = require("scada-common.log")
local ppm        = require("scada-common.ppm")
local util       = require("scada-common.util")

local svsessions = require("supervisor.session.svsessions")

local config     = require("supervisor.config")
local supervisor = require("supervisor.supervisor")

local SUPERVISOR_VERSION = "beta-v0.12.0"

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

----------------------------------------
-- config validation
----------------------------------------

local cfv = util.new_validator()

cfv.assert_port(config.SCADA_DEV_LISTEN)
cfv.assert_port(config.SCADA_SV_LISTEN)
cfv.assert_type_int(config.TRUSTED_RANGE)
cfv.assert_type_num(config.PLC_TIMEOUT)
cfv.assert_min(config.PLC_TIMEOUT, 2)
cfv.assert_type_num(config.RTU_TIMEOUT)
cfv.assert_min(config.RTU_TIMEOUT, 2)
cfv.assert_type_num(config.CRD_TIMEOUT)
cfv.assert_min(config.CRD_TIMEOUT, 2)
cfv.assert_type_int(config.NUM_REACTORS)
cfv.assert_type_table(config.REACTOR_COOLING)
cfv.assert_type_str(config.LOG_PATH)
cfv.assert_type_int(config.LOG_MODE)

assert(cfv.valid(), "bad config file: missing/invalid fields")

for i = 1, config.NUM_REACTORS do
    cfv.assert_type_table(config.REACTOR_COOLING[i])
    assert(cfv.valid(), "missing cooling entry for reactor " .. i)
    cfv.assert_type_int(config.REACTOR_COOLING[i].BOILERS)
    cfv.assert_type_int(config.REACTOR_COOLING[i].TURBINES)
    assert(cfv.valid(), "missing boilers/turbines for reactor " .. i)
    cfv.assert_min(config.REACTOR_COOLING[i].BOILERS, 0)
    cfv.assert_min(config.REACTOR_COOLING[i].TURBINES, 1)
    assert(cfv.valid(), "bad number of boilers/turbines for reactor " .. i)
end

----------------------------------------
-- log init
----------------------------------------

log.init(config.LOG_PATH, config.LOG_MODE)

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

    -- mount connected devices
    ppm.mount_all()

    local modem = ppm.get_wireless_modem()
    if modem == nil then
        println("boot> wireless modem not found")
        log.fatal("no wireless modem on startup")
        return
    end

    -- start comms, open all channels
    local superv_comms = supervisor.comms(SUPERVISOR_VERSION, config.NUM_REACTORS, config.REACTOR_COOLING, modem,
                                            config.SCADA_DEV_LISTEN, config.SCADA_SV_LISTEN, config.TRUSTED_RANGE)

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
                        println_ts("wireless modem disconnected!")
                        log.error("comms modem disconnected!")
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

                        println_ts("wireless modem reconnected.")
                        log.info("comms modem reconnected.")
                    else
                        log.info("wired modem reconnected.")
                    end
                end
            end
        elseif event == "timer" and loop_clock.is_clock(param1) then
            -- main loop tick

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

    println_ts("exited")
    log.info("exited")
end

if not xpcall(main, crash.handler) then crash.exit() end
