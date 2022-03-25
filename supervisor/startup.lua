--
-- Nuclear Generation Facility SCADA Supervisor
--

os.loadAPI("scada-common/log.lua")
os.loadAPI("scada-common/util.lua")
os.loadAPI("scada-common/ppm.lua")
os.loadAPI("scada-common/comms.lua")

os.loadAPI("supervisor/config.lua")
os.loadAPI("supervisor/supervisor.lua")

local SUPERVISOR_VERSION = "alpha-v0.1.0"

local print_ts = util.print_ts

ppm.mount_all()

local modem = ppm.get_device("modem")

print("| SCADA Supervisor - " .. SUPERVISOR_VERSION .. " |")

-- we need a modem
if modem == nil then
    print("Please connect a modem.")
    return
end

-- determine active/backup mode
local mode = comms.SCADA_SV_MODES.BACKUP
if config.SYSTEM_TYPE == "active" then
    mode = comms.SCADA_SV_MODES.ACTIVE
end

-- start comms, open all channels
if not modem.isOpen(config.SCADA_DEV_LISTEN) then
    modem.open(config.SCADA_DEV_LISTEN)
end
if not modem.isOpen(config.SCADA_FO_CHANNEL) then
    modem.open(config.SCADA_FO_CHANNEL)
end
if not modem.isOpen(config.SCADA_SV_CHANNEL) then
    modem.open(config.SCADA_SV_CHANNEL)
end

local comms = supervisor.superv_comms(config.NUM_REACTORS, modem, config.SCADA_DEV_LISTEN, config.SCADA_FO_CHANNEL, config.SCADA_SV_CHANNEL)

-- base loop clock (4Hz, 5 ticks)
local loop_tick = os.startTimer(0.25)

-- event loop
while true do
    local event, param1, param2, param3, param4, param5 = os.pullEventRaw()

    -- handle event
    if event == "timer" and param1 == loop_tick then
        -- basic event tick, send keep-alives
    elseif event == "modem_message" then
        -- got a packet
    elseif event == "terminate" then
        -- safe exit
        print_ts("[alert] terminated\n")
        -- todo: attempt failover, alert hot backup
        return
    end
end
