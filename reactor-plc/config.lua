local config = {}

-- set to false to run in offline mode (safety regulation only)
config.NETWORKED = true
-- unique reactor ID
config.REACTOR_ID = 1

-- for offline mode, this redstone interface will turn off (open a valve)
-- when emergency coolant is needed due to low coolant
-- config.EMERGENCY_COOL = { side = "right", color = nil }

-- port to send packets TO server
config.SERVER_PORT = 16000
-- port to listen to incoming packets FROM server
config.LISTEN_PORT = 14001
-- max trusted modem message distance (0 to disable check)
config.TRUSTED_RANGE = 0
-- time in seconds (>= 2) before assuming a remote device is no longer active
config.COMMS_TIMEOUT = 5

-- log path
config.LOG_PATH = "/log.txt"
-- log mode
--  0 = APPEND (adds to existing file on start)
--  1 = NEW (replaces existing file on start)
config.LOG_MODE = 0
-- true to log verbose debug messages
config.LOG_DEBUG = false

return config
