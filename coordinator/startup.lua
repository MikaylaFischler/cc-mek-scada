--
-- Nuclear Generation Facility SCADA Coordinator
--

local log = require("scada-common.log")
local ppm = require("scada-common.ppm")
local util = require("scada-common.util")

local config = require("config")
local coordinator = require("coordinator")

local COORDINATOR_VERSION = "alpha-v0.1.2"

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

log.init("/log.txt", log.MODE.APPEND)

log.info("========================================")
log.info("BOOTING coordinator.startup " .. COORDINATOR_VERSION)
log.info("========================================")
println(">> SCADA Coordinator " .. COORDINATOR_VERSION .. " <<")

-- mount connected devices
ppm.mount_all()

local modem = ppm.get_wireless_modem()

-- we need a modem
if modem == nil then
    println("please connect a wireless modem")
    return
end
