local log   = require("scada-common.log")
local rsio  = require("scada-common.rsio")
local util  = require("scada-common.util")

local rsctl = require("supervisor.session.rsctl")
local unit  = require("supervisor.session.unit")

local HEATING_WATER  = 20000
local HEATING_SODIUM = 200000

-- 7.14 kJ per blade for 1 mB of fissile fuel
local POWER_PER_BLADE = util.joules_to_fe(7140)

local function m_avg(length, default)
    local data = {}
    local index = 1
    local last_t = 0    ---@type number|nil

    ---@class moving_average
    local public = {}

    -- reset all to a given value
    ---@param x number value
    function public.reset(x)
        data = {}
        for _ = 1, length do table.insert(data, x) end
    end

    -- record a new value
    ---@param x number new value
    ---@param t number? optional last update time to prevent duplicated entries
    function public.record(x, t)
        if type(t) == "number" and last_t == t then
            return
        end

        data[index] = x
        last_t = t

        index = index + 1
        if index > length then index = 1 end
    end

    -- compute the moving average
    ---@return number average
    function public.compute()
        local sum = 0
        for i = 1, length do sum = sum + data[i] end
        return sum
    end

    public.reset(default)

    return public
end

---@alias PROCESS integer
local PROCESS = {
    INACTIVE = 1,
    SIMPLE = 2,
    CHARGE = 3,
    GEN_RATE = 4,
    BURN_RATE = 5
}

---@class facility_management
local facility = {}

facility.PROCESS_MODES = PROCESS

-- create a new facility management object
---@param num_reactors integer number of reactor units
---@param cooling_conf table cooling configurations of reactor units
function facility.new(num_reactors, cooling_conf)
    local self = {
        -- components
        units = {},
        induction = {},
        redstone = {},
        -- process control
        mode = PROCESS.INACTIVE,
        charge_target = 0,      -- FE
        charge_rate = 0,        -- FE/t
        charge_limit = 0.99,    -- percentage
        burn_rate_set = 0,
        unit_limits = {},
        -- statistics
        im_stat_init = false,
        avg_charge = m_avg(10, 0.0),
        avg_inflow = m_avg(10, 0.0),
        avg_outflow = m_avg(10, 0.0)
    }

    -- create units
    for i = 1, num_reactors do
        table.insert(self.units, unit.new(i, cooling_conf[i].BOILERS, cooling_conf[i].TURBINES))

        local u_lim = { burn_rate = -1.0, temp = 1100 } ---@class unit_limit
        table.insert(self.unit_limits, u_lim)
    end

    -- init redstone RTU I/O controller
    local rs_rtu_io_ctl = rsctl.new(self.redstone)

    -- unlink disconnected units
    ---@param sessions table
    local function _unlink_disconnected_units(sessions)
        util.filter_table(sessions, function (u) return u.is_connected() end)
    end

    -- PUBLIC FUNCTIONS --

    ---@class facility
    local public = {}

    -- ADD/LINK DEVICES --

    -- link a redstone RTU session
    ---@param rs_unit unit_session
    function public.add_redstone(rs_unit)
        table.insert(self.redstone, rs_unit)
    end

    -- link an imatrix RTU session
    ---@param imatrix unit_session
    function public.add_imatrix(imatrix)
        table.insert(self.induction, imatrix)
    end

    -- purge devices associated with the given RTU session ID
    ---@param session integer RTU session ID
    function public.purge_rtu_devices(session)
        util.filter_table(self.redstone,  function (s) return s.get_session_id() ~= session end)
        util.filter_table(self.induction, function (s) return s.get_session_id() ~= session end)
    end

    -- UPDATE --

    -- update (iterate) the facility management
    function public.update()
        -- unlink RTU unit sessions if they are closed
        _unlink_disconnected_units(self.induction)
        _unlink_disconnected_units(self.redstone)
    end

    function public.update_units()
        for i = 1, #self.units do
            local u = self.units[i] ---@type reactor_unit
            u.update()
        end
    end

    -- READ STATES/PROPERTIES --

    -- get build properties of all machines
    function public.get_build()
        local build = {}

        build.induction = {}
        for i = 1, #self.induction do
            local matrix = self.induction[i]    ---@type unit_session
            build.induction[matrix.get_device_idx()] = { matrix.get_db().formed, matrix.get_db().build }
        end

        return build
    end

    -- get RTU statuses
    function public.get_rtu_statuses()
        local status = {}

        -- status of induction matricies (including tanks)
        status.induction = {}
        for i = 1, #self.induction do
            local matrix = self.induction[i]  ---@type unit_session
            status.induction[matrix.get_device_idx()] = {
                matrix.is_faulted(),
                matrix.get_db().formed,
                matrix.get_db().state,
                matrix.get_db().tanks
            }
        end

        ---@todo other RTU statuses

        return status
    end

    function public.get_units()
        return self.units
    end

    return public
end

return facility
