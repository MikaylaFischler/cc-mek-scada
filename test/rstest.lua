require("/initenv").init_env()

local rsio = require("scada-common.rsio")
local util = require("scada-common.util")

local testutils = require("test.testutils")

local print = util.print
local println = util.println

local IO = rsio.IO
local IO_LVL = rsio.IO_LVL
local IO_MODE = rsio.IO_MODE

println("starting RSIO tester")
println("")

println(">>> checking valid ports:")

-- port function tests
local cid = 0
local max_value = 1
for key, value in pairs(IO) do
    if value > max_value then max_value = value end
    cid = cid + 1

    local c_name = rsio.to_string(value)
    local io_mode = rsio.get_io_mode(value)
    local mode = ""

    if io_mode == IO_MODE.DIGITAL_IN then
        mode = " (DIGITAL_IN)"
    elseif io_mode == IO_MODE.DIGITAL_OUT then
        mode = " (DIGITAL_OUT)"
    elseif io_mode == IO_MODE.ANALOG_IN then
        mode = " (ANALOG_IN)"
    elseif io_mode == IO_MODE.ANALOG_OUT then
        mode = " (ANALOG_OUT)"
    else
        error("unknown mode for port " .. key)
    end

    assert(key == c_name, c_name .. " != " .. key .. ": " .. value .. mode)
    println(c_name .. ": " .. value .. mode)
end

assert(max_value == cid, "IO_PORT last IDx out-of-sync with count: " .. max_value .. " (count " .. cid .. ")")

testutils.pause()

println(">>> checking invalid ports:")

testutils.test_func("rsio.to_string", rsio.to_string, { -1, 100, false }, "")
testutils.test_func_nil("rsio.to_string", rsio.to_string, "")
testutils.test_func("rsio.get_io_mode", rsio.get_io_mode, { -1, 100, false }, IO_MODE.ANALOG_IN)
testutils.test_func_nil("rsio.get_io_mode", rsio.get_io_mode, IO_MODE.ANALOG_IN)

testutils.pause()

println(">>> checking validity checks:")

local ivc_t_list = { 0, -1, 100 }
testutils.test_func("rsio.is_valid_port", rsio.is_valid_port, ivc_t_list, false)
testutils.test_func_nil("rsio.is_valid_port", rsio.is_valid_port, false)

local ivs_t_list = rs.getSides()
testutils.test_func("rsio.is_valid_side", rsio.is_valid_side, ivs_t_list, true)
testutils.test_func("rsio.is_valid_side", rsio.is_valid_side, { "" }, false)
testutils.test_func_nil("rsio.is_valid_side", rsio.is_valid_side, false)

local ic_t_list = { colors.white, colors.purple, colors.blue, colors.cyan, colors.black }
testutils.test_func("rsio.is_color", rsio.is_color, ic_t_list, true)
testutils.test_func("rsio.is_color", rsio.is_color, { 0, 999999, colors.combine(colors.red, colors.blue, colors.black) }, false)
testutils.test_func_nil("rsio.is_color", rsio.is_color, false)

testutils.pause()

println(">>> checking port-independent I/O wrappers:")

testutils.test_func("rsio.digital_read", rsio.digital_read, { true, false }, { IO_LVL.HIGH, IO_LVL.LOW })

print("rsio.analog_read(): ")
assert(rsio.analog_read(0, 0, 100) == 0, "RS_READ_0_100")
assert(rsio.analog_read(7.5, 0, 100) == 50, "RS_READ_7_5_100")
assert(rsio.analog_read(15, 0, 100) == 100, "RS_READ_15_100")
assert(rsio.analog_read(4, 0, 15) == 4, "RS_READ_4_15")
assert(rsio.analog_read(12, 0, 15) == 12, "RS_READ_12_15")
println("PASS")

