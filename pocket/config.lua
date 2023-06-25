local config = {}

-- supervisor comms channel
config.SVR_CHANNEL = 16240
-- coordinator comms channel
config.CRD_CHANNEL = 16243
-- pocket comms channel
config.PKT_CHANNEL = 16244
-- max trusted modem message distance (0 to disable check)
config.TRUSTED_RANGE = 0
-- time in seconds (>= 2) before assuming a remote device is no longer active
config.COMMS_TIMEOUT = 5
-- facility authentication key (do NOT use one of your passwords)
-- this enables verifying that messages are authentic
-- all devices on the same network must use the same key
-- message authentication codes require computing a hash on each message, so this can slow things down
-- config.AUTH_KEY = "SCADAfacility123"

-- log path
config.LOG_PATH = "/log.txt"
-- log mode
--  0 = APPEND (adds to existing file on start)
--  1 = NEW (replaces existing file on start)
config.LOG_MODE = 0
-- true to log verbose debug messages
config.LOG_DEBUG = false

return config
