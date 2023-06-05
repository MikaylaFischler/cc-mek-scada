--
-- Utility Functions
--

local cc_strings = require("cc.strings")

---@class util
local util = {}

-- ENVIRONMENT CONSTANTS --

util.TICK_TIME_S = 0.05
util.TICK_TIME_MS = 50

-- OPERATORS --
--#region

-- trinary operator
---@nodiscard
---@param cond boolean|nil condition
---@param a any return if true
---@param b any return if false
---@return any value
function util.trinary(cond, a, b)
    if cond then return a else return b end
end

--#endregion

-- PRINT --
--#region

-- print
---@param message any
function util.print(message)
    term.write(tostring(message))
end

-- print line
---@param message any
function util.println(message)
    print(tostring(message))
end

-- timestamped print
---@param message any
function util.print_ts(message)
    term.write(os.date("[%H:%M:%S] ") .. tostring(message))
end

-- timestamped print line
---@param message any
function util.println_ts(message)
    print(os.date("[%H:%M:%S] ") .. tostring(message))
end

--#endregion

-- STRING TOOLS --
--#region

-- get a value as a string
---@nodiscard
---@param val any
---@return string
function util.strval(val)
    local t = type(val)
    if t == "table" or t == "function" then
        return "[" .. tostring(val) .. "]"
    else
        return tostring(val)
    end
end

-- repeat a string n times
---@nodiscard
---@param str string
---@param n integer
---@return string
function util.strrep(str, n)
    local repeated = ""
    for _ = 1, n do
        repeated = repeated .. str
    end
    return repeated
end

-- repeat a space n times
---@nodiscard
---@param n integer
---@return string
function util.spaces(n)
    return util.strrep(" ", n)
end

-- pad text to a minimum width
---@nodiscard
---@param str string text
---@param n integer minimum width
---@return string
function util.pad(str, n)
    local len = string.len(str)
    local lpad = math.floor((n - len) / 2)
    local rpad = (n - len) - lpad

    return util.spaces(lpad) .. str .. util.spaces(rpad)
end

-- wrap a string into a table of lines
---@nodiscard
---@param str string
---@param limit integer line limit
---@return table lines
function util.strwrap(str, limit) return cc_strings.wrap(str, limit) end

-- luacheck: no unused args

-- concatenation with built-in to string
---@nodiscard
---@vararg any
---@return string
---@diagnostic disable-next-line: unused-vararg
function util.concat(...)
    local str = ""
    for _, v in ipairs(arg) do str = str .. util.strval(v) end
    return str
end

-- alias
util.c = util.concat

-- sprintf implementation
---@nodiscard
---@param format string
---@vararg any
---@diagnostic disable-next-line: unused-vararg
function util.sprintf(format, ...)
    return string.format(format, table.unpack(arg))
end

-- luacheck: unused args

-- format a number string with commas as the thousands separator<br>
-- subtracts from spaces at the start if present for each comma used
---@nodiscard
---@param num string number string
---@return string
function util.comma_format(num)
    local formatted = num
    local commas = 0
    local i = 1

    while i > 0 do
        formatted, i = formatted:gsub("^(%s-%d+)(%d%d%d)", '%1,%2')
        if i > 0 then commas = commas + 1 end
    end

    local _, num_spaces = formatted:gsub(" %s-", "")
    local remove = math.min(num_spaces, commas)

    formatted = string.sub(formatted, remove + 1)

    return formatted
end

--#endregion

-- MATH --
--#region

-- is a value an integer
---@nodiscard
---@param x any value
---@return boolean is_integer if the number is an integer
function util.is_int(x)
    return type(x) == "number" and x == math.floor(x)
end

-- get the sign of a number
---@nodiscard
---@param x number value
---@return integer sign (-1 for < 0, 1 otherwise)
function util.sign(x)
    return util.trinary(x < 0, -1, 1)
end

-- round a number to an integer
---@nodiscard
---@return integer rounded
function util.round(x)
    return math.floor(x + 0.5)
end

-- get a new moving average object
---@nodiscard
---@param length integer history length
---@param default number value to fill history with for first call to compute()
function util.mov_avg(length, default)
    local data = {}
    local index = 1
    local last_t = 0    ---@type number|nil

    ---@class moving_average
    local public = {}

    -- reset all to a given value
    ---@param x number value
    function public.reset(x)
        data = {}
        for _ = 1, length do table.insert(data, x) end
    end

    -- record a new value
    ---@param x number new value
    ---@param t number? optional last update time to prevent duplicated entries
    function public.record(x, t)
        if type(t) == "number" and last_t == t then
            return
        end

        data[index] = x
        last_t = t

        index = index + 1
        if index > length then index = 1 end
    end

    -- compute the moving average
    ---@nodiscard
    ---@return number average
    function public.compute()
        local sum = 0
        for i = 1, length do sum = sum + data[i] end
        return sum / length
    end

    public.reset(default)

    return public
