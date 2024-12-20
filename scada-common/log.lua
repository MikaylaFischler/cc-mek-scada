--
-- File System Logger
--

local util = require("scada-common.util")

-- constant strings for speed
local DBG_TAG, INF_TAG, WRN_TAG, ERR_TAG, FTL_TAG = "[DBG] ", "[INF] ", "[WRN] ", "[ERR] ", "[FTL] "
local COLON, FUNC, ARROW = ":", "():", " > "

local MIN_SPACE    = 512
local OUT_OF_SPACE = "Out of space"
local TIME_FMT     = "%F %T "

---@class logger
local log = {}

---@enum LOG_MODE
local MODE = { APPEND = 0, NEW = 1 }

log.MODE = MODE

local logger = {
    not_ready = true,
    path = "/log.txt",
    mode = MODE.APPEND,
    debug = false,
    file = nil,         ---@type table|nil
    dmesg_out = nil,    ---@type Redirect|nil
    dmesg_restore_coord = { 1, 1 },
    dmesg_scroll_count = 0
}

---@type function
local free_space = fs.getFreeSpace

-----------------------
-- PRIVATE FUNCTIONS --
-----------------------

-- check if the provided error indicates out of space or if insufficient space available
---@param err_msg string|nil error message
---@return boolean out_of_space
local function check_out_of_space(err_msg)
    return (free_space(logger.path) < MIN_SPACE) or ((err_msg ~= nil) and (string.find(err_msg, OUT_OF_SPACE) ~= nil))
end

-- private log write function
---@param msg_bits any[]
local function _log(msg_bits)
    if logger.not_ready then return end

    local time_stamp = os.date(TIME_FMT)
    local stamped    = util.c(time_stamp, table.unpack(msg_bits))

    -- attempt to write log
    local status, result = pcall(function ()
        logger.file.writeLine(stamped)
        logger.file.flush()
    end)

    -- if we don't have space, we need to create a new log file
    if check_out_of_space() then
        assert(false)
        -- delete the old log file before opening a new one
        logger.file.close()
        fs.delete(logger.path)

        -- re-init logger and pass dmesg_out so that it doesn't change
        log.init(logger.path, logger.mode, logger.debug, logger.dmesg_out)

        -- log the message and recycle warning
        logger.file.writeLine(time_stamp .. WRN_TAG .. "recycled log file")
        logger.file.writeLine(stamped)
        logger.file.flush()
        assert(false)
    elseif (not status) and (result ~= nil) then
        util.println("unexpected error writing to the log file: " .. result)
    end
end

----------------------
-- PUBLIC FUNCTIONS --
----------------------

-- initialize logger
---@param path string file path
---@param write_mode LOG_MODE file write mode
---@param include_debug boolean whether or not to include debug logs
---@param dmesg_redirect? Redirect terminal/window to direct dmesg to
function log.init(path, write_mode, include_debug, dmesg_redirect)
    local err_msg = nil

    logger.path = path
    logger.mode = write_mode
    logger.debug = include_debug
    logger.file, err_msg = fs.open(path, util.trinary(logger.mode == MODE.APPEND, "a", "w"))

    if dmesg_redirect then
        logger.dmesg_out = dmesg_redirect
    else
        logger.dmesg_out = term.current()
    end

    -- check for space issues
    local out_of_space = check_out_of_space(err_msg)

    -- try to handle problems
    if logger.file == nil or out_of_space then
        if out_of_space then
            if fs.exists(logger.path) then
                fs.delete(logger.path)

                logger.file, err_msg = fs.open(path, util.trinary(logger.mode == MODE.APPEND, "a", "w"))

                if logger.file then
                    logger.file.writeLine(os.date(TIME_FMT) .. WRN_TAG .. "init recycled log file")
                    logger.file.flush()
                else error("failed to setup the log file: " .. err_msg) end
            else error("failed to make space for the log file, please delete unused files") end
        else error("unexpected error setting up the log file: " .. err_msg) end
    end

    logger.not_ready = false
end

-- close the log file handle
function log.close() logger.file.close() end

-- direct dmesg output to a monitor/window
---@param window Window window or terminal reference
function log.direct_dmesg(window) logger.dmesg_out = window end

-- dmesg style logging for boot because I like linux-y things
---@param msg any message
---@param tag? string log tag
---@param tag_color? integer log tag color
---@return dmesg_ts_coord coordinates line area to place working indicator
function log.dmesg(msg, tag, tag_color)
    ---@class dmesg_ts_coord
    local ts_coord = { x1 = 2, x2 = 3, y = 1 }

    msg = util.strval(msg)
    tag = util.strval(tag or "")

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

        _log{"[", t_stamp, "] [", tag, "] ", msg}
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
---@param msg any message
---@param trace? boolean include file trace
function log.debug(msg, trace)
    if logger.debug then
        if trace then
            local info = debug.getinfo(2)

            if info.name ~= nil then
                _log{DBG_TAG, info.short_src, COLON, info.name, FUNC, info.currentline, ARROW, msg}
            else
                _log{DBG_TAG, info.short_src, COLON, info.currentline, ARROW, msg}
            end
        else
            _log{DBG_TAG, msg}
        end
    end
end

-- log info messages
---@param msg any message
function log.info(msg) _log{INF_TAG, msg} end

-- log warning messages
---@param msg any message
function log.warning(msg) _log{WRN_TAG, msg} end

-- log error messages
---@param msg any message
---@param trace? boolean include file trace
function log.error(msg, trace)
    if trace then
        local info = debug.getinfo(2)

        if info.name ~= nil then
            _log{ERR_TAG, info.short_src, COLON, info.name, FUNC, info.currentline, ARROW, msg}
        else
            _log{ERR_TAG, info.short_src, COLON, info.currentline, ARROW, msg}
        end
    else
        _log{ERR_TAG, msg}
    end
end

-- log fatal errors
---@param msg any message
function log.fatal(msg) _log{FTL_TAG, msg} end

return log
