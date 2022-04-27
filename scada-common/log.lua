--
-- File System Logger
--

-- we use extra short abbreviations since computer craft screens are very small
-- underscores are used since some of these names are used elsewhere (e.g. 'debug' is a lua table)

local LOG_DEBUG = true
local LOG_PATH = "/log.txt"

local file_handle = fs.open(LOG_PATH, "a")

local _log = function (msg)
    local stamped = os.date("[%c] ") .. msg

    -- attempt to write log
    local status, result = pcall(function () 
        file_handle.writeLine(stamped)
        file_handle.flush()
    end)

    -- if we don't have much space, we need to create a new log file
    local delete_log = fs.getFreeSpace(LOG_PATH) < 100

    if not status then
        if result == "Out of space" then
            delete_log = true
        elseif result ~= nil then
            print("unknown error writing to logfile: " .. result)
        end
    end

    if delete_log then
        -- delete the old log file and open a new one
        file_handle.close()
        fs.delete(LOG_PATH)
        file_handle = fs.open(LOG_PATH, "a")

        -- leave a message
        local notif = os.date("[%c] ") .. "recycled log file"
        file_handle.writeLine(notif)
        file_handle.writeLine(stamped)
        file_handle.flush()
    end
end

function _debug(msg, trace)
    if LOG_DEBUG then
        local dbg_info = ""

        if trace then
            local name = ""

            if debug.getinfo(2).name ~= nil then
                name = ":" .. debug.getinfo(2).name .. "():"
            end

            dbg_info = debug.getinfo(2).short_src .. ":" .. name ..
                debug.getinfo(2).currentline .. " > "
        end

        _log("[DBG] " .. dbg_info .. msg)
    end
end

function _info(msg)
    _log("[INF] " .. msg)
end

function _warning(msg)
    _log("[WRN] " .. msg)
end

function _error(msg, trace)
    local dbg_info = ""
    
    if trace then
        local name = ""

        if debug.getinfo(2).name ~= nil then
            name = ":" .. debug.getinfo(2).name .. "():"
        end
        
        dbg_info = debug.getinfo(2).short_src .. ":" .. name .. 
            debug.getinfo(2).currentline .. " > "
    end

    _log("[ERR] " .. dbg_info .. msg)
end

function _fatal(msg)
    _log("[FTL] " .. msg)
end
