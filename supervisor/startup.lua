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
local types      = require("scada-common.types")
local util       = require("scada-common.util")

local core       = require("graphics.core")

local configure  = require("supervisor.configure")
local databus    = require("supervisor.databus")
local facility   = require("supervisor.facility")
local renderer   = require("supervisor.renderer")
local supervisor = require("supervisor.supervisor")

local svsessions = require("supervisor.session.svsessions")

local SUPERVISOR_VERSION = "v1.6.8"

local println = util.println
local println_ts = util.println_ts

----------------------------------------
-- get configuration
----------------------------------------

if not supervisor.load_config() then
    -- try to reconfigure (user action)
    local success, error = configure.configure(true)
    if success then
        if not supervisor.load_config() then
            println("failed to load a valid configuration, please reconfigure")
            return
        end
    else
        println("configuration error: " .. error)
        return
    end
end

local config = supervisor.config

local cfv = util.new_validator()

cfv.assert_eq(#config.CoolingConfig, config.UnitCount)
assert(cfv.valid(), "startup> the number of reactor cooling configurations is different than the number of units")

for i = 1, config.UnitCount do
    cfv.assert_type_table(config.CoolingConfig[i])
    assert(cfv.valid(), "startup> missing cooling entry for reactor unit " .. i)
    cfv.assert_type_int(config.CoolingConfig[i].BoilerCount)
    cfv.assert_type_int(config.CoolingConfig[i].TurbineCount)
    cfv.assert_type_bool(config.CoolingConfig[i].TankConnection)
    assert(cfv.valid(), "startup> missing boiler/turbine/tank fields for reactor unit " .. i)
    cfv.assert_range(config.CoolingConfig[i].BoilerCount, 0, 2)
    cfv.assert_range(config.CoolingConfig[i].TurbineCount, 1, 3)
    assert(cfv.valid(), "startup> out-of-range number of boilers and/or turbines provided for reactor unit " .. i)
end

if config.FacilityTankMode > 0 then
    assert(config.UnitCount == #config.FacilityTankDefs, "startup> the number of facility tank definitions must be equal to the number of units in facility tank mode")

    for i = 1, config.UnitCount do
        local def = config.FacilityTankDefs[i]
        cfv.assert_type_int(def)
        cfv.assert_range(def, 0, 2)
        assert(cfv.valid(), "startup> invalid facility tank definition for reactor unit " .. i)

        local entry = config.FacilityTankList[i]
        cfv.assert_type_int(entry)
        cfv.assert_range(entry, 0, 2)
        assert(cfv.valid(), "startup> invalid facility tank list entry for tank " .. i)

        local conn = config.FacilityTankConns[i]
        cfv.assert_type_int(conn)
        cfv.assert_range(conn, 0, #config.FacilityTankDefs)
        assert(cfv.valid(), "startup> invalid facility tank connection for reactor unit " .. i)

        local type = config.TankFluidTypes[i]
        cfv.assert_type_int(type)
        cfv.assert_range(type, 0, types.COOLANT_TYPE.SODIUM)
        assert(cfv.valid(), "startup> invalid tank fluid type for tank " .. i)
    end
end

----------------------------------------
-- log init
----------------------------------------

log.init(config.LogPath, config.LogMode, config.LogDebug)

log.info("========================================")
log.info("BOOTING supervisor.startup " .. SUPERVISOR_VERSION)
log.info("========================================")
println(">> SCADA Supervisor " .. SUPERVISOR_VERSION .. " <<")

crash.set_env("supervisor", SUPERVISOR_VERSION)
crash.dbg_log_env()

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
    if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
        network.init_mac(config.AuthKey)
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
    local fp_ok, message = renderer.try_start_ui(config.FrontPanelTheme, config.ColorMode)

    if not fp_ok then
        println_ts(util.c("UI error: ", message))
        log.error(util.c("front panel GUI render failed with error ", message))
    else
        -- redefine println_ts local to not print as we have the front panel running
        println_ts = function (_) end
    end

    -- create facility and unit objects
    local sv_facility = facility.new(config)

    -- create network interface then setup comms
    local nic = network.nic(modem)
    local superv_comms = supervisor.comms(SUPERVISOR_VERSION, nic, fp_ok, sv_facility)

    -- base loop clock (6.67Hz, 3 ticks)
    local MAIN_CLOCK = 0.15
    local loop_clock = util.new_clock(MAIN_CLOCK)

    -- start clock
    loop_clock.start()

    -- halve the rate heartbeat LED flash
    local heartbeat_toggle = true

    -- init startup recovery
    sv_facility.boot_recovery_init(supervisor.boot_state)

    -- event loop
    while true do
        local event, param1, param2, param3, param4, param5 = util.pull_event()

        -- handle event
        if event == "peripheral_detach" then
            local type, device = ppm.handle_unmount(param1)

            if type ~= nil and device ~= nil then
                if type == "modem" then
                    ---@cast device Modem
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
                    ---@cast device Modem
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
            if packet then superv_comms.handle_packet(packet) end
        elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or
               event == "double_click" then
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

    sv_facility.clear_boot_state()

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
