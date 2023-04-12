---@todo remove this once API is started
---@diagnostic disable: unused-local

local apisessions = {}

---@param packet capi_frame
function apisessions.handle_packet(packet)
end

-- attempt to identify which session's watchdog timer fired
---@param timer_event number
function apisessions.check_all_watchdogs(timer_event)
end

-- delete all closed sessions
function apisessions.free_all_closed()
end

-- close all open connections
function apisessions.close_all()
end

return apisessions
