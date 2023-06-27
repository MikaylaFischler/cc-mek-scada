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
config.SV_TIMEOUT = 5
config.API_TIMEOUT = 5
-- facility authentication key (do NOT use one of your passwords)
-- this enables verifying that messages are authentic
-- all devices on the same network must use the same key
-- config.AUTH_KEY = "SCADAfacility123"

-- expected number of reactor units, used only to require that number of unit monitors
config.NUM_UNITS = 4

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
-- true to log verbose debug messages
config.LOG_DEBUG = false

return config
