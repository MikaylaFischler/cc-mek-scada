--
-- Timer Callback Dispatcher
--

local log  = require("scada-common.log")
local util = require("scada-common.util")

local tcallbackdsp = {}

local registry = {}

-- request a function to be called after the specified time
---@param time number seconds
---@param f function callback function
function tcallbackdsp.dispatch(time, f)
---@diagnostic disable-next-line: undefined-field
    registry[os.startTimer(time)] = { callback = f }
end

-- request a function to be called after the specified time, aborting any registered instances of that function reference
---@param time number seconds
---@param f function callback function
function tcallbackdsp.dispatch_unique(time, f)
    -- ignore if already registered
    for timer, entry in pairs(registry) do
        if entry.callback == f then
            -- found an instance of this function reference, abort it
            log.debug(util.c("TCD: aborting duplicate timer callback (timer: ", timer, ", function: ", f, ")"))

            -- cancel event and remove from registry (even if it fires it won't call)
---@diagnostic disable-next-line: undefined-field
            os.cancelTimer(timer)
            registry[timer] = nil
        end
    end

---@diagnostic disable-next-line: undefined-field
    registry[os.startTimer(time)] = { callback = f }
end

-- lookup a timer event and execute the callback if found
---@param event integer timer event timer ID
function tcallbackdsp.handle(event)
    if registry[event] ~= nil then
        registry[event].callback()
        registry[event] = nil
    end
end

return tcallbackdsp
