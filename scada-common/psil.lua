--
-- Publisher-Subscriber Interconnect Layer
--

local util = require("scada-common.util")

local psil = {}

-- instantiate a new PSI layer
---@nodiscard
function psil.create()
    local ic = {}

    -- allocate a new interconnect field
    ---@key string data key
    local function alloc(key)
        ic[key] = { subscribers = {}, value = nil }
    end

    ---@class psil
    local public = {}

    -- subscribe to a data object in the interconnect<br>
    -- will call func() right away if a value is already avaliable
    ---@param key string data key
    ---@param func function function to call on change
    function public.subscribe(key, func)
        -- allocate new key if not found or notify if value is found
        if ic[key] == nil then
            alloc(key)
        elseif ic[key].value ~= nil then
            func(ic[key].value)
        end

        -- subscribe to key
        table.insert(ic[key].subscribers, { notify = func })
    end

    -- unsubscribe a function from a given key
    ---@param key string data key
    ---@param func function function to unsubscribe
    function public.unsubscribe(key, func)
        if ic[key] ~= nil then
            util.filter_table(ic[key].subscribers, function (s) return s.notify ~= func end)
        end
    end

    -- publish data to a given key, passing it to all subscribers if it has changed
    ---@param key string data key
    ---@param value any data value
    function public.publish(key, value)
        if ic[key] == nil then alloc(key) end

        if ic[key].value ~= value then
            for i = 1, #ic[key].subscribers do
                ic[key].subscribers[i].notify(value)
            end
        end

        ic[key].value = value
    end

    -- publish a toggled boolean value to a given key, passing it to all subscribers if it has changed<br>
    -- this is intended to be used to toggle boolean indicators such as heartbeats without extra state variables
    ---@param key string data key
    function public.toggle(key)
        if ic[key] == nil then alloc(key) end

        ic[key].value = ic[key].value == false

        for i = 1, #ic[key].subscribers do
            ic[key].subscribers[i].notify(ic[key].value)
        end
    end

    -- clear the contents of the interconnect
    function public.purge() ic = {} end

    return public
end

return psil
