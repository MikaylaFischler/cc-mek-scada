--
-- Utility Functions
--

---@class util
local util = {}

-- PRINT --

-- print
---@param message any
util.print = function (message)
    term.write(tostring(message))
end

-- print line
---@param message any
util.println = function (message)
    print(tostring(message))
end

-- timestamped print
---@param message any
util.print_ts = function (message)
    term.write(os.date("[%H:%M:%S] ") .. tostring(message))
end

-- timestamped print line
---@param message any
util.println_ts = function (message)
    print(os.date("[%H:%M:%S] ") .. tostring(message))
end

-- STRING TOOLS --

-- get a value as a string
---@param val any
---@return string
util.strval = function (val)
    local t = type(val)
    if t == "table" or t == "function" then
        return "[" .. tostring(val) .. "]"
    else
        return tostring(val)
    end
end

-- concatenation with built-in to string
---@vararg any
---@return string
util.concat = function (...)
    local str = ""
    for _, v in ipairs(arg) do
        str = str .. util.strval(v)
    end
    return str
end

-- sprintf implementation
---@param format string
---@vararg any
util.sprintf = function (format, ...)
    return string.format(format, table.unpack(arg))
end

-- TIME --

-- current time
---@return integer milliseconds
util.time_ms = function ()
---@diagnostic disable-next-line: undefined-field
    return os.epoch('local')
end

-- current time
---@return number seconds
util.time_s = function ()
---@diagnostic disable-next-line: undefined-field
    return os.epoch('local') / 1000.0
end

-- current time
---@return integer milliseconds
util.time = function ()
    return util.time_ms()
end

-- PARALLELIZATION --

-- protected sleep call so we still are in charge of catching termination
---@param t integer seconds
--- EVENT_CONSUMER: this function consumes events
util.psleep = function (t)
---@diagnostic disable-next-line: undefined-field
    pcall(os.sleep, t)
end

-- no-op to provide a brief pause (1 tick) to yield
---
--- EVENT_CONSUMER: this function consumes events
util.nop = function ()
    util.psleep(0.05)
end

-- attempt to maintain a minimum loop timing (duration of execution)
---@param target_timing integer minimum amount of milliseconds to wait for
---@param last_update integer millisecond time of last update
---@return integer time_now
-- EVENT_CONSUMER: this function consumes events
util.adaptive_delay = function (target_timing, last_update)
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
util.filter_table = function (t, f, on_delete)
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
util.table_contains = function (t, element)
    for i = 1, #t do
        if t[i] == element then return true end
    end

    return false
end

-- MEKANISM POWER --

-- function kFE(fe) return fe / 1000 end
-- function MFE(fe) return fe / 1000000 end
-- function GFE(fe) return fe / 1000000000 end
-- function TFE(fe) return fe / 1000000000000 end

-- -- FLOATING POINT PRINTS --

-- local function fractional_1s(number)
--     return number == math.round(number)
-- end

-- local function fractional_10ths(number)
--     number = number * 10
--     return number == math.round(number)
-- end

-- local function fractional_100ths(number)
--     number = number * 100
--     return number == math.round(number)
-- end

-- function power_format(fe)
--     if fe < 1000 then
--         return string.format("%.2f FE", fe)
--     elseif fe < 1000000 then
--         return string.format("%.3f kFE", kFE(fe))
--     end
-- end

-- WATCHDOG --

-- ComputerCraft OS Timer based Watchdog
---@param timeout number timeout duration
---
--- triggers a timer event if not fed within 'timeout' seconds
util.new_watchdog = function (timeout)
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
    public.is_timer = function (timer)
        return self.wd_timer == timer
    end

    -- satiate the beast
    public.feed = function ()
        if self.wd_timer ~= nil then
            cancel_timer(self.wd_timer)
        end
        self.wd_timer = start_timer(self.timeout)
    end

    -- cancel the watchdog
    public.cancel = function ()
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
util.new_clock = function (period)
---@diagnostic disable-next-line: undefined-field
    local start_timer = os.startTimer

    local self = {
        period = period,
        timer = nil
    }

    ---@class clock
    local public = {}

    ---@param timer number timer event timer ID
    public.is_clock = function (timer)
        return self.timer == timer
    end

    -- start the clock
    public.start = function ()
        self.timer = start_timer(self.period)
    end

    return public
end

return util
