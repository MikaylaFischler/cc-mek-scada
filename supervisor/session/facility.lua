local log   = require("scada-common.log")
local rsio  = require("scada-common.rsio")
local types = require("scada-common.types")
local util  = require("scada-common.util")

local rsctl = require("supervisor.session.rsctl")
local unit  = require("supervisor.session.unit")

local PROCESS = types.PROCESS

-- 7.14 kJ per blade for 1 mB of fissile fuel<br/>
-- 2856 FE per blade per 1 mB, 285.6 FE per blade per 0.1 mB (minimum)
local POWER_PER_BLADE = util.joules_to_fe(7140)

local MAX_CHARGE = 0.99
local RE_ENABLE_CHARGE = 0.95

local AUTO_SCRAM = {
    NONE = 0,
    MATRIX_DC = 1,
    MATRIX_FILL = 2
}

local charge_Kp = 1.0
local charge_Ki = 0.00001
local charge_Kd = 0.0

local rate_Kp = 1.0
local rate_Ki = 0.00001
local rate_Kd = 0.0

---@class facility_management
local facility = {}

-- create a new facility management object
---@param num_reactors integer number of reactor units
---@param cooling_conf table cooling configurations of reactor units
function facility.new(num_reactors, cooling_conf)
    local self = {
        units = {},
        induction = {},
        redstone = {},
        -- process control
        mode = PROCESS.INACTIVE,
        last_mode = PROCESS.INACTIVE,
        mode_set = PROCESS.SIMPLE,
        max_burn_combined = 0.0,        -- maximum burn rate to clamp at
        burn_target = 0.1,              -- burn rate target for aggregate burn mode
        charge_target = 0,              -- FE charge target
        gen_rate_target = 0,            -- FE/t charge rate target
        group_map = { 0, 0, 0, 0 },     -- units -> group IDs
        prio_defs = { {}, {}, {}, {} }, -- priority definitions (each level is a table of units)
        ascram = false,
        ascram_reason = AUTO_SCRAM.NONE,
        -- closed loop control
        charge_conversion = 1.0,
        time_start = 0.0,
        initial_ramp = true,
        waiting_on_ramp = false,
        accumulator = 0.0,
        saturated = false,
        last_error = 0.0,
        last_time = 0.0,
        -- statistics
        im_stat_init = false,
        avg_charge = util.mov_avg(10, 0.0),
        avg_inflow = util.mov_avg(10, 0.0),
        avg_outflow = util.mov_avg(10, 0.0)
    }

    -- create units
    for i = 1, num_reactors do
        table.insert(self.units, unit.new(i, cooling_conf[i].BOILERS, cooling_conf[i].TURBINES))
    end

    -- init redstone RTU I/O controller
    local rs_rtu_io_ctl = rsctl.new(self.redstone)

    -- unlink disconnected units
    ---@param sessions table
    local function _unlink_disconnected_units(sessions)
        util.filter_table(sessions, function (u) return u.is_connected() end)
    end

    -- check if all auto-controlled units completed ramping
    local function _all_units_ramped()
        local all_ramped = true

        for i = 1, #self.prio_defs do
            local units = self.prio_defs[i]
            for u = 1, #units do
                all_ramped = all_ramped and units[u].a_ramp_complete()
            end
        end

        return all_ramped
    end

    -- split a burn rate among the reactors
    ---@param burn_rate number burn rate assignment
    ---@param ramp boolean true to ramp, false to set right away
    local function _allocate_burn_rate(burn_rate, ramp)
        local unallocated = math.floor(burn_rate * 10)

        -- go through alll priority groups
        for i = 1, #self.prio_defs and (unallocated > 0) do
            local units = self.prio_defs[i]
            local split = math.floor(unallocated / #units)

            local splits = {}
            for u = 1, #units do splits[u] = split end
            splits[#units] = splits[#units] + (unallocated % #units)

            -- go through all reactor units in this group
            for u = 1, #units do
                local ctl = units[u].get_control_inf()  ---@type unit_control
                local last = ctl.br10

                if splits[u] <= ctl.lim_br10 then
                    ctl.br10 = splits[u]
                else
                    ctl.br10 = ctl.lim_br10

                    if u < #units then
                        local remaining = #units - u
                        split = math.floor(unallocated / remaining)
                        for x = (u + 1), #units do splits[x] = split end
                        splits[#units] = splits[#units] + (unallocated % remaining)
                    end
                end

                unallocated = unallocated - ctl.br10

                if last ~= ctl.br10 then units[u].a_commit_br10(ramp) end
            end
        end
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

        -- calculate moving averages for induction matrix
        if self.induction[1] ~= nil then
            local matrix = self.induction[1]    ---@type unit_session
            local db = matrix.get_db()          ---@type imatrix_session_db

            if (db.state.last_update > 0) and (db.tanks.last_update > 0) then
                if self.im_stat_init then
                    self.avg_charge.record(db.tanks.energy, db.tanks.last_update)
                    self.avg_inflow.record(db.state.last_input, db.state.last_update)
                    self.avg_outflow.record(db.state.last_output, db.state.last_update)
                else
                    self.im_stat_init = true
                    self.avg_charge.reset(db.tanks.energy)
                    self.avg_inflow.reset(db.state.last_input)
                    self.avg_outflow.reset(db.state.last_output)
                end
            end
        else
            self.im_stat_init = false
        end

        -------------------------
        -- Run Process Control --
        -------------------------

        local avg_charge = self.avg_charge.compute()
        local avg_inflow = self.avg_inflow.compute()

        local now = util.time_s()

        local state_changed = self.mode ~= self.last_mode

        -- once auto control is started, sort the priority sublists by limits
        if state_changed then
            if self.last_mode == PROCESS.INACTIVE then
                local blade_count = 0
                self.max_burn_combined = 0.0

                for i = 1, #self.prio_defs do
                    table.sort(self.prio_defs[i],
                        ---@param a reactor_unit
                        ---@param b reactor_unit
                        function (a, b) return a.get_control_inf().lim_br10 < b.get_control_inf().lim_br10 end
                    )

                    for _, u in pairs(self.prio_defs[i]) do
                        blade_count = blade_count + u.get_db().blade_count
                        u.a_engage()
                        self.max_burn_combined = self.max_burn_combined + (u.get_control_inf().lim_br10 / 10.0)
                    end
                end

                self.charge_conversion = blade_count * POWER_PER_BLADE
            elseif self.mode == PROCESS.INACTIVE then
                for i = 1, #self.prio_defs do
                    for _, u in pairs(self.prio_defs[i]) do
                        u.a_disengage()
                    end
                end
            end

            self.initial_ramp = true
            self.waiting_on_ramp = false
        else
            self.initial_ramp = false
        end

        if self.mode == PROCESS.SIMPLE then
            -- run units at their last configured set point
            if state_changed then
                self.time_start = now
            end
        elseif self.mode == PROCESS.BURN_RATE then
            -- a total aggregate burn rate
            if state_changed then
                -- nothing special to do
            elseif self.waiting_on_ramp and _all_units_ramped() then
                self.waiting_on_ramp = false
                self.time_start = now
            end

            if not self.waiting_on_ramp then
                _allocate_burn_rate(self.burn_target, self.initial_ramp)
            end
        elseif self.mode == PROCESS.CHARGE then
            -- target a level of charge
            local error = (self.charge_target - avg_charge) / self.charge_conversion

            if state_changed then
                -- nothing special to do
            elseif self.waiting_on_ramp and _all_units_ramped() then
                self.waiting_on_ramp = false

                self.time_start = now
                self.accumulator = 0
            end

            if not self.waiting_on_ramp then
                if not self.saturated then
                    self.accumulator = self.accumulator + ((avg_charge / self.charge_conversion) * (now - self.last_time))
                end

                local runtime = now - self.time_start
                local integral = self.accumulator
                -- local derivative = (error - self.last_error) / (now - self.last_time)

                local P = (charge_Kp * error)
                local I = (charge_Ki * integral)
                local D = 0 -- (charge_Kd * derivative)

                local setpoint = P + I + D

                -- round setpoint -> setpoint rounded (sp_r)
                local sp_r = util.round(setpoint * 10.0) / 10.0

                -- clamp at range -> setpoint clamped (sp_c)
                local sp_c = math.max(0, math.min(sp_r, self.max_burn_combined))

                self.saturated = sp_r ~= sp_c

                log.debug(util.sprintf("PROC_CHRG[%f] { CHRG[%f] ERR[%f] INT[%f] => SP[%f] SP_C[%f] <= P[%f] I[%f] D[%d] }",
                    runtime, avg_charge, error, integral, setpoint, sp_c, P, I, D))

                _allocate_burn_rate(sp_c, self.initial_ramp)

                if self.initial_ramp then
                    self.waiting_on_ramp = true
                end
            end
        elseif self.mode == PROCESS.GEN_RATE then
            -- target a rate of generation
            local error = (self.gen_rate_target - avg_inflow) / self.charge_conversion
            local setpoint = 0.0

            if state_changed then
                -- estimate an initial setpoint
                setpoint = error / self.charge_conversion

                local sp_r = util.round(setpoint * 10.0) / 10.0

                _allocate_burn_rate(sp_r, true)
            elseif self.waiting_on_ramp and _all_units_ramped() then
                self.waiting_on_ramp = false

                self.time_start = now
                self.accumulator = 0
            end

            if not self.waiting_on_ramp then
                if not self.saturated then
                    self.accumulator = self.accumulator + ((avg_inflow / self.charge_conversion) * (now - self.last_time))
                end

                local runtime = util.time_s() - self.time_start
                local integral = self.accumulator
                -- local derivative = (error - self.last_error) / (now - self.last_time)

                local P = (rate_Kp * error)
                local I = (rate_Ki * integral)
                local D = 0 -- (rate_Kd * derivative)

                setpoint = P + I + D

                -- round setpoint -> setpoint rounded (sp_r)
                local sp_r = util.round(setpoint * 10.0) / 10.0

                -- clamp at range -> setpoint clamped (sp_c)
                local sp_c = math.max(0, math.min(sp_r, self.max_burn_combined))

                self.saturated = sp_r ~= sp_c

                log.debug(util.sprintf("PROC_RATE[%f] { RATE[%f] ERR[%f] INT[%f] => SP[%f] SP_C[%f] <= P[%f] I[%f] D[%f] }",
                    runtime, avg_inflow, error, integral, setpoint, sp_c, P, I, D))

                _allocate_burn_rate(sp_c, false)
            end
        end

        ------------------------------
        -- Evaluate Automatic SCRAM --
        ------------------------------

        if self.mode ~= PROCESS.INACTIVE then
            local scram = false

            if self.induction[1] ~= nil then
                local matrix = self.induction[1]    ---@type unit_session
                local db = matrix.get_db()          ---@type imatrix_session_db

                if self.ascram_reason == AUTO_SCRAM.MATRIX_DC then
                    self.ascram_reason = AUTO_SCRAM.NONE
                end

                if (db.tanks.energy_fill > MAX_CHARGE) or
                   (self.ascram_reason == AUTO_SCRAM.MATRIX_FILL and db.tanks.energy_fill > RE_ENABLE_CHARGE) then
                    scram = true

                    if self.ascram_reason == AUTO_SCRAM.NONE then
                        self.ascram_reason = AUTO_SCRAM.MATRIX_FILL
                    end
                end
            else
                scram = true
                if self.ascram_reason == AUTO_SCRAM.NONE then
                    self.ascram_reason = AUTO_SCRAM.MATRIX_DC
                end
            end

            -- SCRAM all units
            if not self.ascram and scram then
                for i = 1, #self.prio_defs do
                    for _, u in pairs(self.prio_defs[i]) do
                        u.a_scram()
                    end
                end

                self.ascram = true
            end
        end
    end

    -- call the update function of all units in the facility
    function public.update_units()
        for i = 1, #self.units do
            local u = self.units[i] ---@type reactor_unit
            u.update()
        end
    end

    -- COMMANDS --

    -- SCRAM all reactor units
    function public.scram_all()
        for i = 1, #self.units do
            local u = self.units[i] ---@type reactor_unit
            u.scram()
        end
    end

    -- stop auto control
    function public.auto_stop()
        self.mode = PROCESS.INACTIVE
    end

    -- set automatic control configuration and start the process
    ---@param config coord_auto_config configuration
    ---@return table response ready state (successfully started) and current configuration (after updating)
    function public.auto_start(config)
        local ready = false

        -- load up current limits
        local limits = {}
        for i = 1, num_reactors do
            local u = self.units[i] ---@type reactor_unit
            limits[i] = u.get_control_inf().lim_br10 * 10
        end

        -- only allow changes if not running
        if self.mode == PROCESS.INACTIVE then
            if (type(config.mode) == "number") and (config.mode > PROCESS.INACTIVE) and (config.mode <= PROCESS.SIMPLE) then
                self.mode_set = config.mode
            end

            if (type(config.burn_target) == "number") and config.burn_target >= 0.1 then
                self.burn_target = config.burn_target
                log.debug("SET BURN TARGET " .. config.burn_target)
            end

            if (type(config.charge_target) == "number") and config.charge_target >= 0 then
                self.charge_target = config.charge_target
                log.debug("SET CHARGE TARGET " .. config.charge_target)
            end

            if (type(config.gen_target) == "number") and config.gen_target >= 0 then
                self.gen_rate_target = config.gen_target
                log.debug("SET RATE TARGET " .. config.gen_target)
            end

            if (type(config.limits) == "table") and (#config.limits == num_reactors) then
                for i = 1, num_reactors do
                    local limit = config.limits[i]

                    if (type(limit) == "number") and (limit >= 0.1) then
                        limits[i] = limit
                        self.units[i].set_burn_limit(limit)
                        log.debug("SET UNIT " .. i .. " LIMIT " .. limit)
                    end
                end
            end

            ready = self.mode_set > 0

            if (self.mode_set == PROCESS.CHARGE) and (self.charge_target <= 0) then
                ready = false
            elseif (self.mode_set == PROCESS.GEN_RATE) and (self.gen_rate_target <= 0) then
                ready = false
            elseif (self.mode_set == PROCESS.BURN_RATE) and (self.burn_target <= 0.1) then
                ready = false
            end

            if ready then self.mode = self.mode_set end
        end

        return { ready, self.mode_set, self.burn_target, self.charge_target, self.gen_rate_target, limits }
    end

    -- SETTINGS --

    -- set the automatic control group of a unit
    ---@param unit_id integer unit ID
    ---@param group integer group ID or 0 for independent
    function public.set_group(unit_id, group)
        if group >= 0 and group <= 4 and self.mode == PROCESS.INACTIVE then
            -- remove from old group if previously assigned
            local old_group = self.group_map[unit_id]
            if old_group ~= 0 then
                util.filter_table(self.prio_defs[old_group], function (u) return u.get_id() ~= unit_id end)
            end

            self.group_map[unit] = group

            -- add to group if not independent
            if group > 0 then
                table.insert(self.prio_defs[group], self.units[unit_id])
            end
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

    -- get automatic process control status
    function public.get_control_status()
        return {
            self.mode,
            self.waiting_on_ramp,
            self.ascram,
            self.ascram_reason
        }
    end

    -- get RTU statuses
    function public.get_rtu_statuses()
        local status = {}

        -- power averages from induction matricies
        status.power = {
            self.avg_charge,
            self.avg_inflow,
            self.avg_outflow
        }

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
