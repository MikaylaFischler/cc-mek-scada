--
-- MODBUS Transaction Controller
--

local util = require("scada-common.util")

local txnctrl = {}

local TIMEOUT = 2000    -- 2000ms max wait

-- create a new transaction controller
---@nodiscard
function txnctrl.new()
    local self = {
        list = {},
        next_id = 0
    }

    ---@class transaction_controller
    local public = {}

    local insert = table.insert
    local remove = table.remove

    -- get the length of the transaction list
    ---@nodiscard
    function public.length()
        return #self.list
    end

    -- check if there are no active transactions
    ---@nodiscard
    function public.empty()
        return #self.list == 0
    end

    -- create a new transaction of the given type
    ---@nodiscard
    ---@param txn_type integer
    ---@return integer txn_id
    function public.create(txn_type)
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
    ---@nodiscard
    ---@param txn_id integer
    ---@return integer|nil txn_type
    function public.resolve(txn_id)
        local txn_type = nil

        for i = 1, public.length() do
            if self.list[i].txn_id == txn_id then
                local entry = remove(self.list, i)
                txn_type = entry.txn_type
                break
            end
        end

        return txn_type
    end

    -- renew a transaction by re-inserting it with its ID and type
    ---@param txn_id integer
    ---@param txn_type integer
    function public.renew(txn_id, txn_type)
        insert(self.list, {
            txn_id = txn_id,
            txn_type = txn_type,
            expiry = util.time() + TIMEOUT
        })
    end

    -- close timed-out transactions
    function public.cleanup()
        local now = util.time()
        util.filter_table(self.list, function (txn) return txn.expiry > now end)
    end

    -- clear the transaction list
    function public.clear()
        self.list = {}
    end

    return public
end

return txnctrl
