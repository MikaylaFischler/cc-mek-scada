require("/initenv").init_env()

local types = require("scada-common.types")
local util = require("scada-common.util")

local testutils = require("test.testutils")

local modbus = require("rtu.modbus")
local redstone_rtu = require("rtu.dev.redstone_rtu")

local rsio = require("scada-common.rsio")

local print = util.print
local println = util.println

local MODBUS_FCODE = types.MODBUS_FCODE
local MODBUS_EXCODE = types.MODBUS_EXCODE

println("starting redstone RTU and MODBUS tester")
println("")

-- RTU init --

print(">>> init redstone RTU: ")

local rs_rtu = redstone_rtu.new()

local di, c, ir, hr = rs_rtu.io_count()
assert(di == 0 and c == 0 and ir == 0 and hr == 0, "IOCOUNT_0")

rs_rtu.link_di("back", colors.black)
rs_rtu.link_di("back", colors.blue)

rs_rtu.link_do("back", colors.red)
rs_rtu.link_do("back", colors.purple)

rs_rtu.link_ai("right")
rs_rtu.link_ao("left")

di, c, ir, hr = rs_rtu.io_count()
assert(di == 2, "IOCOUNT_DI")
assert(c == 2, "IOCOUNT_C")
assert(ir == 1, "IOCOUNT_IR")
assert(hr == 1, "IOCOUNT_HR")

println("OK")

-- MODBUS testing --

local rs_modbus = modbus.new(rs_rtu, false)

local mbt = testutils.modbus_tester(rs_modbus, MODBUS_FCODE.ERROR_FLAG)

-------------------------
--- CHECKING REQUESTS ---
-------------------------

println(">>> checking MODBUS requests:")

print("read c {0}: ")
mbt.pkt_set(MODBUS_FCODE.READ_COILS, {0})
mbt.test_error__check_request(MODBUS_EXCODE.NEG_ACKNOWLEDGE)
println("PASS")

print("99 {1,2}: ")
---@diagnostic disable-next-line: param-type-mismatch
mbt.pkt_set(99, {1, 2})
mbt.test_error__check_request(MODBUS_EXCODE.ILLEGAL_FUNCTION)
println("PASS")

print("read c {1,2}: ")
mbt.pkt_set(MODBUS_FCODE.READ_COILS, {1, 2})
mbt.test_success__check_request(MODBUS_EXCODE.ACKNOWLEDGE)
println("PASS")

testutils.pause()

--------------------
--- BAD REQUESTS ---
--------------------

println(">>> trying bad requests:")

print("read di {1,10}: ")
mbt.pkt_set(MODBUS_FCODE.READ_DISCRETE_INPUTS, {1, 10})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("read di {5,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_DISCRETE_INPUTS, {5, 1})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("read di {1,0}: ")
mbt.pkt_set(MODBUS_FCODE.READ_DISCRETE_INPUTS, {1, 0})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("read c {5,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_COILS, {5, 1})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("read c {1,0}: ")
mbt.pkt_set(MODBUS_FCODE.READ_COILS, {1, 0})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("read ir {5,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_INPUT_REGS, {5, 1})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("read ir {1,0}: ")
mbt.pkt_set(MODBUS_FCODE.READ_INPUT_REGS, {1, 0})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("read hr {5,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_MUL_HOLD_REGS, {5, 1})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("write c {5,1}: ")
mbt.pkt_set(MODBUS_FCODE.WRITE_SINGLE_COIL, {5, 1})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("write mul c {5,1}: ")
mbt.pkt_set(MODBUS_FCODE.WRITE_SINGLE_COIL, {5, 1})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("write mul c {5,{1}}: ")
mbt.pkt_set(MODBUS_FCODE.WRITE_SINGLE_COIL, {5, {1}})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("write hr {5,1}: ")
mbt.pkt_set(MODBUS_FCODE.WRITE_SINGLE_HOLD_REG, {5, 1})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

print("write mul hr {5,{1}}: ")
mbt.pkt_set(MODBUS_FCODE.WRITE_SINGLE_HOLD_REG, {5, {1}})
mbt.test_error__handle_packet(MODBUS_EXCODE.ILLEGAL_DATA_ADDR)
println("PASS")

testutils.pause()

----------------------
--- READING INPUTS ---
----------------------

println(">>> reading inputs:")

print("read di {1,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_DISCRETE_INPUTS, {1, 1})
mbt.test_success__handle_packet()

print("read di {2,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_DISCRETE_INPUTS, {2, 1})
mbt.test_success__handle_packet()

print("read di {1,2}: ")
mbt.pkt_set(MODBUS_FCODE.READ_DISCRETE_INPUTS, {1, 2})
mbt.test_success__handle_packet()

print("read ir {1,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_INPUT_REGS, {1, 1})
mbt.test_success__handle_packet()

testutils.pause()

-----------------------
--- WRITING OUTPUTS ---
-----------------------

println(">>> writing outputs:")

print("write mul c {1,{LOW,LOW}}: ")
mbt.pkt_set(MODBUS_FCODE.WRITE_MUL_COILS, {1, {rsio.IO_LVL.LOW, rsio.IO_LVL.LOW}})
mbt.test_success__handle_packet()

testutils.pause()

print("write c {1,HIGH}: ")
mbt.pkt_set(MODBUS_FCODE.WRITE_SINGLE_COIL, {1, rsio.IO_LVL.HIGH})
mbt.test_success__handle_packet()

testutils.pause()

print("write c {2,HIGH}: ")
mbt.pkt_set(MODBUS_FCODE.WRITE_SINGLE_COIL, {2, rsio.IO_LVL.HIGH})
mbt.test_success__handle_packet()

testutils.pause()

print("write hr {1,7}: ")
mbt.pkt_set(MODBUS_FCODE.WRITE_SINGLE_HOLD_REG, {1, 7})
mbt.test_success__handle_packet()

testutils.pause()

print("write mul hr {1,{4}}: ")
mbt.pkt_set(MODBUS_FCODE.WRITE_MUL_HOLD_REGS, {1, {4}})
mbt.test_success__handle_packet()

println("PASS")

testutils.pause()

-----------------------
--- READING OUTPUTS ---
-----------------------

println(">>> reading outputs:")

print("read c {1,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_COILS, {1, 1})
mbt.test_success__handle_packet()

print("read c {2,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_COILS, {2, 1})
mbt.test_success__handle_packet()

print("read c {1,2}: ")
mbt.pkt_set(MODBUS_FCODE.READ_COILS, {1, 2})
mbt.test_success__handle_packet()

print("read hr {1,1}: ")
mbt.pkt_set(MODBUS_FCODE.READ_MUL_HOLD_REGS, {1, 1})
mbt.test_success__handle_packet()

println("PASS")

println("TEST COMPLETE")
