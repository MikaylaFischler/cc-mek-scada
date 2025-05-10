--
-- Utility Functions
--

local cc_strings = require("cc.strings")

local const      = require("scada-common.constants")

local math = math
local string = string
local table = table
local os = os

local getmetatable = getmetatable
local print = print
local tostring = tostring
local type = type

local t_concat = table.concat
local t_insert = table.insert
local t_pack   = table.pack

---@class util
local util = {}

-- scada-common version
util.version = "1.5.2"

util.TICK_TIME_S = 0.05
util.TICK_TIME_MS = 50

--#region OPERATORS

-- trinary operator
---@nodiscard
---@param cond any condition
---@param a any return if evaluated as true
---@param b any return if false or nil
---@return any value
function util.trinary(cond, a, b)
    if cond then return a else return b end
end

--#endregion

--#region PRINT

local p_time = "[%H:%M:%S] "

-- print
---@param message any
function util.print(message) term.write(tostring(message)) end

-- print line
---@param message any
function util.println(message) print(tostring(message)) end

-- timestamped print
---@param message any
function util.print_ts(message) term.write(os.date(p_time) .. tostring(message)) end

-- timestamped print line
---@param message any
function util.println_ts(message) print(os.date(p_time) .. tostring(message)) end

--#endregion

--#region STRING TOOLS

