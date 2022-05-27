local config = {}

-- scada network listen for PLC's and RTU's
config.SCADA_DEV_LISTEN = 16000
-- listen port for SCADA supervisor access by coordinators
config.SCADA_SV_LISTEN = 16100
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

return config
