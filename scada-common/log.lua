--
-- File System Logger
--

local util = require("scada-common.util")

---@class logger
local log = {}

---@alias MODE integer
local MODE = { APPEND = 0, NEW = 1 }

log.MODE = MODE

local logger = {
    not_ready = true,
    path = "/log.txt",
    mode = MODE.APPEND,
    debug = false,
    file = nil,         ---@type table|nil
    dmesg_out = nil,
    dmesg_restore_coord = { 1, 1 },
    dmesg_scroll_count = 0
}

---@type function
local free_space = fs.getFreeSpace

-----------------------
-- PRIVATE FUNCTIONS --
-----------------------

-- private log write function
---@param msg string
local function _log(msg)
    if logger.not_ready then return end

    local out_of_space = false
    local time_stamp = os.date("[%c] ")
    local stamped = time_stamp .. util.strval(msg)

    -- attempt to write log
    local status, result = pcall(function ()
        logger.file.writeLine(stamped)
        logger.file.flush()
    end)

    -- if we don't have space, we need to create a new log file

    if (not status) and (result ~= nil) then
        out_of_space = string.find(result, "Out of space") ~= nil

        if out_of_space then
            -- will delete log file
        else
            util.println("unknown error writing to logfile: " .. result)
        end
    end

    if out_of_space or (free_space(logger.path) < 512) then
        -- delete the old log file before opening a new one
        logger.file.close()
        fs.delete(logger.path)

        -- re-init logger and pass dmesg_out so that it doesn't change
        log.init(logger.path, logger.mode, logger.debug, logger.dmesg_out)

        -- leave a message
        logger.file.writeLine(time_stamp .. "recycled log file")
        logger.file.writeLine(stamped)
        logger.file.flush()
    end
end

----------------------
-- PUBLIC FUNCTIONS --
----------------------

-- initialize logger
---@param path string file path
---@param write_mode MODE file write mode
---@param include_debug boolean whether or not to include debug logs
---@param dmesg_redirect? table terminal/window to direct dmesg to
function log.init(path, write_mode, include_debug, dmesg_redirect)
    logger.path = path
    logger.mode = write_mode
    logger.debug = include_debug

    if logger.mode == MODE.APPEND then
        logger.file = fs.open(path, "a")
    else
        logger.file = fs.open(path, "w")
    end

    if dmesg_redirect then
        logger.dmesg_out = dmesg_redirect
    else
        logger.dmesg_out = term.current()
    end

    logger.not_ready = false
end

-- close the log file handle
function log.close()
    logger.file.close()
end

-- direct dmesg output to a monitor/window
---@param window table window or terminal reference
function log.direct_dmesg(window) logger.dmesg_out = window end

-- dmesg style logging for boot because I like linux-y things
---@param msg string message
---@param tag? string log tag
---@param tag_color? integer log tag color
---@return dmesg_ts_coord coordinates line area to place working indicator
function log.dmesg(msg, tag, tag_color)
    ---@class dmesg_ts_coord
    local ts_coord = { x1 = 2, x2 = 3, y = 1 }

    msg = util.strval(msg)
    tag = tag or ""
    tag = util.strval(tag)

    local t_stamp = string.format("%12.2f", os.clock())
    local out = logger.dmesg_out

    if out ~= nil then
        local out_w, out_h = out.getSize()

        local lines = { msg }

        -- wrap if needed
        if string.len(msg) > out_w then
            local remaining = true
            local s_start = 1
            local s_end = out_w
            local i = 1

            lines = {}

            while remaining do
                local line = string.sub(msg, s_start, s_end)

                if line == "" then
                    remaining = false
                else
                    lines[i] = line

                    s_start = s_end + 1
                    s_end = s_end + out_w
                    i = i + 1
                end
            end
        end

        -- start output with tag and time, assuming we have enough width for this to be on one line
        local cur_x, cur_y = out.getCursorPos()

        if cur_x > 1 then
            if cur_y == out_h then
                out.scroll(1)
                out.setCursorPos(1, cur_y)
                logger.dmesg_scroll_count = logger.dmesg_scroll_count + 1
            else
                out.setCursorPos(1, cur_y + 1)
            end
        end

        -- colored time
        local initial_color = out.getTextColor()
        out.setTextColor(colors.white)
        out.write("[")
        out.setTextColor(colors.lightGray)
        out.write(t_stamp)
        ts_coord.x2, ts_coord.y = out.getCursorPos()
        ts_coord.x2 = ts_coord.x2 - 1
        out.setTextColor(colors.white)
        out.write("] ")

        -- print optionally colored tag
        if tag ~= "" then
            out.write("[")
            if tag_color then out.setTextColor(tag_color) end
            out.write(tag)
            out.setTextColor(colors.white)
            out.write("] ")
        end

        out.setTextColor(initial_color)

        -- output message
        for i = 1, #lines do
            cur_x, cur_y = out.getCursorPos()

            if i > 1 and cur_x > 1 then
                if cur_y == out_h then
                    out.scroll(1)
                    out.setCursorPos(1, cur_y)
                    logger.dmesg_scroll_count = logger.dmesg_scroll_count + 1
                else
                    out.setCursorPos(1, cur_y + 1)
                end
            end

            out.write(lines[i])
        end

        logger.dmesg_restore_coord = { out.getCursorPos() }

        _log(util.c("[", t_stamp, "] [", tag, "] ", msg))
    end

    return ts_coord
