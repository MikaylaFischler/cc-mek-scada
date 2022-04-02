--
-- Reactor Programmable Logic Controller
--

os.loadAPI("scada-common/log.lua")
os.loadAPI("scada-common/util.lua")
os.loadAPI("scada-common/ppm.lua")
os.loadAPI("scada-common/comms.lua")

os.loadAPI("reactor-plc/config.lua")
os.loadAPI("reactor-plc/plc.lua")

local R_PLC_VERSION = "alpha-v0.1.0"

local print_ts = util.print_ts

print(">> Reactor PLC " .. R_PLC_VERSION .. " <<")

-- mount connected devices
ppm.mount_all()

local reactor = ppm.get_device("fissionReactor")
local modem = ppm.get_device("modem")

-- we need a reactor and a modem
if reactor == nil then
    print("Fission reactor not found, exiting...");
    return
elseif modem == nil then
    print("No modem found, disabling reactor and exiting...")
    reactor.scram()
    return
end

-- just booting up, no fission allowed (neutrons stay put thanks)
reactor.scram()

-- init internal safety system
local iss = plc.iss_init(reactor)

-- start comms
if not modem.isOpen(config.LISTEN_PORT) then
    modem.open(config.LISTEN_PORT)
end

local plc_comms = plc.rplc_comms(config.REACTOR_ID, modem, config.LISTEN_PORT, config.SERVER_PORT, reactor)

-- comms watchdog, 3 second timeout
local conn_watchdog = watchdog.new_watchdog(3)

-- loop clock (10Hz, 2 ticks)
local loop_tick = os.startTimer(0.05)

-- send status updates at ~3.33Hz (every 6 server ticks) (every 3 loop ticks)
-- send link requests at 0.5Hz (every 40 server ticks) (every 20 loop ticks)
local UPDATE_TICKS = 3
local LINK_TICKS = 20

-- start by linking
local ticks_to_update = LINK_TICKS

-- runtime variables
local control_state = false

-- event loop
while true do
    local event, param1, param2, param3, param4, param5 = os.pullEventRaw()

    if event == "peripheral_detach" then
        ppm.handle_unmount(param1)

        -- try to scram reactor if it is still connected
        if reactor.scram() then
            print_ts("[fatal] PLC lost a peripheral: successful SCRAM\n")
        else
            print_ts("[fatal] PLC lost a peripheral: failed SCRAM\n")
        end

        -- send an alarm: plc_comms.send_alarm(ALARMS.PLC_PERI_DC) ?
    end

    -- check safety (SCRAM occurs if tripped)
    local iss_status, iss_tripped, iss_first = iss.check()
    if iss_first then
        plc_comms.send_iss_alarm(iss_status)
    end

    -- handle event
    if event == "timer" and param1 == loop_tick then
        -- basic event tick, send updated data if it is time (~3.33Hz)
        -- iss was already checked (main reason for this tick rate)
        ticks_to_update = ticks_to_update - 1

        if plc_comms.linked() then
            if ticks_to_update <= 0 then
                plc_comms.send_status(control_state, iss_tripped)
                ticks_to_update = UPDATE_TICKS
            end
        else
            if ticks_to_update <= 0 then
                plc_comms.send_link_req()
                ticks_to_update = LINK_TICKS
            end
        end
    elseif event == "modem_message" then
        -- got a packet
        -- feed the watchdog first so it doesn't uhh...eat our packets
        conn_watchdog.feed()

        local packet = plc_comms.parse_packet(p1, p2, p3, p4, p5)
        plc_comms.handle_packet(packet)
    elseif event == "timer" and param1 == conn_watchdog.get_timer() then
        -- haven't heard from server recently? shutdown reactor
        plc_comms.unlink()
        iss.trip_timeout()
        print_ts("[alert] server timeout, reactor disabled\n")
    elseif event == "terminate" then
        -- safe exit
        if reactor.scram() then
            print_ts("[alert] exiting, reactor disabled\n")
        else
            -- send an alarm: plc_comms.send_alarm(ALARMS.PLC_LOST_CONTROL) ?
            print_ts("[alert] exiting, reactor failed to disable\n")
        end
        -- send an alarm: plc_comms.send_alarm(ALARMS.PLC_SHUTDOWN) ?
        return
    end
end
