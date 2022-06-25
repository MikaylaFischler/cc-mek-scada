--
-- Publisher-Subscriber Interconnect Layer
--

local psil = {}

-- instantiate a new PSI layer
function psil.create()
    local self = {
        ic = {}
    }

    -- allocate a new interconnect field
    ---@key string data key
    local function alloc(key)
        self.ic[key] = { subscribers = {}, value = 0 }
    end

    ---@class psil
    local public = {}

    -- subscribe to a data object in the interconnect
    ---@param key string data key
    ---@param func function function to call on change
    function public.subscribe(key, func)
        if self.ic[key] == nil then alloc(key) end
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

    return public
end

return psil
