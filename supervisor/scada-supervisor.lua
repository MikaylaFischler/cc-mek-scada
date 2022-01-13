--
-- Nuclear Generation Facility SCADA Supervisor
--

os.loadAPI("scada-common/util.lua")
os.loadAPI("scada-common/comms.lua")
os.loadAPI("supervisor/config.lua")

local SUPERVISOR_VERSION = "alpha-v0.1"

local print_ts = util.print_ts

local modem = peripheral.find("modem")

print("| SCADA Supervisor - " .. SUPERVISOR_VERSION .. " |")

-- we need a modem
if modem == nil then
    print("No modem found, exiting...")
    return
end

-- read config

-- start comms
if not modem.isOpen(config.LISTEN_PORT) then
    modem.open(config.LISTEN_PORT)
end

local comms = comms.superv_comms(config.NUM_REACTORS, modem, config.SCADA_PLC_LISTEN, config.SCADA_SV_CHANNEL)

-- base loop clock (4Hz, 5 ticks)
local loop_tick = os.startTimer(0.25)

-- event loop
while true do
    local event, param1, param2, param3, param4, param5 = os.pullEvent()

    -- handle event
    if event == "timer" and param1 == loop_tick then
        -- basic event tick, send keep-alives
    elseif event == "modem_message" then
        -- got a packet
    end
end
