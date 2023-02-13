local config = {}

-- port of the SCADA supervisor
config.SCADA_SV_PORT = 16100
-- port to listen to incoming packets from supervisor
config.SCADA_SV_LISTEN = 16101
-- listen port for SCADA coordinator API access
config.SCADA_API_LISTEN = 16200
-- max trusted modem message distance (0 to disable check)
config.TRUSTED_RANGE = 0
-- time in seconds (>= 1) before assuming a remote device is no longer active
config.COMMS_TIMEOUT = 5

-- expected number of reactor units, used only to require that number of unit monitors
config.NUM_UNITS = 4

-- override default display colors (prettier in my opinion)
config.RECOLOR = true

-- alarm sounder volume (0.0 to 3.0, 1.0 being standard max volume, this is the option given to to speaker.play())
-- note: alarm sine waves are at half saturation, so that multiple will be required to reach full scale
config.SOUNDER_VOLUME = 1.0

-- true for 24 hour time on main view screen
config.TIME_24_HOUR = true

-- log path
config.LOG_PATH = "/log.txt"
-- log mode
--  0 = APPEND (adds to existing file on start)
--  1 = NEW (replaces existing file on start)
config.LOG_MODE = 0

return config
