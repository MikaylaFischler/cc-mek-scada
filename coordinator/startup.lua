--
-- Nuclear Generation Facility SCADA Coordinator
--

os.loadAPI("scada-common/log.lua")
os.loadAPI("scada-common/util.lua")
os.loadAPI("scada-common/ppm.lua")
os.loadAPI("scada-common/comms.lua")

os.loadAPI("coordinator/config.lua")
os.loadAPI("coordinator/coordinator.lua")

local COORDINATOR_VERSION = "alpha-v0.1.0"

local print_ts = util.print_ts

ppm.mount_all()

local modem = ppm.get_device("modem")

print("| SCADA Coordinator - " .. COORDINATOR_VERSION .. " |")

-- we need a modem
if modem == nil then
    print("Please connect a modem.")
    return
end