end

-- print a dmesg message, but then show remaining seconds instead of timestamp
---@nodiscard
---@param msg string message
---@param tag? string log tag
---@param tag_color? integer log tag color
---@return function update, function done
function log.dmesg_working(msg, tag, tag_color)
    local ts_coord = log.dmesg(msg, tag, tag_color)
    local initial_scroll = logger.dmesg_scroll_count

    local out = logger.dmesg_out
    local width = (ts_coord.x2 - ts_coord.x1) + 1

    if out ~= nil then
        local initial_color = out.getTextColor()

        local counter = 0

        local function update(sec_remaining)
            local new_y = ts_coord.y - (logger.dmesg_scroll_count - initial_scroll)
            if new_y < 1 then return end

            local time = util.sprintf("%ds", sec_remaining)
            local available = width - (string.len(time) + 2)
            local progress = ""

            out.setCursorPos(ts_coord.x1, new_y)
            out.write(" ")

            if counter % 4 == 0 then
                progress = "|"
            elseif counter % 4 == 1 then
                progress = "/"
            elseif counter % 4 == 2 then
                progress = "-"
            elseif counter % 4 == 3 then
                progress = "\\"
            end

            out.setTextColor(colors.blue)
            out.write(progress)
            out.setTextColor(colors.lightGray)
            out.write(util.spaces(available) .. time)
            out.setTextColor(initial_color)

            counter = counter + 1

            out.setCursorPos(table.unpack(logger.dmesg_restore_coord))
        end

        local function done(ok)
            local new_y = ts_coord.y - (logger.dmesg_scroll_count - initial_scroll)
            if new_y < 1 then return end

            out.setCursorPos(ts_coord.x1, new_y)

            if ok or ok == nil then
                out.setTextColor(colors.green)
                out.write(util.pad("DONE", width))
            else
                out.setTextColor(colors.red)
                out.write(util.pad("FAIL", width))
            end

            out.setTextColor(initial_color)

            out.setCursorPos(table.unpack(logger.dmesg_restore_coord))
        end

        return update, done
    else
        return function () end, function () end
    end
end

-- log debug messages
---@param msg string message
---@param trace? boolean include file trace
function log.debug(msg, trace)
    if logger.debug then
        local dbg_info = ""

        if trace then
            local info = debug.getinfo(2)
            local name = ""

            if info.name ~= nil then
                name = ":" .. info.name .. "():"
            end

            dbg_info = info.short_src .. ":" .. name .. info.currentline .. " > "
        end

        _log("[DBG] " .. dbg_info .. util.strval(msg))
    end
end

-- log info messages
---@param msg string message
function log.info(msg)
    _log("[INF] " .. util.strval(msg))
end

-- log warning messages
---@param msg string message
function log.warning(msg)
    _log("[WRN] " .. util.strval(msg))
end

-- log error messages
---@param msg string message
---@param trace? boolean include file trace
function log.error(msg, trace)
    local dbg_info = ""

    if trace then
        local info = debug.getinfo(2)
        local name = ""

        if info.name ~= nil then
            name = ":" .. info.name .. "():"
        end

        dbg_info = info.short_src .. ":" .. name ..  info.currentline .. " > "
    end

    _log("[ERR] " .. dbg_info .. util.strval(msg))
end

-- log fatal errors
---@param msg string message
function log.fatal(msg)
    _log("[FTL] " .. util.strval(msg))
end

return log