print("rsio.analog_write(): ")
assert(rsio.analog_write(0, 0, 100) == 0, "RS_WRITE_0_100")
assert(rsio.analog_write(100, 0, 100) == 15, "RS_WRITE_100_100")
assert(rsio.analog_write(4, 0, 15) == 4, "RS_WRITE_4_15")
assert(rsio.analog_write(12, 0, 15) == 12, "RS_WRITE_12_15")
println("PASS")

testutils.pause()

println(">>> checking port I/O:")

print("rsio.digital_is_active(...): ")

-- check input ports
assert(rsio.digital_is_active(IO.F_SCRAM, IO_LVL.LOW) == true, "IO_F_SCRAM_HIGH")
assert(rsio.digital_is_active(IO.F_SCRAM, IO_LVL.HIGH) == false, "IO_F_SCRAM_LOW")
assert(rsio.digital_is_active(IO.R_SCRAM, IO_LVL.LOW) == true, "IO_R_SCRAM_HIGH")
assert(rsio.digital_is_active(IO.R_SCRAM, IO_LVL.HIGH) == false, "IO_R_SCRAM_LOW")
assert(rsio.digital_is_active(IO.R_ENABLE, IO_LVL.LOW) == false, "IO_R_ENABLE_HIGH")
assert(rsio.digital_is_active(IO.R_ENABLE, IO_LVL.HIGH) == true, "IO_R_ENABLE_LOW")

-- non-inputs should always return LOW
assert(rsio.digital_is_active(IO.F_ALARM, IO_LVL.LOW) == false, "IO_OUT_READ_LOW")
assert(rsio.digital_is_active(IO.F_ALARM, IO_LVL.HIGH) == false, "IO_OUT_READ_HIGH")

println("PASS")

-- check output ports

print("rsio.digital_write(...): ")

-- check output ports
assert(rsio.digital_write_active(IO.F_ALARM, true) == IO_LVL.LOW, "IO_F_ALARM_LOW")
assert(rsio.digital_write_active(IO.F_ALARM, true) == IO_LVL.HIGH, "IO_F_ALARM_HIGH")
assert(rsio.digital_write_active(IO.WASTE_PU, true) == IO_LVL.HIGH, "IO_WASTE_PU_HIGH")
assert(rsio.digital_write_active(IO.WASTE_PU, true) == IO_LVL.LOW, "IO_WASTE_PU_LOW")
assert(rsio.digital_write_active(IO.WASTE_PO, true) == IO_LVL.HIGH, "IO_WASTE_PO_HIGH")
assert(rsio.digital_write_active(IO.WASTE_PO, true) == IO_LVL.LOW, "IO_WASTE_PO_LOW")
assert(rsio.digital_write_active(IO.WASTE_POPL, true) == IO_LVL.HIGH, "IO_WASTE_POPL_HIGH")
assert(rsio.digital_write_active(IO.WASTE_POPL, true) == IO_LVL.LOW, "IO_WASTE_POPL_LOW")
assert(rsio.digital_write_active(IO.WASTE_AM, true) == IO_LVL.HIGH, "IO_WASTE_AM_HIGH")
assert(rsio.digital_write_active(IO.WASTE_AM, true) == IO_LVL.LOW, "IO_WASTE_AM_LOW")

-- check all reactor output ports (all are active high)
for i = IO.R_ALARM, (IO.R_PLC_TIMEOUT - IO.R_ALARM + 1) do
    assert(rsio.to_string(i) ~= "", "REACTOR_IO_BAD_PORT")
    assert(rsio.digital_write_active(i, false) == IO_LVL.LOW, "IO_" .. rsio.to_string(i) .. "_LOW")
    assert(rsio.digital_write_active(i, true) == IO_LVL.HIGH, "IO_" .. rsio.to_string(i) .. "_HIGH")
end

-- non-outputs should always return false
assert(rsio.digital_write_active(IO.F_SCRAM, false) == IO_LVL.LOW, "IO_IN_WRITE_FALSE")
assert(rsio.digital_write_active(IO.F_SCRAM, true) == IO_LVL.LOW, "IO_IN_WRITE_TRUE")

println("PASS")

println("TEST COMPLETE")
