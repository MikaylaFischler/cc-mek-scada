local log   = require("scada-common.log")
local rsio  = require("scada-common.rsio")
local types = require("scada-common.types")
local util  = require("scada-common.util")

local unit  = require("supervisor.unit")

local rsctl = require("supervisor.session.rsctl")

local PROCESS = types.PROCESS
local PROCESS_NAMES = types.PROCESS_NAMES

local IO = rsio.IO

-- 7.14 kJ per blade for 1 mB of fissile fuel<br>
-- 2856 FE per blade per 1 mB, 285.6 FE per blade per 0.1 mB (minimum)
local POWER_PER_BLADE = util.joules_to_fe(7140)

local FLOW_STABILITY_DELAY_S = unit.FLOW_STABILITY_DELAY_MS / 1000

-- background radiation 0.0000001 Sv/h (99.99 nSv/h)
-- "green tint" radiation 0.00001 Sv/h (10 uSv/h)
-- damaging radiation 0.00006 Sv/h (60 uSv/h)
local RADIATION_ALARM_LEVEL = 0.00001

local HIGH_CHARGE = 1.0
local RE_ENABLE_CHARGE = 0.95

local AUTO_SCRAM = {
    NONE = 0,
    MATRIX_DC = 1,
    MATRIX_FILL = 2,
    CRIT_ALARM = 3,
    RADIATION = 4,
    GEN_FAULT = 5
}

local START_STATUS = {
    OK = 0,
    NO_UNITS = 1,
    BLADE_MISMATCH = 2
}

local charge_Kp = 0.275
local charge_Ki = 0.0
local charge_Kd = 4.5

local rate_Kp = 2.45
local rate_Ki = 0.4825
local rate_Kd = -1.0

---@class facility_management
local facility = {}

