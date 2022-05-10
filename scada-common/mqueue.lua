--
-- Message Queue
--

local mqueue = {}

local TYPE = {
    COMMAND = 0,
    DATA = 1,
    PACKET = 2
}

mqueue.TYPE = TYPE

mqueue.new = function ()
    local queue = {}

    local insert = table.insert
    local remove = table.remove

    local length = function ()
        return #queue
    end

    local empty = function ()
        return #queue == 0
    end

    local ready = function ()
        return #queue ~= 0
    end

    local _push = function (qtype, message)
        insert(queue, { qtype = qtype, message = message })
    end

    local push_command = function (message)
        _push(TYPE.COMMAND, message)
    end

    local push_data = function (key, value)
        _push(TYPE.DATA, { key = key, val = value })
    end

    local push_packet = function (message)
        _push(TYPE.PACKET, message)
    end

    local pop = function ()
        if #queue > 0 then
            return remove(queue, 1)
        else
            return nil
        end
    end

    return {
        length = length,
        empty = empty,
        ready = ready,
        push_packet = push_packet,
        push_data = push_data,
        push_command = push_command,
        pop = pop
    }
end

return mqueue