end

-- TIME --

-- current time
---@nodiscard
---@return integer milliseconds
function util.time_ms()
---@diagnostic disable-next-line: undefined-field
    return os.epoch('local')
end

-- current time
---@nodiscard
---@return number seconds
function util.time_s()
---@diagnostic disable-next-line: undefined-field
    return os.epoch('local') / 1000.0
end

-- current time
---@nodiscard
---@return integer milliseconds
function util.time() return util.time_ms() end

--#endregion

-- OS --
--#region

-- OS pull event raw wrapper with types
---@nodiscard
---@param target_event? string event to wait for
---@return os_event event, any param1, any param2, any param3, any param4, any param5
function util.pull_event(target_event)
---@diagnostic disable-next-line: undefined-field
    return os.pullEventRaw(target_event)
end

-- OS queue event raw wrapper with types
---@param event os_event
---@param param1 any
---@param param2 any
---@param param3 any
---@param param4 any
---@param param5 any
function util.push_event(event, param1, param2, param3, param4, param5)
---@diagnostic disable-next-line: undefined-field
    return os.queueEvent(event, param1, param2, param3, param4, param5)
end

-- start an OS timer
---@nodiscard
---@param t number timer duration in seconds
---@return integer timer ID
function util.start_timer(t)
---@diagnostic disable-next-line: undefined-field
    return os.startTimer(t)
end

-- cancel an OS timer
---@param timer integer timer ID
function util.cancel_timer(timer)
---@diagnostic disable-next-line: undefined-field
    os.cancelTimer(timer)
end

--#endregion

-- PARALLELIZATION --
--#region

-- protected sleep call so we still are in charge of catching termination
---@param t integer seconds
--- EVENT_CONSUMER: this function consumes events
function util.psleep(t)
---@diagnostic disable-next-line: undefined-field
    pcall(os.sleep, t)
end

-- no-op to provide a brief pause (1 tick) to yield<br>
--- EVENT_CONSUMER: this function consumes events
function util.nop() util.psleep(0.05) end

-- attempt to maintain a minimum loop timing (duration of execution)
---@nodiscard
---@param target_timing integer minimum amount of milliseconds to wait for
---@param last_update integer millisecond time of last update
---@return integer time_now
--- EVENT_CONSUMER: this function consumes events
function util.adaptive_delay(target_timing, last_update)
    local sleep_for = target_timing - (util.time() - last_update)
    -- only if >50ms since worker loops already yield 0.05s
    if sleep_for >= 50 then util.psleep(sleep_for / 1000.0) end
    return util.time()
end

--#endregion

-- TABLE UTILITIES --
--#region

-- delete elements from a table if the passed function returns false when passed a table element<br>
-- put briefly: deletes elements that return false, keeps elements that return true
---@param t table table to remove elements from
---@param f function should return false to delete an element when passed the element: f(elem) = true|false
---@param on_delete? function optional function to execute on deletion, passed the table element to be deleted as the parameter
function util.filter_table(t, f, on_delete)
    local move_to = 1
    for i = 1, #t do
        local element = t[i]
        if element ~= nil then
            if f(element) then
                if t[move_to] == nil then
                    t[move_to] = element
                    t[i] = nil
                end
                move_to = move_to + 1
            else
                if on_delete then on_delete(element) end
                t[i] = nil
            end
        end
    end
end

-- check if a table contains the provided element
---@nodiscard
---@param t table table to check
---@param element any element to check for
function util.table_contains(t, element)
    for i = 1, #t do
        if t[i] == element then return true end
    end

    return false
end

--#endregion

-- MEKANISM POWER --
--#region

-- convert Joules to FE
---@nodiscard
---@param J number Joules
---@return number FE Forge Energy
function util.joules_to_fe(J) return (J * 0.4) end

-- convert FE to Joules
---@nodiscard
---@param FE number Forge Energy
---@return number J Joules
function util.fe_to_joules(FE) return (FE * 2.5) end

