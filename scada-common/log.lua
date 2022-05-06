local util = require("scada-common.util")

--
-- File System Logger
--

local log = {}

local MODE = {
    APPEND = 0,
    NEW = 1
}

log.MODE = MODE

----------------------------
-- PRIVATE DATA/FUNCTIONS --
----------------------------

local LOG_DEBUG = true

local _log_sys = {
    path = "/log.txt",
    mode = MODE.APPEND,
    file = nil
}

local _log = function (msg)
    local time_stamp = os.date("[%c] ")
    local stamped = time_stamp .. msg

    -- attempt to write log
    local status, result = pcall(function () 
        _log_sys.file.writeLine(stamped)
        _log_sys.file.flush()
    end)

    -- if we don't have space, we need to create a new log file

    if not status then
        if result == "Out of space" then
            -- will delete log file
        elseif result ~= nil then
            util.println("unknown error writing to logfile: " .. result)
        end
    end

    if (result == "Out of space") or (fs.getFreeSpace(_log_sys.path) < 100) then
        -- delete the old log file and open a new one
        _log_sys.file.close()
        fs.delete(_log_sys.path)
        init(_log_sys.path, _log_sys.mode)

        -- leave a message
        _log_sys.file.writeLine(time_stamp .. "recycled log file")
        _log_sys.file.writeLine(stamped)
        _log_sys.file.flush()
    end
end

----------------------
-- PUBLIC FUNCTIONS --
----------------------

log.init = function (path, write_mode)
    _log_sys.path = path
    _log_sys.mode = write_mode

    if _log_sys.mode == MODE.APPEND then
        _log_sys.file = fs.open(path, "a")
    else
        _log_sys.file = fs.open(path, "w+")
    end
end

log.debug = function (msg, trace)
    if LOG_DEBUG then
        local dbg_info = ""

        if trace then
            local info = debug.getinfo(2)
            local name = ""

            if info.name ~= nil then
                name = ":" .. info.name .. "():"
            end

            dbg_info = info.short_src .. ":" .. name .. info.currentline .. " > "
        end

        _log("[DBG] " .. dbg_info .. msg)
    end
end

log.info = function (msg)
    _log("[INF] " .. msg)
end

log.warning = function (msg)
    _log("[WRN] " .. msg)
end

log.error = function (msg, trace)
    local dbg_info = ""
    
    if trace then
        local info = debug.getinfo(2)
        local name = ""

        if info.name ~= nil then
            name = ":" .. info.name .. "():"
        end
        
        dbg_info = info.short_src .. ":" .. name ..  info.currentline .. " > "
    end

    _log("[ERR] " .. dbg_info .. msg)
end

log.fatal = function (msg)
    _log("[FTL] " .. msg)
end

return log
