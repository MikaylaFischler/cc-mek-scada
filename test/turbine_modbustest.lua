require("/initenv").init_env()

local log = require("scada-common.log")
local ppm = require("scada-common.ppm")
local types = require("scada-common.types")
local util = require("scada-common.util")

local testutils = require("test.testutils")

local modbus = require("rtu.modbus")
local turbine_rtu = require("rtu.dev.turbine_rtu")

local print = util.print
local println = util.println

local MODBUS_FCODE = types.MODBUS_FCODE

println("starting turbine RTU MODBUS tester")
println("note: use rs_modbustest to fully test RTU/MODBUS")
println("      this only tests a turbine/parallel read")
println("")

-- RTU init --

log.init("/log.txt", log.MODE.NEW, true)

print(">>> init turbine RTU: ")

ppm.mount_all()

local dev = ppm.get_device("turbine")
assert(dev ~= nil, "NO_TURBINE")

local t_rtu = turbine_rtu.new(dev)

local di, c, ir, hr = t_rtu.io_count()
assert(di == 0, "IOCOUNT_DI")
assert(c == 0, "IOCOUNT_C")
assert(ir == 16, "IOCOUNT_IR")
assert(hr == 0, "IOCOUNT_HR")

println("OK")

local t_modbus = modbus.new(t_rtu, true)

local mbt = testutils.modbus_tester(t_modbus, MODBUS_FCODE.ERROR_FLAG)

----------------------
--- READING INPUTS ---
----------------------

println(">>> reading inputs:")

print("read ir {1,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_INPUT_REGS, {1, 1})
mbt.test_success__handle_packet()

print("read ir {2,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_INPUT_REGS, {2, 1})
mbt.test_success__handle_packet()

print("read ir {1,16}: ")
mbt.pkt_set(MODBUS_FCODE.READ_INPUT_REGS, {1, 16})
mbt.test_success__handle_packet()

println("PASS")

println("TEST COMPLETE")
