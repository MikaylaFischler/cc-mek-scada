-- configuration definitions

CTRL_VERSION = "0.7"

-- monitors
MONITOR_0 = "monitor_6"
MONITOR_1 = "monitor_5"
MONITOR_2 = "monitor_7"
MONITOR_3 = "monitor_8"

-- modem server
LISTEN_PORT = 1000

-- regulator (should match the number of reactors present)
BUNDLE_DEF = { colors.red, colors.orange, colors.yellow, colors.lime }

-- stats calculation
REACTOR_MB_T = 39
TURBINE_MRF_T = 3.114
PLUTONIUM_PER_WASTE = 0.1
POLONIUM_PER_WASTE = 0.1
SPENT_PER_BYPRODUCT = 1
ANTIMATTER_PER_POLONIUM = 0.001
