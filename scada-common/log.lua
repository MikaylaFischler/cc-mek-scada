--
-- File System Logger
--

-- we use extra short abbreviations since computer craft screens are very small
-- underscores are used since some of these names are used elsewhere (e.g. 'debug' is a lua table)

local LOG_DEBUG = true

local file_handle = fs.open("/log.txt", "a")

local _log = function (msg)
    local stamped = os.date("[%c] ") .. msg
    file_handle.writeLine(stamped)
    file_handle.flush()
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

        _log("[DBG] " .. dbg_info .. msg .. "\n")
    end
end

function _info(msg)
    _log("[INF] " .. msg .. "\n")
end

function _warning(msg)
    _log("[WRN] " .. msg .. "\n")
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

    _log("[ERR] " .. dbg_info .. msg .. "\n")
end

function _fatal(msg)
    _log("[FTL] " .. msg .. "\n")
end
