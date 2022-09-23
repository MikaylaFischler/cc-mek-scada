--
-- Utility Functions
--

---@class util
local util = {}

-- OPERATORS --

-- trinary operator
---@param cond boolean condition
---@param a any return if true
---@param b any return if false
---@return any value
function util.trinary(cond, a, b)
    if cond then return a else return b end
end

-- PRINT --

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

-- STRING TOOLS --

-- get a value as a string
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
---@param n integer
---@return string
function util.spaces(n)
    return util.strrep(" ", n)
end

-- pad text to a minimum width
---@param str string text
---@param n integer minimum width
---@return string
function util.pad(str, n)
    local len = string.len(str)
    local lpad = math.floor((n - len) / 2)
    local rpad = (n - len) - lpad

    return util.spaces(lpad) .. str .. util.spaces(rpad)
end

-- wrap a string into a table of lines, supporting single dash splits
---@param str string
---@param limit integer line limit
---@return table lines
function util.strwrap(str, limit)
    local lines = {}
    local ln_start = 1

    local first_break = str:find("([%-%s]+)")

    if first_break ~= nil then
        lines[1] = string.sub(str, 1, first_break - 1)
    else
        lines[1] = str
    end

---@diagnostic disable-next-line: discard-returns
    str:gsub("(%s+)()(%S+)()",
        function(space, start, word, stop)
            -- support splitting SINGLE DASH words
            word:gsub("(%S+)(%-)()(%S+)()",
                function (pre, dash, d_start, post, d_stop)
                    if (stop + d_stop) - ln_start <= limit then
                        -- do nothing, it will entirely fit
                    elseif ((start + d_start) + 1) - ln_start <= limit then
                        -- we can fit including the dash
                        lines[#lines] = lines[#lines] .. space .. pre .. dash
                        -- drop the space and replace the word with the post
                        space = ""
                        word = post
                        -- force a wrap
                        stop = limit + 1 + ln_start
                        -- change start position for new line start
                        start = start + d_start - 1
                    end
                end)
            -- can we append this or do we have to start a new line?
            if stop - ln_start > limit then
                -- starting new line
                ln_start = start
                lines[#lines + 1] = word
            else lines[#lines] = lines[#lines] .. space .. word end
        end)

    return lines
end

-- concatenation with built-in to string
---@vararg any
---@return string
function util.concat(...)
    local str = ""
    for _, v in ipairs(arg) do
        str = str .. util.strval(v)
    end
    return str
end

-- alias
util.c = util.concat

-- sprintf implementation
---@param format string
---@vararg any
function util.sprintf(format, ...)
    return string.format(format, table.unpack(arg))
end

-- MATH --

-- is a value an integer
---@param x any value
---@return boolean is_integer if the number is an integer
function util.is_int(x)
    return type(x) == "number" and x == math.floor(x)
end

-- round a number to an integer
---@return integer rounded
function util.round(x)
    return math.floor(x + 0.5)
end

-- TIME --

-- current time
---@return integer milliseconds
function util.time_ms()
---@diagnostic disable-next-line: undefined-field
    return os.epoch('local')
end

-- current time
---@return number seconds
function util.time_s()
---@diagnostic disable-next-line: undefined-field
    return os.epoch('local') / 1000.0
end

-- current time
---@return integer milliseconds
function util.time()
    return util.time_ms()
end

-- OS --

-- OS pull event raw wrapper with types
---@param target_event? string event to wait for
---@return os_event event, any param1, any param2, any param3, any param4, any param5
function util.pull_event(target_event)
---@diagnostic disable-next-line: undefined-field
    return os.pullEventRaw(target_event)
end

-- PARALLELIZATION --

-- protected sleep call so we still are in charge of catching termination
---@param t integer seconds
--- EVENT_CONSUMER: this function consumes events
function util.psleep(t)
---@diagnostic disable-next-line: undefined-field
    pcall(os.sleep, t)
end

-- no-op to provide a brief pause (1 tick) to yield
---
--- EVENT_CONSUMER: this function consumes events
function util.nop()
    util.psleep(0.05)
end

-- attempt to maintain a minimum loop timing (duration of execution)
---@param target_timing integer minimum amount of milliseconds to wait for
---@param last_update integer millisecond time of last update
---@return integer time_now
--- EVENT_CONSUMER: this function consumes events
function util.adaptive_delay(target_timing, last_update)
    local sleep_for = target_timing - (util.time() - last_update)
    -- only if >50ms since worker loops already yield 0.05s
    if sleep_for >= 50 then
        util.psleep(sleep_for / 1000.0)
    end
    return util.time()
end

-- TABLE UTILITIES --

-- delete elements from a table if the passed function returns false when passed a table element
--
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
---@param t table table to check
---@param element any element to check for
function util.table_contains(t, element)
    for i = 1, #t do
        if t[i] == element then return true end
    end

    return false
end

-- MEKANISM POWER --

-- convert Joules to FE
---@param J number Joules
---@return number FE Forge Energy
function util.joules_to_fe(J) return mekanismEnergyHelper.joulesToFE(J) end

-- convert FE to Joules
---@param FE number Forge Energy
---@return number J Joules
function util.fe_to_joules(FE) return mekanismEnergyHelper.feToJoules(FE) end

local function kFE(fe) return fe / 1000.0 end
local function MFE(fe) return fe / 1000000.0 end
local function GFE(fe) return fe / 1000000000.0 end
local function TFE(fe) return fe / 1000000000000.0 end

-- format a power value into XXX.XX UNIT format (FE, kFE, MFE, GFE, TFE)
---@param fe number forge energy value
---@return string str formatted string
function util.power_format(fe)
    if fe < 1000 then
        return string.format("%.2f FE", fe)
    elseif fe < 1000000 then
        return string.format("%.2f kFE", kFE(fe))
    elseif fe < 1000000000 then
        return string.format("%.2f MFE", MFE(fe))
    elseif fe < 1000000000000 then
        return string.format("%.2f GFE", GFE(fe))
    else
        return string.format("%.2f TFE", TFE(fe))
    end
end

-- WATCHDOG --

-- ComputerCraft OS Timer based Watchdog
---@param timeout number timeout duration
---
--- triggers a timer event if not fed within 'timeout' seconds
function util.new_watchdog(timeout)
---@diagnostic disable-next-line: undefined-field
    local start_timer = os.startTimer
---@diagnostic disable-next-line: undefined-field
    local cancel_timer = os.cancelTimer

    local self = {
        timeout = timeout,
        wd_timer = start_timer(timeout)
    }

    ---@class watchdog
    local public = {}

    ---@param timer number timer event timer ID
    function public.is_timer(timer)
        return self.wd_timer == timer
    end

    -- satiate the beast
    function public.feed()
        if self.wd_timer ~= nil then
            cancel_timer(self.wd_timer)
        end
        self.wd_timer = start_timer(self.timeout)
    end

    -- cancel the watchdog
    function public.cancel()
        if self.wd_timer ~= nil then
            cancel_timer(self.wd_timer)
        end
    end

    return public
end

-- LOOP CLOCK --

-- ComputerCraft OS Timer based Loop Clock
---@param period number clock period
---
--- fires a timer event at the specified period, does not start at construct time
function util.new_clock(period)
---@diagnostic disable-next-line: undefined-field
    local start_timer = os.startTimer

    local self = {
        period = period,
        timer = nil
    }

    ---@class clock
    local public = {}

    ---@param timer number timer event timer ID
    function public.is_clock(timer)
        return self.timer == timer
    end

    -- start the clock
    function public.start()
        self.timer = start_timer(self.period)
    end

    return public
end

-- create a new type validator
--
-- can execute sequential checks and check valid() to see if it is still valid
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

    function public.assert_port(port) valid = valid and type(port) == "number" and port >= 0 and port <= 65535 end

    function public.valid() return valid end

    return public
end

return util
