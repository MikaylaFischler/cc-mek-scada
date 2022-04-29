--
-- Nuclear Generation Facility SCADA Coordinator
--

os.loadAPI("scada-common/log.lua")
os.loadAPI("scada-common/util.lua")
os.loadAPI("scada-common/ppm.lua")
os.loadAPI("scada-common/comms.lua")

os.loadAPI("coordinator/config.lua")
os.loadAPI("coordinator/coordinator.lua")

local COORDINATOR_VERSION = "alpha-v0.1.1"

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

log.init("/log.txt", log.MODE.APPEND)

log._info("========================================")
log._info("BOOTING coordinator.startup " .. COORDINATOR_VERSION)
log._info("========================================")
println(">> RTU " .. COORDINATOR_VERSION .. " <<")

-- mount connected devices
ppm.mount_all()

local modem = ppm.get_wireless_modem()

-- we need a modem
if modem == nil then
    println("please connect a wireless modem")
    return
end
