--
-- Crash Handler
--

local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local util  = require("scada-common.util")

local crash = {}

local app = "unknown"
local ver = "v0.0.0"
local err = ""

-- set crash environment
---@param application string app name
---@param version string version
function crash.set_env(application, version)
    app = application
    ver = version
end

-- handle a crash error
---@param error string error message
function crash.handler(error)
    err = error
    log.info("=====> FATAL SOFTWARE FAULT <=====")
    log.fatal(error)
    log.info("----------------------------------")
    log.info(util.c("RUNTIME:          ", _HOST))
    log.info(util.c("LUA VERSION:      ", _VERSION))
    log.info(util.c("APPLICATION:      ", app))
    log.info(util.c("FIRMWARE VERSION: ", ver))
    log.info(util.c("COMMS VERSION:    ", comms.version))
    log.info("----------------------------------")
    log.info(debug.traceback("--- begin debug trace ---", 1))
    log.info("--- end debug trace ---")
end

-- final error print on failed xpcall, app exits here
function crash.exit()
    log.close()
    util.println("fatal error occured in main application:")
    error(err, 0)
end

return crash
