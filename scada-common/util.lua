-- timestamped print
function print_ts(message)
    term.write(os.date("[%H:%M:%S] ") .. message)
end

-- ComputerCraft OS Timer based Watchdog
-- triggers a timer event if not fed within 'timeout' seconds
function new_watchdog(timeout)
    local self = { 
        _timeout = timeout, 
        _wd_timer = os.startTimer(_timeout)
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
