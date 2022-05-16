--
-- MODBUS Transaction Controller
--

local util = require("scada-common.util")

local txnctrl = {}

local TIMEOUT = 3000 -- 3000ms max wait

-- create a new transaction controller
txnctrl.new = function ()
    local self = {
        list = {},
        next_id = 0
    }

    ---@class transaction_controller
    local public = {}

    local insert = table.insert

    -- get the length of the transaction list
    public.length = function ()
        return #self.list
    end

    -- check if there are no active transactions
    public.empty = function ()
        return #self.list == 0
    end

    -- create a new transaction of the given type
    ---@param txn_type integer
    ---@return integer txn_id
    public.create = function (txn_type)
        local txn_id = self.next_id

        insert(self.list, {
            txn_id = txn_id,
            txn_type = txn_type,
            expiry = util.time() + TIMEOUT
        })

        self.next_id = self.next_id + 1

        return txn_id
    end

    -- mark a transaction as resolved to get its transaction type
    ---@param txn_id integer
    ---@return integer txn_type
    public.resolve = function (txn_id)
        local txn_type = nil

        for i = 1, public.length() do
            if self.list[i].txn_id == txn_id then
                txn_type = self.list[i].txn_type
                self.list[i] = nil
            end
        end

        return txn_type
    end

    -- close timed-out transactions
    public.cleanup = function ()
        local now = util.time()
        util.filter_table(self.list, function (txn) return txn.expiry > now end)
    end

    -- clear the transaction list
    public.clear = function ()
        self.list = {}
    end

    return public
end

return txnctrl
