local util = {}

-- PRINT --

-- print
util.print = function (message)
    term.write(message)
end

-- print line
util.println = function (message)
    print(message)
end

-- timestamped print
util.print_ts = function (message)
    term.write(os.date("[%H:%M:%S] ") .. message)
end

-- timestamped print line
util.println_ts = function (message)
    print(os.date("[%H:%M:%S] ") .. message)
end

-- TIME --

util.time_ms = function ()
    return os.epoch('local')
end

util.time_s = function ()
    return os.epoch('local') / 1000
end

util.time = function ()
    return util.time_ms()
end

-- PARALLELIZATION --

-- protected sleep call so we still are in charge of catching termination
-- EVENT_CONSUMER: this function consumes events
util.psleep = function (t)
    pcall(os.sleep, t)
end

-- no-op to provide a brief pause (and a yield)
-- EVENT_CONSUMER: this function consumes events
util.nop = function ()
    util.psleep(0.05)
end

-- attempt to maintain a minimum loop timing (duration of execution)
-- EVENT_CONSUMER: this function consumes events
util.adaptive_delay = function (target_timing, last_update)
    local sleep_for = target_timing - (util.time() - last_update)
    -- only if >50ms since worker loops already yield 0.05s
    if sleep_for >= 50 then
        util.psleep(sleep_for / 1000.0)
    end
    return util.time()
end

-- WATCHDOG --

-- ComputerCraft OS Timer based Watchdog
-- triggers a timer event if not fed within 'timeout' seconds
util.new_watchdog = function (timeout)
    local self = {
        _timeout = timeout,
        _wd_timer = os.startTimer(timeout)
    }

    local get_timer = function ()
        return self._wd_timer
    end

    local feed = function ()
        if self._wd_timer ~= nil then
            os.cancelTimer(self._wd_timer)
        end
        self._wd_timer = os.startTimer(self._timeout)
    end

    local cancel = function ()
        if self._wd_timer ~= nil then
            os.cancelTimer(self._wd_timer)
        end
    end

    return {
        get_timer = get_timer,
        feed = feed,
        cancel = cancel
    }
end

return util
