--
-- Nuclear Generation Facility SCADA Supervisor
--

os.loadAPI("scada-common/log.lua")
os.loadAPI("scada-common/util.lua")
os.loadAPI("scada-common/ppm.lua")
os.loadAPI("scada-common/comms.lua")
os.loadAPI("scada-common/modbus.lua")
os.loadAPI("scada-common/mqueue.lua")

os.loadAPI("config.lua")

os.loadAPI("session/rtu.lua")
os.loadAPI("session/plc.lua")
os.loadAPI("session/coordinator.lua")
os.loadAPI("session/svsessions.lua")

os.loadAPI("supervisor.lua")

local SUPERVISOR_VERSION = "alpha-v0.1.11"

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

log.init(config.LOG_PATH, config.LOG_MODE)

log._info("========================================")
log._info("BOOTING supervisor.startup " .. SUPERVISOR_VERSION)
log._info("========================================")
println(">> SCADA Supervisor " .. SUPERVISOR_VERSION .. " <<")

-- mount connected devices
ppm.mount_all()

local modem = ppm.get_wireless_modem()
if modem == nil then
    println("boot> wireless modem not found")
    log._warning("no wireless modem on startup")
    return
end

-- start comms, open all channels
local superv_comms = supervisor.superv_comms(config.NUM_REACTORS, modem, config.SCADA_DEV_LISTEN, config.SCADA_SV_LISTEN)

-- base loop clock (6.67Hz, 3 ticks)
local MAIN_CLOCK = 0.15
local loop_clock = os.startTimer(MAIN_CLOCK)

-- event loop
while true do
    local event, param1, param2, param3, param4, param5 = os.pullEventRaw()

    -- handle event
    if event == "peripheral_detach" then
        local device = ppm.handle_unmount(param1)

        if device.type == "modem" then
            -- we only care if this is our wireless modem
            if device.dev == modem then
                println_ts("wireless modem disconnected!")
                log._error("comms modem disconnected!")
            else
                log._warning("non-comms modem disconnected")
            end
        end
    elseif event == "peripheral" then
        local type, device = ppm.mount(param1)

        if type == "modem" then
            if device.isWireless() then
                -- reconnected modem
                modem = device
                superv_comms.reconnect_modem(modem)

                println_ts("wireless modem reconnected.")
                log._info("comms modem reconnected.")
            else
                log._info("wired modem reconnected.")
            end
        end
    elseif event == "timer" and param1 == loop_clock then
        -- main loop tick

        -- iterate sessions
        svsessions.iterate_all()

        -- free any closed sessions
        svsessions.free_all_closed()

        loop_clock = os.startTimer(MAIN_CLOCK)
    elseif event == "timer" then
        -- another timer event, check watchdogs
        svsessions.check_all_watchdogs(param1)
    elseif event == "modem_message" then
        -- got a packet
        local packet = superv_comms.parse_packet(param1, param2, param3, param4, param5)
        superv_comms.handle_packet(packet)
    end

    -- check for termination request
    if event == "terminate" or ppm.should_terminate() then
        println_ts("closing sessions...")
        log._info("terminate requested, closing sessions...")
        svsessions.close_all()
        log._info("sessions closed")
        break
    end
end

println_ts("exited")
log._info("exited")
