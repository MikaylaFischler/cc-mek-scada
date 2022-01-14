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

local comms = comms.rplc_comms(config.REACTOR_ID, modem, config.LISTEN_PORT, config.SERVER_PORT, reactor)

-- attempt server connection
-- exits application if connection is denied
plc.scada_link(comms)

-- comms watchdog, 3 second timeout
local conn_watchdog = watchdog.new_watchdog(3)

-- loop clock (10Hz, 2 ticks)
-- send status updates at 4Hz (every 5 ticks)
local loop_tick = os.startTimer(0.05)
local ticks_to_update = 5

-- event loop
while true do
    local event, param1, param2, param3, param4, param5 = os.pullEvent()

    -- check safety (SCRAM occurs if tripped)
    local iss_status, iss_tripped = iss.check()

    -- handle event
    if event == "timer" and param1 == loop_tick then
        -- basic event tick, send updated data if it is time
        ticks_to_update = ticks_to_update - 1
        if ticks_to_update == 0 then
            ticks_to_update = 5
        end
    elseif event == "modem_message" then
        -- got a packet
        -- feed the watchdog first so it doesn't eat our packets
        conn_watchdog.feed()

    elseif event == "timer" and param1 == conn_watchdog.get_timer() then
        -- haven't heard from server recently? shutdown
        reactor.scram()
        print_ts("[alert] server timeout, reactor disabled\n")
    end
end
