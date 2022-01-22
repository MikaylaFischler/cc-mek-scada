--
-- Reactor Programmable Logic Controller
--

os.loadAPI("scada-common/util.lua")
os.loadAPI("scada-common/comms.lua")
os.loadAPI("reactor-plc/config.lua")
os.loadAPI("reactor-plc/plc.lua")

local R_PLC_VERSION = "alpha-v0.1"

local print_ts = util.print_ts

local reactor = peripheral.find("fissionReactor")
local modem = peripheral.find("modem")

print(">> Reactor PLC " .. R_PLC_VERSION .. " <<")

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

local plc_comms = comms.rplc_comms(config.REACTOR_ID, modem, config.LISTEN_PORT, config.SERVER_PORT, reactor)

-- attempt server connection
-- exit application if connection is denied
if ~plc.scada_link(plc_comms) then
    return
end

-- comms watchdog, 3 second timeout
local conn_watchdog = watchdog.new_watchdog(3)

-- loop clock (10Hz, 2 ticks)
-- send status updates at 4Hz (every 5 ticks)
local loop_tick = os.startTimer(0.05)
local ticks_to_update = 5

-- runtime variables
local control_state = false

-- event loop
while true do
    local event, param1, param2, param3, param4, param5 = os.pullEvent()

    if event == "peripheral_detach" then
        print_ts("[fatal] lost a peripheral, stopping...\n")
        -- todo: determine which disconnected and what is left
        -- hopefully it wasn't the reactor
        reactor.scram()
        -- send an alarm: plc_comms.send_alarm(ALARMS.PLC_DC) ?
        return
    end

    -- check safety (SCRAM occurs if tripped)
    local iss_status, iss_tripped, iss_first = iss.check()
    if iss_first then
        plc_comms.send_iss_alarm(iss_status)
    end

    -- handle event
    if event == "timer" and param1 == loop_tick then
        -- basic event tick, send updated data if it is time (4Hz)
        ticks_to_update = ticks_to_update - 1
        if ticks_to_update == 0 then
            plc_comms.send_status(control_state, iss_tripped)
            ticks_to_update = 5
        end
    elseif event == "modem_message" then
        -- got a packet
        -- feed the watchdog first so it doesn't uhh,,,eat our packets
        conn_watchdog.feed()

        local packet = comms.make_packet(p1, p2, p3, p4, p5)
        plc_comms.handle_packet(packet)

    elseif event == "timer" and param1 == conn_watchdog.get_timer() then
        -- haven't heard from server recently? shutdown
        iss.trip_timeout()
        print_ts("[alert] server timeout, reactor disabled\n")
    end
end