-- create a new facility management object
---@param num_reactors integer number of reactor units
---@param cooling_conf table cooling configurations of reactor units
function facility.new(num_reactors, cooling_conf)
    local self = {
        units = {},
        status_text = { "START UP", "initializing..." },
        all_sys_ok = false,
        -- rtus
        rtu_conn_count = 0,
        redstone = {},
        induction = {},
        envd = {},
        -- redstone I/O control
        io_ctl = nil,   ---@type rs_controller
        -- process control
        units_ready = false,
        mode = PROCESS.INACTIVE,
        last_mode = PROCESS.INACTIVE,
        return_mode = PROCESS.INACTIVE,
        mode_set = PROCESS.MAX_BURN,
        start_fail = START_STATUS.OK,
        max_burn_combined = 0.0,        -- maximum burn rate to clamp at
        burn_target = 0.1,              -- burn rate target for aggregate burn mode
        charge_setpoint = 0,            -- FE charge target setpoint
        gen_rate_setpoint = 0,          -- FE/t charge rate target setpoint
        group_map = { 0, 0, 0, 0 },     -- units -> group IDs
        prio_defs = { {}, {}, {}, {} }, -- priority definitions (each level is a table of units)
        at_max_burn = false,
        ascram = false,
        ascram_reason = AUTO_SCRAM.NONE,
        ---@class ascram_status
        ascram_status = {
            matrix_dc = false,
            matrix_fill = false,
            crit_alarm = false,
            radiation = false,
            gen_fault = false
        },
        -- closed loop control
        charge_conversion = 1.0,
        time_start = 0.0,
        initial_ramp = true,
        waiting_on_ramp = false,
        waiting_on_stable = false,
        accumulator = 0.0,
        saturated = false,
        last_update = 0,
        last_error = 0.0,
        last_time = 0.0,
        -- statistics
        im_stat_init = false,
        avg_charge = util.mov_avg(3, 0.0),
        avg_inflow = util.mov_avg(6, 0.0),
        avg_outflow = util.mov_avg(6, 0.0)
    }

    -- create units
    for i = 1, num_reactors do
        table.insert(self.units, unit.new(i, cooling_conf[i].BOILERS, cooling_conf[i].TURBINES))
    end

    -- init redstone RTU I/O controller
    self.io_ctl = rsctl.new(self.redstone)

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
    ---@param abort_on_fault boolean? true to exit if one device has an effective burn rate different than its limit
    ---@return integer unallocated_br100, boolean? aborted
    local function _allocate_burn_rate(burn_rate, ramp, abort_on_fault)
        local unallocated = math.floor(burn_rate * 100)

        -- go through all priority groups
        for i = 1, #self.prio_defs do
            local units = self.prio_defs[i]

            if #units > 0 then
                local split = math.floor(unallocated / #units)

                local splits = {}
                for u = 1, #units do splits[u] = split end
                splits[#units] = splits[#units] + (unallocated % #units)

                -- go through all reactor units in this group
                for id = 1, #units do
                    local u = units[id] ---@type reactor_unit

                    local ctl = u.get_control_inf()
                    local lim_br100 = u.a_get_effective_limit()

                    if abort_on_fault and (lim_br100 ~= ctl.lim_br100) then
                        -- effective limit differs from set limit, unit is degraded
                        return unallocated, true
                    end

                    local last = ctl.br100

                    if splits[id] <= lim_br100 then
                        ctl.br100 = splits[id]
                    else
                        ctl.br100 = lim_br100

                        if id < #units then
                            local remaining = #units - id
                            split = math.floor(unallocated / remaining)
                            for x = (id + 1), #units do splits[x] = split end
                            splits[#units] = splits[#units] + (unallocated % remaining)
                        end
                    end

                    unallocated = math.max(0, unallocated - ctl.br100)

                    if last ~= ctl.br100 then
                        log.debug("unit " .. u.get_id() .. ": set to " .. ctl.br100 .. " (was " .. last .. ")")
                        u.a_commit_br100(ramp)
                    end
                end
            end
        end

        return unallocated, false
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

    -- link an environment detector RTU session
    ---@param envd unit_session
    function public.add_envd(envd)
        table.insert(self.envd, envd)
    end

    -- purge devices associated with the given RTU session ID
    ---@param session integer RTU session ID
    function public.purge_rtu_devices(session)
        util.filter_table(self.redstone,  function (s) return s.get_session_id() ~= session end)
        util.filter_table(self.induction, function (s) return s.get_session_id() ~= session end)
        util.filter_table(self.envd,      function (s) return s.get_session_id() ~= session end)
    end

    -- UPDATE --

    -- supervisor sessions reporting the list of active RTU sessions
    ---@param rtu_sessions table session list of all connected RTUs
    function public.report_rtus(rtu_sessions)
        self.rtu_conn_count = #rtu_sessions
    end

    -- update (iterate) the facility management
    function public.update()
        -- unlink RTU unit sessions if they are closed
        _unlink_disconnected_units(self.redstone)
        _unlink_disconnected_units(self.induction)
        _unlink_disconnected_units(self.envd)

        -- current state for process control
        local charge_update = 0
        local rate_update = 0

        -- calculate moving averages for induction matrix
        if self.induction[1] ~= nil then
            local matrix = self.induction[1]    ---@type unit_session
            local db = matrix.get_db()          ---@type imatrix_session_db

            charge_update = db.tanks.last_update
            rate_update = db.state.last_update

            if (charge_update > 0) and (rate_update > 0) then
                if self.im_stat_init then
                    self.avg_charge.record(util.joules_to_fe(db.tanks.energy), charge_update)
                    self.avg_inflow.record(util.joules_to_fe(db.state.last_input), rate_update)
                    self.avg_outflow.record(util.joules_to_fe(db.state.last_output), rate_update)
                else
                    self.im_stat_init = true
                    self.avg_charge.reset(util.joules_to_fe(db.tanks.energy))
                    self.avg_inflow.reset(util.joules_to_fe(db.state.last_input))
                    self.avg_outflow.reset(util.joules_to_fe(db.state.last_output))
                end
            end
        else
            self.im_stat_init = false
        end

        self.all_sys_ok = true
        for i = 1, #self.units do
            self.all_sys_ok = self.all_sys_ok and not self.units[i].get_control_inf().degraded
        end

        -------------------------
        -- Run Process Control --
        -------------------------

        local avg_charge = self.avg_charge.compute()
        local avg_inflow = self.avg_inflow.compute()

        local now = util.time_s()

        local state_changed = self.mode ~= self.last_mode
        local next_mode = self.mode

        -- once auto control is started, sort the priority sublists by limits
        if state_changed then
            self.saturated = false

            log.debug("FAC: state changed from " .. PROCESS_NAMES[self.last_mode] .. " to " .. PROCESS_NAMES[self.mode])

            if (self.last_mode == PROCESS.INACTIVE) or (self.last_mode == PROCESS.GEN_RATE_FAULT_IDLE) then
                self.start_fail = START_STATUS.OK

                if (self.mode ~= PROCESS.MATRIX_FAULT_IDLE) and (self.mode ~= PROCESS.SYSTEM_ALARM_IDLE) then
                    -- auto clear ASCRAM
                    self.ascram = false
                    self.ascram_reason = AUTO_SCRAM.NONE
                end

                local blade_count = nil
                self.max_burn_combined = 0.0

                for i = 1, #self.prio_defs do
                    table.sort(self.prio_defs[i],
                        ---@param a reactor_unit
                        ---@param b reactor_unit
                        function (a, b) return a.get_control_inf().lim_br100 < b.get_control_inf().lim_br100 end
                    )

                    for _, u in pairs(self.prio_defs[i]) do
                        local u_blade_count = u.get_control_inf().blade_count

                        if blade_count == nil then
                            blade_count = u_blade_count
                        elseif (u_blade_count ~= blade_count) and (self.mode == PROCESS.GEN_RATE) then
                            log.warning("FAC: cannot start GEN_RATE process with inconsistent unit blade counts")
                            next_mode = PROCESS.INACTIVE
                            self.start_fail = START_STATUS.BLADE_MISMATCH
                        end

                        if self.start_fail == START_STATUS.OK then u.a_engage() end

                        self.max_burn_combined = self.max_burn_combined + (u.get_control_inf().lim_br100 / 100.0)
                    end
                end

                if blade_count == nil then
                    -- no units
                    log.warning("FAC: cannot start process control with 0 units assigned")
                    next_mode = PROCESS.INACTIVE
                    self.start_fail = START_STATUS.NO_UNITS
                else
                    self.charge_conversion = blade_count * POWER_PER_BLADE
                end
            elseif self.mode == PROCESS.INACTIVE then
                for i = 1, #self.prio_defs do
                    -- SCRAM reactors and disengage auto control
                    -- use manual SCRAM since inactive was requested, and automatic SCRAM trips an alarm
                    for _, u in pairs(self.prio_defs[i]) do
                        u.scram()
                        u.a_disengage()
                    end
                end

                log.info("FAC: disengaging auto control (now inactive)")
            end

            self.initial_ramp = true
            self.waiting_on_ramp = false
            self.waiting_on_stable = false
        else
            self.initial_ramp = false
        end

        -- update unit ready state
        local assign_count = 0
        self.units_ready = true
        for i = 1, #self.prio_defs do
            for _, u in pairs(self.prio_defs[i]) do
                assign_count = assign_count + 1
                self.units_ready = self.units_ready and u.get_control_inf().ready
            end
        end

        -- perform mode-specific operations
        if self.mode == PROCESS.INACTIVE then
            if not self.units_ready then
                self.status_text = { "NOT READY", "assigned units not ready" }
            else
                -- clear ASCRAM once ready
                self.ascram = false
                self.ascram_reason = AUTO_SCRAM.NONE

                if self.start_fail == START_STATUS.NO_UNITS and assign_count == 0 then
                    self.status_text = { "START FAILED", "no units were assigned" }
                elseif self.start_fail == START_STATUS.BLADE_MISMATCH then
                    self.status_text = { "START FAILED", "turbine blade count mismatch" }
                else
                    self.status_text = { "IDLE", "control disengaged" }
                end
            end
        elseif self.mode == PROCESS.MAX_BURN then
            -- run units at their limits
            if state_changed then
                self.time_start = now
                self.saturated = true

                self.status_text = { "MONITORED MODE", "running reactors at limit" }
                log.info(util.c("FAC: MAX_BURN process mode started"))
            end

            _allocate_burn_rate(self.max_burn_combined, true)
        elseif self.mode == PROCESS.BURN_RATE then
            -- a total aggregate burn rate
            if state_changed then
                self.time_start = now
                self.status_text = { "BURN RATE MODE", "running" }
                log.info(util.c("FAC: BURN_RATE process mode started"))
            end

            local unallocated = _allocate_burn_rate(self.burn_target, true)
            self.saturated = self.burn_target == self.max_burn_combined or unallocated > 0
        elseif self.mode == PROCESS.CHARGE then
            -- target a level of charge
            if state_changed then
                self.time_start = now
                self.last_time = now
                self.last_error = 0
                self.accumulator = 0

                self.status_text = { "CHARGE MODE", "running control loop" }
                log.info(util.c("FAC: CHARGE mode starting PID control"))
            elseif self.last_update ~= charge_update then
                -- convert to kFE to make constants not microscopic
                local error = util.round((self.charge_setpoint - avg_charge) / 1000) / 1000

                -- stop accumulator when saturated to avoid windup
                if not self.saturated then
                    self.accumulator = self.accumulator + (error * (now - self.last_time))
                end

                local runtime = now - self.time_start
                local integral = self.accumulator
                local derivative = (error - self.last_error) / (now - self.last_time)

                local P = (charge_Kp * error)
                local I = (charge_Ki * integral)
                local D = (charge_Kd * derivative)

                local output = P + I + D

                -- clamp at range -> output clamped (out_c)
                local out_c = math.max(0, math.min(output, self.max_burn_combined))

                self.saturated = output ~= out_c

                log.debug(util.sprintf("CHARGE[%f] { CHRG[%f] ERR[%f] INT[%f] => OUT[%f] OUT_C[%f] <= P[%f] I[%f] D[%d] }",
                    runtime, avg_charge, error, integral, output, out_c, P, I, D))

                _allocate_burn_rate(out_c, true)

                self.last_time = now
                self.last_error = error
            end

            self.last_update = charge_update
        elseif self.mode == PROCESS.GEN_RATE then
            -- target a rate of generation
            if state_changed then
                -- estimate an initial output
                local output = self.gen_rate_setpoint / self.charge_conversion

                local unallocated = _allocate_burn_rate(output, true)

                self.saturated = output >= self.max_burn_combined or unallocated > 0
                self.waiting_on_ramp = true

                self.status_text = { "GENERATION MODE", "starting up" }
                log.info(util.c("FAC: GEN_RATE process mode initial ramp started (initial target is ", output, " mB/t)"))
            elseif self.waiting_on_ramp then
                if _all_units_ramped() then
                    self.waiting_on_ramp = false
                    self.waiting_on_stable = true

                    self.time_start = now

                    self.status_text = { "GENERATION MODE", "holding ramped rate" }
                    log.info("FAC: GEN_RATE process mode initial ramp completed, holding for stablization time")
                end
            elseif self.waiting_on_stable then
                if (now - self.time_start) > FLOW_STABILITY_DELAY_S then
                    self.waiting_on_stable = false

                    self.time_start = now
                    self.last_time = now
                    self.last_error = 0
                    self.accumulator = 0

                    self.status_text = { "GENERATION MODE", "running control loop" }
                    log.info("FAC: GEN_RATE process mode initial hold completed, starting PID control")
                end
            elseif self.last_update ~= rate_update then
                -- convert to MFE (in rounded kFE) to make constants not microscopic
                local error = util.round((self.gen_rate_setpoint - avg_inflow) / 1000) / 1000

                -- stop accumulator when saturated to avoid windup
                if not self.saturated then
                    self.accumulator = self.accumulator + (error * (now - self.last_time))
                end

                local runtime = now - self.time_start
                local integral = self.accumulator
                local derivative = (error - self.last_error) / (now - self.last_time)

                local P = (rate_Kp * error)
                local I = (rate_Ki * integral)
                local D = (rate_Kd * derivative)

                -- velocity (rate) (derivative of charge level => rate) feed forward
                local FF = self.gen_rate_setpoint / self.charge_conversion

                local output = P + I + D + FF

                -- clamp at range -> output clamped (sp_c)
                local out_c = math.max(0, math.min(output, self.max_burn_combined))

                self.saturated = output ~= out_c

                log.debug(util.sprintf("GEN_RATE[%f] { RATE[%f] ERR[%f] INT[%f] => OUT[%f] OUT_C[%f] <= P[%f] I[%f] D[%f] }",
                    runtime, avg_inflow, error, integral, output, out_c, P, I, D))

                _allocate_burn_rate(out_c, false)

                self.last_time = now
                self.last_error = error
            end

            self.last_update = rate_update
        elseif self.mode == PROCESS.MATRIX_FAULT_IDLE then
            -- exceeded charge, wait until condition clears
            if self.ascram_reason == AUTO_SCRAM.NONE then
                next_mode = self.return_mode
                log.info("FAC: exiting matrix fault idle state due to fault resolution")
            elseif self.ascram_reason == AUTO_SCRAM.CRIT_ALARM then
                next_mode = PROCESS.SYSTEM_ALARM_IDLE
                log.info("FAC: exiting matrix fault idle state due to critical unit alarm")
            end
        elseif self.mode == PROCESS.SYSTEM_ALARM_IDLE then
            -- do nothing, wait for user to confirm (stop and reset)
        elseif self.mode == PROCESS.GEN_RATE_FAULT_IDLE then
            -- system faulted (degraded/not ready) while running generation rate mode
            -- mode will need to be fully restarted once everything is OK to re-ramp to feed-forward
            if self.units_ready then
                log.info("FAC: system ready after faulting out of GEN_RATE process mode, switching back...")
                next_mode = PROCESS.GEN_RATE
            end
        elseif self.mode ~= PROCESS.INACTIVE then
            log.error(util.c("FAC: unsupported process mode ", self.mode, ", switching to inactive"))
            next_mode = PROCESS.INACTIVE
        end

        ------------------------------
        -- Evaluate Automatic SCRAM --
        ------------------------------

        local astatus = self.ascram_status

        if self.induction[1] ~= nil then
            local matrix = self.induction[1]    ---@type unit_session
            local db = matrix.get_db()          ---@type imatrix_session_db

            -- clear matrix disconnected
            if astatus.matrix_dc then
                astatus.matrix_dc = false
                log.info("FAC: induction matrix reconnected, clearing ASCRAM condition")
            end

            -- check matrix fill too high
            local was_fill = astatus.matrix_fill
            astatus.matrix_fill = (db.tanks.energy_fill >= HIGH_CHARGE) or (astatus.matrix_fill and db.tanks.energy_fill > RE_ENABLE_CHARGE)

            if was_fill and not astatus.matrix_fill then
                log.info("FAC: charge state of induction matrix entered acceptable range <= " .. (RE_ENABLE_CHARGE * 100) .. "%")
            end

            -- check for critical unit alarms
            astatus.crit_alarm = false
            for i = 1, #self.units do
                local u = self.units[i] ---@type reactor_unit

                if u.has_critical_alarm() then
                    astatus.crit_alarm = true
                    break
                end
            end

            -- check for facility radiation
            if self.envd[1] ~= nil then
                local envd = self.envd[1]   ---@type unit_session
                local e_db = envd.get_db()  ---@type envd_session_db

                astatus.radiation = e_db.radiation_raw > RADIATION_ALARM_LEVEL
            else
                -- don't clear, if it is true then we lost it with high radiation, so just keep alarming
                -- operator can restart the system or hit the stop/reset button
            end

            -- system not ready, will need to restart GEN_RATE mode
            -- clears when we enter the fault waiting state
            astatus.gen_fault = self.mode == PROCESS.GEN_RATE and not self.units_ready
        else
            astatus.matrix_dc = true
        end

        if (self.mode ~= PROCESS.INACTIVE) and (self.mode ~= PROCESS.SYSTEM_ALARM_IDLE) then
            local scram = astatus.matrix_dc or astatus.matrix_fill or astatus.crit_alarm or astatus.gen_fault

            if scram and not self.ascram then
                -- SCRAM all units
                for i = 1, #self.prio_defs do
                    for _, u in pairs(self.prio_defs[i]) do
                        u.a_scram()
                    end
                end

                if astatus.crit_alarm then
                    -- highest priority alarm
                    next_mode = PROCESS.SYSTEM_ALARM_IDLE
                    self.ascram_reason = AUTO_SCRAM.CRIT_ALARM
                    self.status_text = { "AUTOMATIC SCRAM", "critical unit alarm tripped" }

                    log.info("FAC: automatic SCRAM due to critical unit alarm")
                    log.warning("FAC: emergency exit of process control due to critical unit alarm")
                elseif astatus.radiation then
                    next_mode = PROCESS.SYSTEM_ALARM_IDLE
                    self.ascram_reason = AUTO_SCRAM.RADIATION
                    self.status_text = { "AUTOMATIC SCRAM", "facility radiation high" }

                    log.info("FAC: automatic SCRAM due to high facility radiation")
                elseif astatus.matrix_dc then
                    next_mode = PROCESS.MATRIX_FAULT_IDLE
                    self.ascram_reason = AUTO_SCRAM.MATRIX_DC
                    self.status_text = { "AUTOMATIC SCRAM", "induction matrix disconnected" }

                    if self.mode ~= PROCESS.MATRIX_FAULT_IDLE then self.return_mode = self.mode end

                    log.info("FAC: automatic SCRAM due to induction matrix disconnection")
                elseif astatus.matrix_fill then
                    next_mode = PROCESS.MATRIX_FAULT_IDLE
                    self.ascram_reason = AUTO_SCRAM.MATRIX_FILL
                    self.status_text = { "AUTOMATIC SCRAM", "induction matrix fill high" }

                    if self.mode ~= PROCESS.MATRIX_FAULT_IDLE then self.return_mode = self.mode end

                    log.info("FAC: automatic SCRAM due to induction matrix high charge")
                elseif astatus.gen_fault then
                    -- lowest priority alarm
                    next_mode = PROCESS.GEN_RATE_FAULT_IDLE
                    self.ascram_reason = AUTO_SCRAM.GEN_FAULT
                    self.status_text = { "GENERATION MODE IDLE", "paused: system not ready" }

                    log.info("FAC: automatic SCRAM due to unit problem while in GEN_RATE mode, will resume once all units are ready")
                end
            end

            self.ascram = scram

            if not self.ascram then
                self.ascram_reason = AUTO_SCRAM.NONE

                -- reset PLC RPS trips if we should
                for i = 1, #self.units do
                    local u = self.units[i] ---@type reactor_unit
                    u.a_cond_rps_reset()
                end
            end
        end

        -- update last mode and set next mode
        self.last_mode = self.mode
        self.mode = next_mode

        -------------------------
        -- Handle Redstone I/O --
        -------------------------

        if #self.redstone > 0 then
            -- handle facility SCRAM
            if self.io_ctl.digital_read(IO.F_SCRAM) then
                for i = 1, #self.units do
                    local u = self.units[i] ---@type reactor_unit
                    u.cond_scram()
                end
            end

            -- handle facility ack
            if self.io_ctl.digital_read(IO.F_ACK) then public.ack_all() end

            -- update facility alarm output
            local has_alarm = false
            for i = 1, #self.units do
                local u = self.units[i]     ---@type reactor_unit

                if u.has_critical_alarm() then
                    has_alarm = true
                    return
                end
            end

            self.io_ctl.digital_write(IO.F_ALARM, has_alarm)
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

    -- ack all alarms on all reactor units
    function public.ack_all()
        for i = 1, #self.units do
            local u = self.units[i] ---@type reactor_unit
            u.ack_all()
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
            limits[i] = u.get_control_inf().lim_br100 * 100
        end

        -- only allow changes if not running
        if self.mode == PROCESS.INACTIVE then
            if (type(config.mode) == "number") and (config.mode > PROCESS.INACTIVE) and (config.mode <= PROCESS.GEN_RATE) then
                self.mode_set = config.mode
            end

            if (type(config.burn_target) == "number") and config.burn_target >= 0.1 then
                self.burn_target = config.burn_target
            end

            if (type(config.charge_target) == "number") and config.charge_target >= 0 then
                self.charge_setpoint = config.charge_target * 1000000  -- convert MFE to FE
            end

            if (type(config.gen_target) == "number") and config.gen_target >= 0 then
                self.gen_rate_setpoint = config.gen_target * 1000   -- convert kFE to FE
            end

            if (type(config.limits) == "table") and (#config.limits == num_reactors) then
                for i = 1, num_reactors do
                    local limit = config.limits[i]

                    if (type(limit) == "number") and (limit >= 0.1) then
                        limits[i] = limit
                        self.units[i].set_burn_limit(limit)
                    end
                end
            end

            ready = self.mode_set > 0

            if (self.mode_set == PROCESS.CHARGE) and (self.charge_setpoint <= 0) then
                ready = false
            elseif (self.mode_set == PROCESS.GEN_RATE) and (self.gen_rate_setpoint <= 0) then
                ready = false
            elseif (self.mode_set == PROCESS.BURN_RATE) and (self.burn_target < 0.1) then
                ready = false
            end

            ready = ready and self.units_ready

            if ready then self.mode = self.mode_set end
        end

        return { ready, self.mode_set, self.burn_target, self.charge_setpoint, self.gen_rate_setpoint, limits }
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

            self.group_map[unit_id] = group

            -- add to group if not independent
            if group > 0 then
                table.insert(self.prio_defs[group], self.units[unit_id])
            end
        end
    end

    -- READ STATES/PROPERTIES --

    -- get build properties of all machines
    ---@param inc_imatrix boolean? true/nil to include induction matrix build, false to exclude
    function public.get_build(inc_imatrix)
        local build = {}

        if inc_imatrix ~= false then
            build.induction = {}
            for i = 1, #self.induction do
                local matrix = self.induction[i]    ---@type unit_session
                build.induction[matrix.get_device_idx()] = { matrix.get_db().formed, matrix.get_db().build }
            end
        end

        return build
    end

    -- get automatic process control status
    function public.get_control_status()
        local astat = self.ascram_status
        return {
            self.all_sys_ok,
            self.units_ready,
            self.mode,
            self.waiting_on_ramp or self.waiting_on_stable,
            self.at_max_burn or self.saturated,
            self.ascram,
            astat.matrix_dc,
            astat.matrix_fill,
            astat.crit_alarm,
            astat.radiation,
            astat.gen_fault or self.mode == PROCESS.GEN_RATE_FAULT_IDLE,
            self.status_text[1],
            self.status_text[2],
            self.group_map
        }
    end

    -- get RTU statuses
    function public.get_rtu_statuses()
        local status = {}

        -- total count of all connected RTUs in the facility
        status.count = self.rtu_conn_count

        -- power averages from induction matricies
        status.power = {
            self.avg_charge.compute(),
            self.avg_inflow.compute(),
            self.avg_outflow.compute()
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

        -- radiation monitors (environment detectors)
        status.rad_mon = {}
        for i = 1, #self.envd do
            local envd = self.envd[i]   ---@type unit_session
            status.rad_mon[envd.get_device_idx()] = {
                envd.is_faulted(),
                envd.get_db().radiation
            }
        end

        return status
    end

    function public.get_units()
        return self.units
    end

    return public
end

return facility
