--
-- Message Queue
--

local mqueue = {}

---@class queue_item
---@field qtype MQ_TYPE
---@field message any

---@class queue_data
---@field key any
---@field val any

---@enum MQ_TYPE
local TYPE = {
    COMMAND = 0,
    DATA = 1,
    PACKET = 2
}

mqueue.TYPE = TYPE

local insert = table.insert
local remove = table.remove

-- create a new message queue
---@nodiscard
function mqueue.new()
    local queue = {}

    ---@class mqueue
    local public = {}

    -- get queue length
    function public.length() return #queue end

    -- check if queue is empty
    ---@nodiscard
    ---@return boolean is_empty
    function public.empty() return #queue == 0 end

    -- check if queue has contents
    ---@nodiscard
    ---@return boolean has_contents
    function public.ready() return #queue ~= 0 end

    -- push a new item onto the queue
    ---@param qtype MQ_TYPE
    ---@param message any
    local function _push(qtype, message) insert(queue, { qtype = qtype, message = message }) end

    -- push a command onto the queue
    ---@param message any
    function public.push_command(message) _push(TYPE.COMMAND, message) end

    -- push data onto the queue
    ---@param key any
    ---@param value any
    function public.push_data(key, value) _push(TYPE.DATA, { key = key, val = value }) end

    -- push a packet onto the queue
    ---@param packet packet|frame
    function public.push_packet(packet) _push(TYPE.PACKET, packet) end

    -- get an item off the queue
    ---@nodiscard
    ---@return queue_item|nil
    function public.pop()
        if #queue > 0 then
            return remove(queue, 1)
        else return nil end
    end

    return public
end

return mqueue
