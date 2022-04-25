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

-- block waiting for parallel call
function task_wait(f)
    parallel.waitForAll(f)
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

    return {
        get_timer = get_timer,
        feed = feed
    }
end
