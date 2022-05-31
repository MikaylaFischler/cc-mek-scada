--
-- Message Queue
--

local mqueue = {}

---@alias TYPE integer
local TYPE = {
    COMMAND = 0,
    DATA = 1,
    PACKET = 2
}

mqueue.TYPE = TYPE

-- create a new message queue
function mqueue.new()
    local queue = {}

    local insert = table.insert
    local remove = table.remove

    ---@class queue_item
    ---@field qtype TYPE
    ---@field message any

    ---@class queue_data
    ---@field key any
    ---@field val any

    ---@class mqueue
    local public = {}

    -- get queue length
    function public.length() return #queue end

    -- check if queue is empty
    ---@return boolean is_empty
    function public.empty() return #queue == 0 end

    -- check if queue has contents
    function public.ready() return #queue ~= 0 end

    -- push a new item onto the queue
    ---@param qtype TYPE
    ---@param message string
    local function _push(qtype, message)
        insert(queue, { qtype = qtype, message = message })
    end

    -- push a command onto the queue
    ---@param message any
    function public.push_command(message)
        _push(TYPE.COMMAND, message)
    end

    -- push data onto the queue
    ---@param key any
    ---@param value any
    function public.push_data(key, value)
        _push(TYPE.DATA, { key = key, val = value })
    end

    -- push a packet onto the queue
    ---@param packet scada_packet|modbus_packet|rplc_packet|coord_packet|capi_packet
    function public.push_packet(packet)
        _push(TYPE.PACKET, packet)
    end

    -- get an item off the queue
    ---@return queue_item|nil
    function public.pop()
        if #queue > 0 then
            return remove(queue, 1)
        else
            return nil
        end
    end

    return public
end

return mqueue
