local rsio = require("scada-common.rsio")

local config = {}

-- supervisor comms channel
config.SVR_CHANNEL = 16240
-- RTU/MODBUS comms channel
config.RTU_CHANNEL = 16242
-- max trusted modem message distance (0 to disable check)
config.TRUSTED_RANGE = 0
-- time in seconds (>= 2) before assuming a remote device is no longer active
config.COMMS_TIMEOUT = 5
-- facility authentication key (do NOT use one of your passwords)
-- this enables verifying that messages are authentic
-- all devices on the same network must use the same key
-- config.AUTH_KEY = "SCADAfacility123"

-- alarm sounder volume (0.0 to 3.0, 1.0 being standard max volume, this is the option given to to speaker.play())
-- note: alarm sine waves are at half saturation, so that multiple will be required to reach full scale
config.SOUNDER_VOLUME = 1.0

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
