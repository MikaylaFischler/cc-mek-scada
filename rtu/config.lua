local rsio = require("scada-common.rsio")

local config = {}

-- port to send packets TO server
config.SERVER_PORT = 16000
-- port to listen to incoming packets FROM server
config.LISTEN_PORT = 15001
-- log path
config.LOG_PATH = "/log.txt"
-- log mode
--  0 = APPEND (adds to existing file on start)
--  1 = NEW (replaces existing file on start)
config.LOG_MODE = 0
-- RTU peripheral devices (named: side/network device name)
config.RTU_DEVICES = {
    {
        name = "boiler_1",
        index = 1,
        for_reactor = 1
    },
    {
        name = "turbine_1",
        index = 1,
        for_reactor = 1
    }
}
-- RTU redstone interface definitions
config.RTU_REDSTONE = {
    {
        for_reactor = 1,
        io = {
            {
                channel = rsio.IO.WASTE_PO,
                side = "top",
                bundled_color = colors.blue
            },
            {
                channel = rsio.IO.WASTE_PU,
                side = "top",
                bundled_color = colors.cyan
            },
            {
                channel = rsio.IO.WASTE_AM,
                side = "top",
                bundled_color = colors.purple
            }
        }
    }
}

return config
