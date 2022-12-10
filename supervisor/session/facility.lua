local log   = require("scada-common.log")
local rsio  = require("scada-common.rsio")
local util  = require("scada-common.util")

local rsctl = require("supervisor.session.rsctl")

---@class facility_management
local facility = {}

-- create a new facility management object
function facility.new()
    local self = {
        induction = {},
        redstone = {}
    }

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

    return public
end

return facility
