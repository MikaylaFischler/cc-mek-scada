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

return testutils
