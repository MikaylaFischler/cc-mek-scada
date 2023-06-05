local config = {}

-- supervisor comms channel
config.SVR_CHANNEL = 16240
-- PLC comms channel
config.PLC_CHANNEL = 16241
-- RTU/MODBUS comms channel
config.RTU_CHANNEL = 16242
-- coordinator comms channel
config.CRD_CHANNEL = 16243
-- pocket comms channel
config.PKT_CHANNEL = 16244
-- max trusted modem message distance (0 to disable check)
config.TRUSTED_RANGE = 0
-- time in seconds (>= 2) before assuming a remote device is no longer active
config.PLC_TIMEOUT = 5
config.RTU_TIMEOUT = 5
config.CRD_TIMEOUT = 5
config.PKT_TIMEOUT = 5

-- expected number of reactors
config.NUM_REACTORS = 4
-- expected number of boilers/turbines for each reactor
config.REACTOR_COOLING = {
    { BOILERS = 1, TURBINES = 1 },  -- reactor unit 1
    { BOILERS = 1, TURBINES = 1 },  -- reactor unit 2
    { BOILERS = 1, TURBINES = 1 },  -- reactor unit 3
    { BOILERS = 1, TURBINES = 1 }   -- reactor unit 4
}

-- log path
config.LOG_PATH = "/log.txt"
-- log mode
--  0 = APPEND (adds to existing file on start)
--  1 = NEW (replaces existing file on start)
config.LOG_MODE = 0
-- true to log verbose debug messages
config.LOG_DEBUG = false

return config
