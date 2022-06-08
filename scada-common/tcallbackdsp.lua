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
    log.debug(util.c("TCD: dispatching ", f, " for call in ", time, " seconds"))
---@diagnostic disable-next-line: undefined-field
    registry[os.startTimer(time)] = { callback = f }
end

-- lookup a timer event and execute the callback if found
---@param event integer timer event timer ID
function tcallbackdsp.handle(event)
    if registry[event] ~= nil then
        log.debug(util.c("TCD: executing callback ", registry[event].callback, " for timer ", event))
        registry[event].callback()
        registry[event] = nil
    end
end

return tcallbackdsp
