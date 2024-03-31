--
-- Crash Handler
--

local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local util  = require("scada-common.util")

local has_graphics, core   = pcall(require, "graphics.core")
local has_lockbox, lockbox = pcall(require, "lockbox")

---@class crash_handler
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

-- log environment versions
---@param log_msg function log function to use
local function log_versions(log_msg)
    log_msg(util.c("RUNTIME:          ", _HOST))
    log_msg(util.c("LUA VERSION:      ", _VERSION))
    log_msg(util.c("APPLICATION:      ", app))
    log_msg(util.c("FIRMWARE VERSION: ", ver))
    log_msg(util.c("COMMS VERSION:    ", comms.version))
    if has_graphics then log_msg(util.c("GRAPHICS VERSION: ", core.version)) end
    if has_lockbox  then log_msg(util.c("LOCKBOX VERSION:  ", lockbox.version)) end
end

-- when running with debug logs, log the useful information that the crash handler knows
function crash.dbg_log_env() log_versions(log.debug) end

-- handle a crash error
---@param error string error message
function crash.handler(error)
    err = error
    log.info("=====> FATAL SOFTWARE FAULT <=====")
    log.fatal(error)
    log.info("----------------------------------")
    log_versions(log.info)
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
