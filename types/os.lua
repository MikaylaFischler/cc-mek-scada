-- OS Functions

-- Function templates for ComputerCraft-specific OS functions.

-- luacheck: ignore
---@diagnostic disable: missing-return, unused-local

-- Queues an event after an amount of seconds has passed, and returns the ID.
---@param timeout number
---@return integer
function os.startTimer(timeout) end

-- Cancels a previously started timer.
---@param timerID integer
---@return nil
function os.cancelTimer(timerID) end

-- Adds an event to the event queue.
---@param event string
---@param ... any
---@return nil
function os.queueEvent(event, ...) end

-- Waits for an event to occur.
---@param filter string?
---@return string, any ...
function os.pullEvent(filter) end

-- Waits for an event to occur (doesn't terminate when Ctrl-T is pressed).
---@param filter string?
---@return string, any ...
function os.pullEventRaw(filter) end

-- Sleeps for a number of seconds.
---@param time number seconds
---@return nil
function os.sleep(time) end

-- Returns the time in seconds since an epoch depending on the locale.
---@param locale string
---@return number
function os.epoch(locale) end

-- Returns the version of CraftOS running on the computer.
---@return string
function os.version() end

-- Returns the ID of the current computer.
---@return integer
function os.getComputerID() end
