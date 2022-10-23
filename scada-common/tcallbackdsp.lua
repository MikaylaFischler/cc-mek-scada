--
-- Timer Callback Dispatcher
--

local log  = require("scada-common.log")
local util = require("scada-common.util")

local tcallbackdsp = {}

local registry = {}

local UNSERVICED_CALL_DELAY = util.TICK_TIME_S

-- request a function to be called after the specified time
---@param time number seconds
---@param f function callback function
function tcallbackdsp.dispatch(time, f)
    local timer = util.start_timer(time)
    registry[timer] = {
        callback = f,
        duration = time,
        expiry = time + util.time_s()
    }

    -- log.debug(util.c("TCD: queued callback for ", f, " [timer: ", timer, "]"))
end

-- request a function to be called after the specified time, aborting any registered instances of that function reference
---@param time number seconds
---@param f function callback function
function tcallbackdsp.dispatch_unique(time, f)
    -- ignore if already registered
    for timer, entry in pairs(registry) do
        if entry.callback == f then
            -- found an instance of this function reference, abort it
            log.debug(util.c("TCD: aborting duplicate timer callback [timer: ", timer, ", ", f, "]"))

            -- cancel event and remove from registry (even if it fires it won't call)
            util.cancel_timer(timer)
            registry[timer] = nil
        end
    end

    local timer = util.start_timer(time)
    registry[timer] = {
        callback = f,
        duration = time,
        expiry = time + util.time_s()
    }

    -- log.debug(util.c("TCD: queued callback for ", f, " [timer: ", timer, "]"))
end

-- lookup a timer event and execute the callback if found
---@param event integer timer event timer ID
function tcallbackdsp.handle(event)
    if registry[event] ~= nil then
        local callback = registry[event].callback
        -- clear first so that dispatch_unique call from inside callback won't throw a debug message
        registry[event] = nil
        callback()
    end
end

-- execute any callbacks that are overdo their time and have not been serviced
--
-- this can be called periodically to prevent loss of any callbacks do to timer events that are lost (see github issue #110)
function tcallbackdsp.call_unserviced()
    local found_unserviced = true

    while found_unserviced do
        found_unserviced = false

        -- go through registry, restart if unserviced entries were found due to mutating registry table
        for timer, entry in pairs(registry) do
            found_unserviced = util.time_s() > (entry.expiry + UNSERVICED_CALL_DELAY)
            if found_unserviced then
                local overtime = util.time_s() - entry.expiry
                local callback = entry.callback

                log.warning(util.c("TCD: executing unserviced callback ", entry.callback, " (", overtime, "s late) [timer: ", timer, "]"))

                -- clear first so that dispatch_unique call from inside callback won't see it as a conflict
                registry[timer] = nil
                callback()
                break
            end
        end
    end
end

-- identify any overdo callbacks
--
-- prints to log debug output
function tcallbackdsp.diagnostics()
    for timer, entry in pairs(registry) do
        if entry.expiry < util.time_s() then
            local overtime = util.time_s() - entry.expiry
            log.debug(util.c("TCD: unserviced timer ", timer, " for callback ", entry.callback, " is at least ", overtime, "s late"))
        else
            local time = entry.expiry - util.time_s()
            log.debug(util.c("TCD: pending timer ", timer, " for callback ", entry.callback, " (call after ", entry.duration, "s, expires ", time, ")"))
        end
    end
end

return tcallbackdsp
