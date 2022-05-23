local util = require("scada-common.util")

local print = util.print
local println = util.println

local testutils = {}

-- get a value as a string
---@param val any
---@return string value value as string or "%VALSTR_UNKNOWN%"
local function valstr(val)
    local t = type(val)

    if t == "nil" then
        return "nil"
    elseif t == "number" then
        return "" .. val
    elseif t == "boolean" then
        if val then return "true" else return "false" end
    elseif t == "string" then
        return val
    elseif t == "table" or t == "function" then
        return val
    else
        return "%VALSTR_UNKNOWN%"
    end
end

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
        print(name .. "(" .. valstr(check) .. ") => ")
        assert(f(check) == expect, "FAIL")
        println("PASS")
    end
end

-- test a function with nil as a parameter
---@param name string function name
---@param f function function
---@param result any expected result
function testutils.test_func_nil(name, f, result)
    print(name .. "(" .. valstr(nil) .. ") => ")
    assert(f(nil) == result, "FAIL")
    println("PASS")
end

return testutils
