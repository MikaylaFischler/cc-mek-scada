local config = {}

-- port of the SCADA supervisor
config.SCADA_SV_PORT = 16100
-- port for SCADA coordinator API access
config.SCADA_API_PORT = 16200
-- port to listen to incoming packets FROM servers
config.LISTEN_PORT = 16201
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
