--
-- Nuclear Generation Facility SCADA Coordinator
--

require("/initenv").init_env()

local log  = require("scada-common.log")
local ppm  = require("scada-common.ppm")
local util = require("scada-common.util")

local config      = require("coordinator.config")
local coordinator = require("coordinator.coordinator")
local renderer    = require("coordinator.renderer")

local COORDINATOR_VERSION = "alpha-v0.1.6"

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

----------------------------------------
-- config validation
----------------------------------------

local cfv = util.new_validator()

cfv.assert_port(config.SCADA_SV_PORT)
cfv.assert_port(config.SCADA_SV_LISTEN)
cfv.assert_port(config.SCADA_API_LISTEN)
cfv.assert_type_int(config.NUM_UNITS)
cfv.assert_type_str(config.LOG_PATH)
cfv.assert_type_int(config.LOG_MODE)
cfv.assert_type_bool(config.SECURE)
cfv.assert_type_str(config.PASSWORD)
assert(cfv.valid(), "bad config file: missing/invalid fields")

----------------------------------------
-- log init
----------------------------------------

log.init(config.LOG_PATH, config.LOG_MODE)

log.info("========================================")
log.info("BOOTING coordinator.startup " .. COORDINATOR_VERSION)
log.info("========================================")
println(">> SCADA Coordinator " .. COORDINATOR_VERSION .. " <<")

----------------------------------------
-- startup
----------------------------------------

-- mount connected devices
ppm.mount_all()

-- setup monitors
local configured, monitors = coordinator.configure_monitors(config.NUM_UNITS)
if not configured then
    println("boot> monitor setup failed")
    log.fatal("monitor configuration failed")
    return
end

log.info("monitors ready, dmesg input incoming...")

-- init renderer
renderer.set_displays(monitors)
renderer.reset()
renderer.init_dmesg()

log.dmesg("displays connected and reset", "GRAPHICS", colors.green)
log.dmesg("system start on " .. os.date("%c"), "SYSTEM", colors.cyan)
log.dmesg("starting " .. COORDINATOR_VERSION, "BOOT", colors.blue)

-- get the communications modem
local modem = ppm.get_wireless_modem()
if modem == nil then
    println("boot> wireless modem not found")
    log.fatal("no wireless modem on startup")
    return
end

log.dmesg("wireless modem connected", "COMMS", colors.purple)

log.dmesg("starting UI...", "GRAPHICS", colors.green)
util.psleep(3)

local ui_ok = pcall(renderer.start_ui)
if not ui_ok then
    renderer.close_ui()
    log.dmesg("UI draw failed", "GRAPHICS", colors.green)
end
