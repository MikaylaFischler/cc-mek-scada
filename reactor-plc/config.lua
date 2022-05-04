local config = {}

-- set to false to run in offline mode (safety regulation only)
config.NETWORKED = true
-- unique reactor ID
config.REACTOR_ID  = 1
-- port to send packets TO server
config.SERVER_PORT = 16000
-- port to listen to incoming packets FROM server
config.LISTEN_PORT = 14001
-- log path
config.LOG_PATH = "/log.txt"
-- log mode
--  0 = APPEND (adds to existing file on start)
--  1 = NEW (replaces existing file on start)
config.LOG_MODE = 0

return config