local function kFE(fe) return fe / 1000.0 end
local function MFE(fe) return fe / 1000000.0 end
local function GFE(fe) return fe / 1000000000.0 end
local function TFE(fe) return fe / 1000000000000.0 end
local function PFE(fe) return fe / 1000000000000000.0 end
local function EFE(fe) return fe / 1000000000000000000.0 end    -- if you accomplish this please touch grass
local function ZFE(fe) return fe / 1000000000000000000000.0 end -- please stop

-- format a power value into XXX.XX UNIT format (FE, kFE, MFE, GFE, TFE, PFE, EFE, ZFE)
---@nodiscard
---@param fe number forge energy value
---@param combine_label? boolean if a label should be included in the string itself
---@param format? string format override
---@return string str, string? unit
function util.power_format(fe, combine_label, format)
    local unit
    local value

    if type(format) ~= "string" then format = "%.2f" end

    if fe < 1000.0 then
        unit = "FE"
        value = fe
    elseif fe < 1000000.0 then
        unit = "kFE"
        value = kFE(fe)
    elseif fe < 1000000000.0 then
        unit = "MFE"
        value = MFE(fe)
    elseif fe < 1000000000000.0 then
        unit = "GFE"
        value = GFE(fe)
    elseif fe < 1000000000000000.0 then
        unit = "TFE"
        value = TFE(fe)
    elseif fe < 1000000000000000000.0 then
        unit = "PFE"
        value = PFE(fe)
    elseif fe < 1000000000000000000000.0 then
        unit = "EFE"
        value = EFE(fe)
    else
        unit = "ZFE"
        value = ZFE(fe)
    end

    if combine_label then
        return util.sprintf(util.c(format, " %s"), value, unit)
    else
        return util.sprintf(format, value), unit
    end
end

--#endregion

-- UTILITY CLASSES --
--#region

-- WATCHDOG --

-- OS timer based watchdog<br>
-- triggers a timer event if not fed within 'timeout' seconds
---@nodiscard
---@param timeout number timeout duration
function util.new_watchdog(timeout)
    local self = {
        timeout = timeout,
        wd_timer = util.start_timer(timeout)
    }

    ---@class watchdog
    local public = {}

    -- check if a timer is this watchdog
    ---@nodiscard
    ---@param timer number timer event timer ID
    function public.is_timer(timer) return self.wd_timer == timer end

    -- satiate the beast
    function public.feed()
        if self.wd_timer ~= nil then
            util.cancel_timer(self.wd_timer)
        end
        self.wd_timer = util.start_timer(self.timeout)
    end

    -- cancel the watchdog
    function public.cancel()
        if self.wd_timer ~= nil then
            util.cancel_timer(self.wd_timer)
        end
    end

    return public
end

-- LOOP CLOCK --

-- OS timer based loop clock<br>
-- fires a timer event at the specified period, does not start at construct time
---@nodiscard
---@param period number clock period
function util.new_clock(period)
    local self = {
        period = period,
        timer = nil
    }

    ---@class clock
    local public = {}

    -- check if a timer is this clock
    ---@nodiscard
    ---@param timer number timer event timer ID
    function public.is_clock(timer) return self.timer == timer end

    -- start the clock
    function public.start() self.timer = util.start_timer(self.period) end

    return public
end

-- FIELD VALIDATOR --

-- create a new type validator<br>
-- can execute sequential checks and check valid() to see if it is still valid
---@nodiscard
function util.new_validator()
    local valid = true

    ---@class validator
    local public = {}

    function public.assert_type_bool(value) valid = valid and type(value) == "boolean" end
    function public.assert_type_num(value) valid = valid and type(value) == "number" end
    function public.assert_type_int(value) valid = valid and util.is_int(value) end
    function public.assert_type_str(value) valid = valid and type(value) == "string" end
    function public.assert_type_table(value) valid = valid and type(value) == "table" end

    function public.assert_eq(check, expect) valid = valid and check == expect end
    function public.assert_min(check, min) valid = valid and check >= min end
    function public.assert_min_ex(check, min) valid = valid and check > min end
    function public.assert_max(check, max) valid = valid and check <= max end
    function public.assert_max_ex(check, max) valid = valid and check < max end
    function public.assert_range(check, min, max) valid = valid and check >= min and check <= max end
    function public.assert_range_ex(check, min, max) valid = valid and check > min and check < max end

    function public.assert_channel(channel) valid = valid and type(channel) == "number" and channel >= 0 and channel <= 65535 end

    -- check if all assertions passed successfully
    ---@nodiscard
    function public.valid() return valid end

    return public
end

--#endregion

return util
