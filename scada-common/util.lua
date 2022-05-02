-- PRINT --

-- we are overwriting 'print' so save it first
local _print = print

-- print
function print(message)
    term.write(message)
end

-- print line
function println(message)
    _print(message)
end

-- timestamped print
function print_ts(message)
    term.write(os.date("[%H:%M:%S] ") .. message)
end

-- timestamped print line
function println_ts(message)
    _print(os.date("[%H:%M:%S] ") .. message)
end

-- TIME --

function time_ms()
    return os.epoch('local')
end

function time_s()
    return os.epoch('local') / 1000
end

function time()
    return time_ms()
end

-- PARALLELIZATION --

-- protected sleep call so we still are in charge of catching termination
function psleep(t)
    pcall(os.sleep, t)
end

-- no-op to provide a brief pause (and a yield)
-- EVENT_CONSUMER: this function consumes events
function nop()
    psleep(0.05)
end

-- attempt to maintain a minimum loop timing (duration of execution)
function adaptive_delay(target_timing, last_update)
    local sleep_for = target_timing - (time() - last_update)
    -- only if >50ms since worker loops already yield 0.05s
    if sleep_for >= 50 then
        psleep(sleep_for / 1000.0)
    end
    return time()
end

-- WATCHDOG --

-- ComputerCraft OS Timer based Watchdog
-- triggers a timer event if not fed within 'timeout' seconds
function new_watchdog(timeout)
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
