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
mqueue.new = function ()
    local queue = {}

    local insert = table.insert
    local remove = table.remove

    ---@class queue_item
    local queue_item = {
        qtype = 0,  ---@type TYPE
        message = 0 ---@type any
    }

    ---@class mqueue
    local public = {}

    -- get queue length
    public.length = function () return #queue end

    -- check if queue is empty
    ---@return boolean is_empty
    public.empty = function () return #queue == 0 end

    -- check if queue has contents
    public.ready = function () return #queue ~= 0 end

    -- push a new item onto the queue
    ---@param qtype TYPE
    ---@param message string
    local _push = function (qtype, message)
        insert(queue, { qtype = qtype, message = message })
    end

    -- push a command onto the queue
    ---@param message any
    public.push_command = function (message)
        _push(TYPE.COMMAND, message)
    end

    -- push data onto the queue
    ---@param key any
    ---@param value any
    public.push_data = function (key, value)
        _push(TYPE.DATA, { key = key, val = value })
    end

    -- push a packet onto the queue
    ---@param packet scada_packet|modbus_packet|rplc_packet|coord_packet|capi_packet
    public.push_packet = function (packet)
        _push(TYPE.PACKET, packet)
    end

    -- get an item off the queue
    ---@return queue_item|nil
    public.pop = function ()
        if #queue > 0 then
            return remove(queue, 1)
        else
            return nil
        end
    end

    return public
end

return mqueue
