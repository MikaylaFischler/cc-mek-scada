local const = require("scada-common.constants")
local log   = require("scada-common.log")
local rsio  = require("scada-common.rsio")
local types = require("scada-common.types")
local util  = require("scada-common.util")

local unit  = require("supervisor.unit")

local rsctl = require("supervisor.session.rsctl")

local PROCESS = types.PROCESS
local PROCESS_NAMES = types.PROCESS_NAMES
local PRIO = types.ALARM_PRIORITY
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local WASTE = types.WASTE_PRODUCT
local WASTE_MODE = types.WASTE_MODE

local IO = rsio.IO

-- 7.14 kJ per blade for 1 mB of fissile fuel<br>
-- 2856 FE per blade per 1 mB, 285.6 FE per blade per 0.1 mB (minimum)
local POWER_PER_BLADE = util.joules_to_fe(7140)

local FLOW_STABILITY_DELAY_S = const.FLOW_STABILITY_DELAY_MS / 1000

local ALARM_LIMS = const.ALARM_LIMITS

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
---@nodiscard
---@param num_reactors integer number of reactor units
---@param cooling_conf table cooling configurations of reactor units
function facility.new(num_reactors, cooling_conf)
    local self = {
        units = {},
        status_text = { "START UP", "initializing..." },
        all_sys_ok = false,
        -- rtus
        rtu_conn_count = 0,
        rtu_list = {},
        redstone = {},
        induction = {},
        sps = {},
        tanks = {},
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
        group_map = {},                 -- units -> group IDs
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
        -- waste processing
        waste_product = WASTE.PLUTONIUM,
        current_waste_product = WASTE.PLUTONIUM,
        pu_fallback = false,
        -- statistics
        im_stat_init = false,
        avg_charge = util.mov_avg(3, 0.0),
        avg_inflow = util.mov_avg(6, 0.0),
        avg_outflow = util.mov_avg(6, 0.0)
    }

    -- create units
    for i = 1, num_reactors do
        table.insert(self.units, unit.new(i, cooling_conf[i].BOILERS, cooling_conf[i].TURBINES))
        table.insert(self.group_map, 0)
    end

    -- list for RTU session management
    self.rtu_list = { self.redstone, self.induction, self.sps, self.tanks, self.envd }

    -- init redstone RTU I/O controller
    self.io_ctl = rsctl.new(self.redstone)

    -- check if all auto-controlled units completed ramping
    ---@nodiscard
    local function _all_units_ramped()
        local all_ramped = true

        for i = 1, #self.prio_defs do
            local units = self.prio_defs[i]
            for u = 1, #units do
                all_ramped = all_ramped and units[u].auto_ramp_complete()
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
                    local lim_br100 = u.auto_get_effective_limit()

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

                    if last ~= ctl.br100 then u.auto_commit_br100(ramp) end
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

    -- link an induction matrix RTU session
    ---@param imatrix unit_session
    ---@return boolean linked induction matrix accepted (max 1)
    function public.add_imatrix(imatrix)
        if #self.induction == 0 then
            table.insert(self.induction, imatrix)
            return true
        else return false end
    end

    -- link an SPS RTU session
    ---@param sps unit_session
    ---@return boolean linked SPS accepted (max 1)
    function public.add_sps(sps)
        if #self.sps == 0 then
            table.insert(self.sps, sps)
            return true
        else return false end
    end

    -- link a dynamic tank RTU session
    ---@param dynamic_tank unit_session
    ---@return boolean linked dynamic tank accepted (max 1)
    function public.add_tank(dynamic_tank)
        if #self.tanks == 0 then
            table.insert(self.tanks, dynamic_tank)
            return true
        else return false end
    end

    -- link an environment detector RTU session
    ---@param envd unit_session
    ---@return boolean linked environment detector accepted (max 1)
    function public.add_envd(envd)
        if #self.envd == 0 then
            table.insert(self.envd, envd)
            return true
        else return false end
    end

    -- purge devices associated with the given RTU session ID
    ---@param session integer RTU session ID
    function public.purge_rtu_devices(session)
        for _, v in pairs(self.rtu_list) do util.filter_table(v, function (s) return s.get_session_id() ~= session end) end
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
        for _, v in pairs(self.rtu_list) do util.filter_table(v, function (u) return u.is_connected() end) end

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

        --#region Process Control

        local avg_charge = self.avg_charge.compute()
        local avg_inflow = self.avg_inflow.compute()

        local now = util.time_s()

        local state_changed = self.mode ~= self.last_mode
        local next_mode = self.mode

        -- once auto control is started, sort the priority sublists by limits
        if state_changed then
            self.saturated = false

            log.debug("FAC: state changed from " .. PROCESS_NAMES[self.last_mode + 1] .. " to " .. PROCESS_NAMES[self.mode + 1])

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

                        if self.start_fail == START_STATUS.OK then u.auto_engage() end

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
                        u.auto_disengage()
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

                -- local runtime = now - self.time_start
                local integral = self.accumulator
                local derivative = (error - self.last_error) / (now - self.last_time)

                local P = (charge_Kp * error)
                local I = (charge_Ki * integral)
                local D = (charge_Kd * derivative)

                local output = P + I + D

                -- clamp at range -> output clamped (out_c)
                local out_c = math.max(0, math.min(output, self.max_burn_combined))

                self.saturated = output ~= out_c

                -- log.debug(util.sprintf("CHARGE[%f] { CHRG[%f] ERR[%f] INT[%f] => OUT[%f] OUT_C[%f] <= P[%f] I[%f] D[%d] }",
                --     runtime, avg_charge, error, integral, output, out_c, P, I, D))

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

                -- local runtime = now - self.time_start
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

                -- log.debug(util.sprintf("GEN_RATE[%f] { RATE[%f] ERR[%f] INT[%f] => OUT[%f] OUT_C[%f] <= P[%f] I[%f] D[%f] }",
                --     runtime, avg_inflow, error, integral, output, out_c, P, I, D))

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

        --#endregion

        ------------------------------
        -- Evaluate Automatic SCRAM --
        ------------------------------

        --#region Automatic SCRAM

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
            astatus.matrix_fill = (db.tanks.energy_fill >= ALARM_LIMS.CHARGE_HIGH) or (astatus.matrix_fill and db.tanks.energy_fill > ALARM_LIMS.CHARGE_RE_ENABLE)

            if was_fill and not astatus.matrix_fill then
                log.info("FAC: charge state of induction matrix entered acceptable range <= " .. (ALARM_LIMS.CHARGE_RE_ENABLE * 100) .. "%")
            end

            -- check for critical unit alarms
            astatus.crit_alarm = false
            for i = 1, #self.units do
                local u = self.units[i] ---@type reactor_unit

                if u.has_alarm_min_prio(PRIO.CRITICAL) then
                    astatus.crit_alarm = true
                    break
                end
            end

            -- check for facility radiation
            if self.envd[1] ~= nil then
                local envd = self.envd[1]   ---@type unit_session
                local e_db = envd.get_db()  ---@type envd_session_db

                astatus.radiation = e_db.radiation_raw > ALARM_LIMS.FAC_HIGH_RAD
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
                        u.auto_scram()
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
                    u.auto_cond_rps_reset()
                end
            end
        end

        --#endregion

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

            -- update facility alarm output (check if emergency+ alarms are active)
            local has_alarm = false
            for i = 1, #self.units do
                local u = self.units[i]     ---@type reactor_unit

                if u.has_alarm_min_prio(PRIO.EMERGENCY) then
                    has_alarm = true
                    break
                end
            end

            self.io_ctl.digital_write(IO.F_ALARM, has_alarm)
        end

        -----------------------------
        -- Update Waste Processing --
        -----------------------------

        local insufficent_po_rate = false
        for i = 1, #self.units do
            local u = self.units[i] ---@type reactor_unit
            if u.get_control_inf().waste_mode == WASTE_MODE.AUTO then
                if (u.get_sna_rate() * 10.0) < u.get_burn_rate() then
                    insufficent_po_rate = true
                    break
                end
            end
        end

        if self.waste_product == WASTE.PLUTONIUM or (self.pu_fallback and insufficent_po_rate) then
            self.current_waste_product = WASTE.PLUTONIUM
        else self.current_waste_product = self.waste_product end
    end

    -- call the update function of all units in the facility<br>
    -- additionally sets the requested auto waste mode if applicable
    function public.update_units()
        for i = 1, #self.units do
            local u = self.units[i] ---@type reactor_unit
            u.auto_set_waste(self.current_waste_product)
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
    function public.auto_stop() self.mode = PROCESS.INACTIVE end

    -- set automatic control configuration and start the process
    ---@param config coord_auto_config configuration
    ---@return table response ready state (successfully started) and current configuration (after updating)
    function public.auto_start(config)
        local charge_scaler = 1000000   -- convert MFE to FE
        local gen_scaler    = 1000      -- convert kFE to FE
        local ready         = false

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
                self.charge_setpoint = config.charge_target * charge_scaler
            end

            if (type(config.gen_target) == "number") and config.gen_target >= 0 then
                self.gen_rate_setpoint = config.gen_target * gen_scaler
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

            if (self.mode_set == PROCESS.CHARGE) and (self.charge_setpoint <= 0) or
               (self.mode_set == PROCESS.GEN_RATE) and (self.gen_rate_setpoint <= 0) or
               (self.mode_set == PROCESS.BURN_RATE) and (self.burn_target < 0.1) then
                ready = false
            end

            ready = ready and self.units_ready

            if ready then self.mode = self.mode_set end
        end

        return {
            ready,
            self.mode_set,
            self.burn_target,
            self.charge_setpoint / charge_scaler,
            self.gen_rate_setpoint / gen_scaler,
            limits
        }
    end

    -- SETTINGS --

    -- set the automatic control group of a unit
    ---@param unit_id integer unit ID
    ---@param group integer group ID or 0 for independent
    function public.set_group(unit_id, group)
        if (group >= 0 and group <= 4) and (unit_id > 0 and unit_id <= num_reactors) and self.mode == PROCESS.INACTIVE then
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

    -- set waste production
    ---@param product WASTE_PRODUCT target product
    ---@return WASTE_PRODUCT product newly set value, if valid
    function public.set_waste_product(product)
        if product == WASTE.PLUTONIUM or product == WASTE.POLONIUM or product == WASTE.ANTI_MATTER then
            self.waste_product = product
        end

        return self.waste_product
    end

    -- enable/disable plutonium fallback
    ---@param enabled boolean requested state
    ---@return boolean enabled newly set value
    function public.set_pu_fallback(enabled)
        self.pu_fallback = enabled == true
        return self.pu_fallback
    end

    -- READ STATES/PROPERTIES --

    -- get build properties of all facility devices
    ---@nodiscard
    ---@param type RTU_UNIT_TYPE? type or nil to include only a particular unit type, or to include all if nil
    function public.get_build(type)
        local all = type == nil
        local build = {}

        if all or type == RTU_UNIT_TYPE.IMATRIX then
            build.induction = {}
            for i = 1, #self.induction do
                local matrix = self.induction[i]    ---@type unit_session
                build.induction[matrix.get_device_idx()] = { matrix.get_db().formed, matrix.get_db().build }
            end
        end

        if all or type == RTU_UNIT_TYPE.SPS then
            build.sps = {}
            for i = 1, #self.sps do
                local sps = self.sps[i]             ---@type unit_session
                build.sps[sps.get_device_idx()] = { sps.get_db().formed, sps.get_db().build }
            end
        end

        if all or type == RTU_UNIT_TYPE.DYNAMIC_VALVE then
            build.tanks = {}
            for i = 1, #self.tanks do
                local tank = self.tanks[i]          ---@type unit_session
                build.tanks[tank.get_device_idx()] = { tank.get_db().formed, tank.get_db().build }
            end
        end

        return build
    end

    -- get automatic process control status
    ---@nodiscard
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
            self.group_map,
            self.current_waste_product,
            (self.current_waste_product == WASTE.PLUTONIUM) and (self.waste_product ~= WASTE.PLUTONIUM)
        }
    end

    -- get RTU statuses
    ---@nodiscard
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
            local matrix = self.induction[i]    ---@type unit_session
            local db     = matrix.get_db()      ---@type imatrix_session_db
            status.induction[matrix.get_device_idx()] = { matrix.is_faulted(), db.formed, db.state, db.tanks }
        end

        -- status of sps
        status.sps = {}
        for i = 1, #self.sps do
            local sps = self.sps[i]     ---@type unit_session
            local db  = sps.get_db()    ---@type sps_session_db
            status.sps[sps.get_device_idx()] = { sps.is_faulted(), db.formed, db.state, db.tanks }
        end

        -- status of dynamic tanks
        status.tanks = {}
        for i = 1, #self.tanks do
            local tank = self.tanks[i]  ---@type unit_session
            local db   = tank.get_db()  ---@type dynamicv_session_db
            status.tanks[tank.get_device_idx()] = { tank.is_faulted(), db.formed, db.state, db.tanks }
        end

        -- radiation monitors (environment detectors)
        status.rad_mon = {}
        for i = 1, #self.envd do
            local envd = self.envd[i]   ---@type unit_session
            status.rad_mon[envd.get_device_idx()] = { envd.is_faulted(), envd.get_db().radiation }
        end

        return status
    end

    -- get the units in this facility
    ---@nodiscard
    function public.get_units() return self.units end

    return public
end

return facility
