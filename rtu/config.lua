local rsio = require("scada-common.rsio")

local config = {}

-- port to send packets TO server
config.SERVER_PORT = 16000
-- port to listen to incoming packets FROM server
config.LISTEN_PORT = 15001
-- max trusted modem message distance (< 1 to disable check)
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

-- RTU peripheral devices (named: side/network device name)
config.RTU_DEVICES = {
    {
        name = "boilerValve_0",
        index = 1,
        for_reactor = 1
    },
    {
        name = "turbineValve_0",
        index = 1,
        for_reactor = 1
    }
}
-- RTU redstone interface definitions
config.RTU_REDSTONE = {
    -- {
    --     for_reactor = 1,
    --     io = {
    --         {
    --             port = rsio.IO.WASTE_PO,
    --             side = "top",
    --             bundled_color = colors.red
    --         },
    --         {
    --             port = rsio.IO.WASTE_PU,
    --             side = "top",
    --             bundled_color = colors.orange
    --         },
    --         {
    --             port = rsio.IO.WASTE_POPL,
    --             side = "top",
    --             bundled_color = colors.yellow
    --         },
    --         {
    --             port = rsio.IO.WASTE_AM,
    --             side = "top",
    --             bundled_color = colors.lime
    --         }
    --     }
    -- }
}

return config
