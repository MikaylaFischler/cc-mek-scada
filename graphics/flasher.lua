--
-- Indicator Light Flasher
--

local tcd = require("scada-common.tcallbackdsp")

local flasher = {}

-- note: no additional call needs to be made in a main loop as this class automatically uses the TCD to operate

---@alias PERIOD integer
local PERIOD = {
    BLINK_250_MS = 1,
    BLINK_500_MS = 2,
    BLINK_1000_MS = 3
}

flasher.PERIOD = PERIOD

local active = false
local registry = { {}, {}, {} } -- one registry table per period
local callback_counter = 0

-- blink registered indicators
--
-- this assumes it is called every 250ms, it does no checking of time on its own
local function callback_250ms()
    if active then
        for _, f in pairs(registry[PERIOD.BLINK_250_MS]) do f() end

        if callback_counter % 2 == 0 then
            for _, f in pairs(registry[PERIOD.BLINK_500_MS]) do f() end
        end

        if callback_counter % 4 == 0 then
            for _, f in pairs(registry[PERIOD.BLINK_1000_MS]) do f() end
        end

        callback_counter = callback_counter + 1

        tcd.dispatch(0.25, callback_250ms)
    end
end

-- start the flasher periodic
function flasher.init()
    active = true
    registry = { {}, {}, {} }
    callback_250ms()
end

-- clear all blinking indicators and stop the flasher periodic
function flasher.clear()
    active = false
    registry = { {}, {}, {} }
end

-- register a function to be called on the selected blink period
--
-- times are not strictly enforced, but all with a given period will be set at the same time
---@param f function function to call each period
---@param period PERIOD time period option (1, 2, or 3)
function flasher.start(f, period)
    if type(registry[period]) == "table" then
        table.insert(registry[period], f)
    end
end

-- stop a function from being called at the blink period
---@param f function function callback registered
function flasher.stop(f)
    for i = 1, #registry do
        for j = 1, #registry[i] do
            if registry[i][j] == f then
                registry[i][j] = nil
                break
            end
        end
    end
end

return flasher