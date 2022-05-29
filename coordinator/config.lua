local config = {}

-- port of the SCADA supervisor
config.SCADA_SV_PORT = 16100
-- port to listen to incoming packets from supervisor
config.SCADA_SV_LISTEN = 16101
-- listen port for SCADA coordinator API access
config.SCADA_API_LISTEN = 16200
-- expected number of reactor units
config.NUM_UNITS = 4
-- log path
config.LOG_PATH = "/log.txt"
-- log mode
--  0 = APPEND (adds to existing file on start)
--  1 = NEW (replaces existing file on start)
config.LOG_MODE = 0
-- crypto config
config.SECURE = true
-- must be common between all devices
config.PASSWORD = "testpassword!"

return config
