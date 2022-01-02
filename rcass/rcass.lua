--
-- RCaSS: Reactor Controller and Safety Subsystem
--

os.loadAPI("common/util.lua")
os.loadAPI("common/comms.lua")
os.loadAPI("rcass/config.lua")
os.loadAPI("rcass/safety.lua")

local RCASS_VERSION = "alpha-v0.1"

local print_ts = util.print_ts

local reactor = peripheral.find("fissionReactor")
local modem = peripheral.find("modem")

print(">> RCaSS " .. RCASS_VERSION .. " <<")

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
local iss = safety.iss_init(reactor)
local iss_status = "ok"
local iss_tripped = false

-- read config

-- start comms
if not modem.isOpen(config.LISTEN_PORT) then
    modem.open(config.LISTEN_PORT)
end

local comms = comms.rcass_comms(config.REACTOR_ID, modem, config.LISTEN_PORT, config.SERVER_PORT, reactor)

-- attempt server connection
local linked = false
local link_timeout = os.startTimer(5)
comms.send_link_req()
print_ts("sent link request")
repeat
    local event, param1, param2, param3, param4, param5 = os.pullEvent()
   
    -- handle event
    if event == "timer" and param1 == link_timeout then
        -- no response yet
        print("...no response");
        comms.send_link_req()
        print_ts("sent link request")
        link_timeout = os.startTimer(5)
    elseif event == "modem_message" then
        -- server response? cancel timeout
        if link_timeout ~= nil then
            os.cancelTimer(link_timeout)
        end

        local packet = {
            side = param1,
            sender = param2,
            reply_to = param3,
            message = param4,
            distance = param5
        }

        -- handle response
        response = comms.handle_link(packet)
        if response == "wrong_type" then
            print_ts("invalid link response, bad channel?\n")
            return
        elseif response == true then
            print_ts("...linked!\n")
            linked = true
        else
            print_ts("...denied, exiting\n")
            return
        end
    end
until linked

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
    iss_status, iss_tripped = iss.check()

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
