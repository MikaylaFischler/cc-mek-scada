--
-- Publisher-Subscriber Interconnect Layer
--

local psil = {}

-- instantiate a new PSI layer
---@nodiscard
function psil.create()
    local self = {
        ic = {}
    }

    -- allocate a new interconnect field
    ---@key string data key
    local function alloc(key)
        self.ic[key] = { subscribers = {}, value = nil }
    end

    ---@class psil
    local public = {}

    -- subscribe to a data object in the interconnect<br>
    -- will call func() right away if a value is already avaliable
    ---@param key string data key
    ---@param func function function to call on change
    function public.subscribe(key, func)
        -- allocate new key if not found or notify if value is found
        if self.ic[key] == nil then
            alloc(key)
        elseif self.ic[key].value ~= nil then
            func(self.ic[key].value)
        end

        -- subscribe to key
        table.insert(self.ic[key].subscribers, { notify = func })
    end

    -- publish data to a given key, passing it to all subscribers if it has changed
    ---@param key string data key
    ---@param value any data value
    function public.publish(key, value)
        if self.ic[key] == nil then alloc(key) end

        if self.ic[key].value ~= value then
            for i = 1, #self.ic[key].subscribers do
                self.ic[key].subscribers[i].notify(value)
            end
        end

        self.ic[key].value = value
    end

    -- publish a toggled boolean value to a given key, passing it to all subscribers if it has changed<br>
    -- this is intended to be used to toggle boolean indicators such as heartbeats without extra state variables
    ---@param key string data key
    function public.toggle(key)
        if self.ic[key] == nil then alloc(key) end

        self.ic[key].value = self.ic[key].value == false

        for i = 1, #self.ic[key].subscribers do
            self.ic[key].subscribers[i].notify(self.ic[key].value)
        end
    end

    return public
end

return psil