-- get a value as a string
---@nodiscard
---@param val any
---@return string
function util.strval(val)
    local t = type(val)
    if t == "string" then return val end
    -- this depends on Lua short-circuiting the or check for metatables (note: metatables won't have metatables)
    if (t == "table" and (getmetatable(val) == nil or getmetatable(val).__tostring == nil)) or t == "function" then
        return t_concat{"[", tostring(val), "]"}
    else return tostring(val) end
end

-- tokenize a string by a separator<br>
-- does not behave exactly like C's strtok
---@param str string string to tokenize
---@param sep string separator to tokenize by
---@return string[] token_list
function util.strtok(str, sep)
    local list = {}
    for part in string.gmatch(str, "([^" .. sep .. "]+)") do t_insert(list, part) end
    return list
end

-- repeat a space n times
---@nodiscard
---@param n integer
---@return string
function util.spaces(n) return string.rep(" ", n) end

-- pad text to a minimum width
---@nodiscard
---@param str string text
---@param n integer minimum width
---@return string
function util.pad(str, n)
    local len = string.len(str)
    local lpad = math.floor((n - len) / 2)
    local rpad = (n - len) - lpad

    return t_concat{util.spaces(lpad), str, util.spaces(rpad)}
end

-- trim leading and trailing whitespace
---@nodiscard
---@param s string text
---@return string
function util.trim(s)
    local str = s:gsub("^%s*(.-)%s*$", "%1")
    return str
end

-- wrap a string into a table of lines
---@nodiscard
---@param str string
---@param limit integer line limit, must be greater than 0
---@return string[] lines
function util.strwrap(str, limit)
    assert(limit > 0, "util.strwrap() limit not greater than 0")
    return cc_strings.wrap(str, limit)
end

-- make sure a string is at least 'width' long
---@nodiscard
---@param str string
---@param width integer minimum width
---@return string string
function util.strminw(str, width) return cc_strings.ensure_width(str, width) end

-- concatenation with built-in to string
---@nodiscard
---@param ... any
---@return string
function util.concat(...)
    local args, strings = t_pack(...), {}
    for i = 1, args.n do strings[i] = util.strval(args[i]) end
    return t_concat(strings)
end

-- alias
util.c = util.concat

-- sprintf implementation
---@nodiscard
---@param format string
---@param ... any
function util.sprintf(format, ...) return string.format(format, ...) end

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
        formatted, i = formatted:gsub("^(%s-%d+)(%d%d%d)", "%1,%2")
        if i > 0 then commas = commas + 1 end
    end

    local _, num_spaces = formatted:gsub(" %s-", "")
    local remove = math.min(num_spaces, commas)

    formatted = string.sub(formatted, remove + 1)

    return formatted
end

--#endregion

--#region MATH

-- is a value an integer
---@nodiscard
---@param x any value
---@return boolean is_integer
function util.is_int(x) return type(x) == "number" and x == math.floor(x) end

-- get the sign of a number
---@nodiscard
---@param x number value
---@return integer sign (-1 for < 0, 1 otherwise)
function util.sign(x) return util.trinary(x < 0, -1, 1) end

-- round a number to an integer
---@nodiscard
---@return integer rounded
function util.round(x) return math.floor(x + 0.5) end

-- get a new moving average object
---@nodiscard
---@param length integer history length
function util.mov_avg(length)
    local data = {}
    local index = 1
    local last_t = 0 ---@type number|nil

    ---@class moving_average
    local public = {}

    -- reset all to a given value, or clear all data if no value is given
    ---@param x number? value
    function public.reset(x)
        index = 1
        data = {}

        if x then
            for _ = 1, length do t_insert(data, x) end
        end
    end

    -- record a new value
    ---@param x number new value
    ---@param t number? optional last update time to prevent duplicated entries
    function public.record(x, t)
        if type(t) == "number" and last_t == t then return end

        data[index] = x
        last_t = t

        index = index + 1
        if index > length then index = 1 end
    end

    -- compute the moving average
    ---@nodiscard
    ---@return number average
    function public.compute()
        if #data == 0 then return 0 end

        local sum = 0
        for i = 1, #data do
            sum = sum + data[i]
        end

        return sum / #data
    end

    return public
end

--#endregion

--#region TIME

-- current time
---@nodiscard
---@return integer milliseconds
---@diagnostic disable-next-line: undefined-field
function util.time_ms() return os.epoch("local") end

-- current time
---@nodiscard
---@return number seconds
---@diagnostic disable-next-line: undefined-field
function util.time_s() return os.epoch("local") / 1000.0 end

-- current time
---@nodiscard
---@return integer milliseconds
function util.time() return util.time_ms() end

--#endregion

--#region OS

-- OS pull event raw wrapper with types
---@nodiscard
---@param target_event? string event to wait for
---@return os_event event, any param1, any param2, any param3, any param4, any param5
---@diagnostic disable-next-line: undefined-field
function util.pull_event(target_event) return os.pullEventRaw(target_event) end

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
---@diagnostic disable-next-line: undefined-field
function util.start_timer(t) return os.startTimer(t) end

-- cancel an OS timer
---@param timer integer timer ID
---@diagnostic disable-next-line: undefined-field
function util.cancel_timer(timer) os.cancelTimer(timer) end

--#endregion

--#region PARALLELIZATION

-- protected sleep call so we still are in charge of catching termination<br>
-- returns the result of pcall
---@param t number seconds
---@return boolean success, any result, any ...
--- EVENT_CONSUMER: this function consumes events
---@diagnostic disable-next-line: undefined-field
function util.psleep(t) return pcall(os.sleep, t) end

-- no-op to provide a brief pause (1 tick) to yield<br>
--- EVENT_CONSUMER: this function consumes events
function util.nop() util.psleep(0.05) end

-- attempt to maintain a minimum loop timing (duration of execution)<br>
-- note: will not yield for time periods less than 50ms
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

--#region TABLE UTILITIES

-- delete elements from a table if the passed function returns false when passed a table element<br>
-- put briefly: deletes elements that return false, keeps elements that return true
---@generic Type
---@param t Type[] table to remove elements from
---@param f fun(t_elem: Type) : boolean should return false to delete an element when passed the element
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
---@generic Type
---@nodiscard
---@param t Type[] table to check
---@param element Type element to check for
function util.table_contains(t, element)
    for i = 1, #t do
        if t[i] == element then return true end
    end

    return false
end

-- count the length of a table, even if the values are not sequential or contain named keys
---@nodiscard
---@param t table
---@return integer length
function util.table_len(t)
    local n = 0
    for _, _ in pairs(t) do n = n + 1 end
    return n
end

--#endregion

--#region MEKANISM MATH

-- convert Joules to FE (or RF)
---@nodiscard
---@param J number Joules
---@return number FE Forge Energy or Redstone Flux
function util.joules_to_fe_rf(J) return (J * 0.4) end

-- convert FE (or RF) to Joules
---@nodiscard
---@param FE number Forge Energy or Redstone Flux
---@return number J Joules
function util.fe_rf_to_joules(FE) return (FE * 2.5) end

-- format a power value into XXX.XX UNIT format<br>
-- example for FE: FE, kFE, MFE, GFE, TFE, PFE, EFE, ZFE
---@nodiscard
---@param e number energy value
---@param label string energy scale label
---@param combine_label? boolean if a label should be included in the string itself
---@param format? string format override
---@return string str, string unit
function util.power_format(e, label, combine_label, format)
    local unit, value

    if type(format) ~= "string" then format = "%.2f" end

    if e < 1000.0 then
        unit = ""
        value = e
    elseif e < 1000000.0 then
        unit = "k"
        value = e / 1000.0
    elseif e < 1000000000.0 then
        unit = "M"
        value = e / 1000000.0
    elseif e < 1000000000000.0 then
        unit = "G"
        value = e / 1000000000.0
    elseif e < 1000000000000000.0 then
        unit = "T"
        value = e / 1000000000000.0
    elseif e < 1000000000000000000.0 then
        unit = "P"
        value = e / 1000000000000000.0
    elseif e < 1000000000000000000000.0 then
        -- if you accomplish this please touch grass
        unit = "E"
        value = e / 1000000000000000000.0
    else
        -- how & why did you do this?
        unit = "Z"
        value = e / 1000000000000000000000.0
    end

    unit = unit .. label

    if combine_label then
        return util.sprintf(util.c(format, " %s"), value, unit), unit
    else
        return util.sprintf(format, value), unit
    end
end

-- compute Mekanism's rotation rate for a turbine
---@nodiscard
---@param turbine turbinev_session_db turbine data
function util.turbine_rotation(turbine)
    local build = turbine.build

    local inner_vol = build.steam_cap / const.mek.TURBINE_GAS_PER_TANK
    local disp_rate = (build.dispersers * const.mek.TURBINE_DISPERSER_FLOW) * inner_vol
    local vent_rate = build.vents * const.mek.TURBINE_VENT_FLOW

    local max_rate = math.min(disp_rate, vent_rate)
    local flow = math.min(max_rate, turbine.tanks.steam.amount)

    return (flow * (turbine.tanks.steam.amount / build.steam_cap)) / max_rate
end

--#endregion

--#region UTILITY CLASSES

-- WATCHDOG --

-- OS timer based watchdog<br>
-- triggers a timer event if not fed within 'timeout' seconds
---@nodiscard
---@param timeout number timeout duration
function util.new_watchdog(timeout)
    local self = { timeout = timeout, wd_timer = util.start_timer(timeout) }

    ---@class watchdog
    local public = {}

    -- check if a timer is this watchdog
    ---@nodiscard
    ---@param timer number event timer ID
    function public.is_timer(timer) return self.wd_timer == timer end

    -- satiate the beast
    function public.feed()
        public.cancel()
        self.wd_timer = util.start_timer(self.timeout)
    end

    -- cancel the watchdog
    function public.cancel()
        if self.wd_timer ~= nil then util.cancel_timer(self.wd_timer) end
    end

    return public
end

-- LOOP CLOCK --

-- OS timer based loop clock<br>
-- fires a timer event at the specified period, does not start at construct time
---@nodiscard
---@param period number clock period
function util.new_clock(period)
    local self = { period = period, timer = nil }

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

    function public.assert(check) valid = valid and (check == true) end
    function public.assert_eq(check, expect) valid = valid and check == expect end
    function public.assert_min(check, min) valid = valid and check >= min end
    function public.assert_min_ex(check, min) valid = valid and check > min end
    function public.assert_max(check, max) valid = valid and check <= max end
    function public.assert_max_ex(check, max) valid = valid and check < max end
    function public.assert_range(check, min, max) valid = valid and check >= min and check <= max end
    function public.assert_range_ex(check, min, max) valid = valid and check > min and check < max end

    function public.assert_channel(channel) valid = valid and util.is_int(channel) and channel >= 0 and channel <= 65535 end

    -- check if all assertions passed successfully
    ---@nodiscard
    function public.valid() return valid end

    return public
end

--#endregion

return util
