local util = require("scada-common.util")

local print = util.print
local println = util.println

local testutils = {}

-- test a function
---@param name string function name
---@param f function function
---@param values table input values, one per function call
---@param results any table of values or a single value for all tests
function testutils.test_func(name, f, values, results)
    -- if only one value was given, use that for all checks
    if type(results) ~= "table" then
        local _r = {}
        for _ = 1, #values do
            table.insert(_r, results)
        end
        results = _r
    end

    assert(#values == #results, "test_func(" .. name .. ") #values ~= #results")

    for i = 1, #values do
        local check = values[i]
        local expect = results[i]
        print(name .. "(" .. util.strval(check) .. ") => ")
        assert(f(check) == expect, "FAIL")
        println("PASS")
    end
end

-- test a function with nil as a parameter
---@param name string function name
---@param f function function
---@param result any expected result
function testutils.test_func_nil(name, f, result)
    print(name .. "(nil) => ")
    assert(f(nil) == result, "FAIL")
    println("PASS")
end

-- get something as a string
---@param result any
---@return string
function testutils.stringify(result)
    return textutils.serialize(result, { allow_repetitions = true, compact = true })
end

-- pause for 1 second, or the provided seconds
---@param seconds? number
function testutils.pause(seconds)
    seconds = seconds or 1.0
---@diagnostic disable-next-line: undefined-field
    os.sleep(seconds)
end

-- create a new MODBUS tester
---@param modbus modbus modbus object
---@param error_flag MODBUS_FCODE MODBUS_FCODE.ERROR_FLAG
function testutils.modbus_tester(modbus, error_flag)
    -- test packet
    ---@type modbus_frame
    local packet = {
        txn_id = 0,
        length = 0,
        unit_id = 0,
        func_code = 0,
        data = {},
        scada_frame = nil
    }

    ---@class modbus_tester
    local public = {}

    -- set the packet function and data for the next test
    ---@param func MODBUS_FCODE function code
    ---@param data table
    function public.pkt_set(func, data)
        packet.length = #data
        packet.data = data
        packet.func_code = func
    end

    -- check the current packet, expecting an error
    ---@param excode MODBUS_EXCODE exception code to expect
    function public.test_error__check_request(excode)
        local rcode, reply = modbus.check_request(packet)
        assert(rcode == false, "CHECK_NOT_FAIL")
        assert(reply.get().func_code == bit.bor(packet.func_code, error_flag), "WRONG_FCODE")
        assert(reply.get().data[1] == excode, "EXCODE_MISMATCH")
    end

    -- test the current packet, expecting an error
    ---@param excode MODBUS_EXCODE exception code to expect
    function public.test_error__handle_packet(excode)
        local rcode, reply = modbus.handle_packet(packet)
        assert(rcode == false, "CHECK_NOT_FAIL")
        assert(reply.get().func_code == bit.bor(packet.func_code, error_flag), "WRONG_FCODE")
        assert(reply.get().data[1] == excode, "EXCODE_MISMATCH")
    end

    -- check the current packet, expecting success
    ---@param excode MODBUS_EXCODE exception code to expect
    function public.test_success__check_request(excode)
        local rcode, reply = modbus.check_request(packet)
        assert(rcode, "CHECK_NOT_OK")
        assert(reply.get().data[1] == excode, "EXCODE_MISMATCH")
    end

    -- test the current packet, expecting success
    function public.test_success__handle_packet()
        local rcode, reply = modbus.handle_packet(packet)
        assert(rcode, "CHECK_NOT_OK")
        println(testutils.stringify(reply.get().data))
    end

    return public
end

return testutils
