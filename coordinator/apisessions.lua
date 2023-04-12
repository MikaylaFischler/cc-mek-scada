local apisessions = {}

---@param packet capi_frame
---@diagnostic disable-next-line: unused-local
function apisessions.handle_packet(packet)
end

-- attempt to identify which session's watchdog timer fired
---@param timer_event number
---@diagnostic disable-next-line: unused-local
function apisessions.check_all_watchdogs(timer_event)
end

-- delete all closed sessions
function apisessions.free_all_closed()
end

-- close all open connections
function apisessions.close_all()
end

return apisessions
