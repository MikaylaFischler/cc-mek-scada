local audio      = require("scada-common.audio")
local const      = require("scada-common.constants")
local log        = require("scada-common.log")
local rsio       = require("scada-common.rsio")
local types      = require("scada-common.types")
local util       = require("scada-common.util")

local plc        = require("supervisor.session.plc")
local svsessions = require("supervisor.session.svsessions")

local qtypes     = require("supervisor.session.rtu.qtypes")

local TONE           = audio.TONE

local ALARM          = types.ALARM
local PRIO           = types.ALARM_PRIORITY
local ALARM_STATE    = types.ALARM_STATE
local AUTO_GROUP     = types.AUTO_GROUP
local CONTAINER_MODE = types.CONTAINER_MODE
local PROCESS        = types.PROCESS
local PROCESS_NAMES  = types.PROCESS_NAMES
local WASTE_MODE     = types.WASTE_MODE
local WASTE          = types.WASTE_PRODUCT

local IO             = rsio.IO

local ALARM_LIMS     = const.ALARM_LIMITS

local DTV_RTU_S_DATA = qtypes.DTV_RTU_S_DATA

-- 7.14 kJ per blade for 1 mB of fissile fuel<br>
-- 2856 FE per blade per 1 mB, 285.6 FE per blade per 0.1 mB (minimum)
local POWER_PER_BLADE = util.joules_to_fe_rf(7140)

local FLOW_STABILITY_DELAY_S = const.FLOW_STABILITY_DELAY_MS / 1000

local CHARGE_Kp = 0.15
local CHARGE_Ki = 0.0
local CHARGE_Kd = 0.6

local RATE_Kp = 2.45
local RATE_Ki = 0.4825
local RATE_Kd = -1.0

local self          = nil ---@type _facility_self
local next_mode     = 0
local charge_update = 0
local rate_update   = 0

---@class facility_update_extension
local update = {}

--#region PRIVATE FUNCTIONS

-- check if all auto-controlled units completed ramping
---@nodiscard
local function all_units_ramped()
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
local function allocate_burn_rate(burn_rate, ramp, abort_on_fault)
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
                local u = units[id]

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

-- set idle state of all assigned reactors
---@param idle boolean idle state
local function set_idling(idle)
    for i = 1, #self.prio_defs do
        for _, u in pairs(self.prio_defs[i]) do u.auto_set_idle(idle) end
    end
end

--#endregion

--#region PUBLIC FUNCTIONS

-- run reboot recovery routine if needed
function update.boot_recovery()
    local RCV_STATE = self.types.RCV_STATE

    -- attempt reboot recovery if in progress
    if self.recovery == RCV_STATE.RUNNING then
        local was_inactive = self.recovery_boot_state.mode == PROCESS.INACTIVE or self.recovery_boot_state.mode == PROCESS.SYSTEM_ALARM_IDLE

        -- try to start auto control
        if self.recovery_boot_state.mode ~= nil and self.units_ready then
            if not was_inactive then
                self.mode = self.mode_set
                log.info("FAC: process startup resume initiated")
            end

            self.recovery_boot_state.mode = nil
        end

        local recovered = self.recovery_boot_state.mode == nil or was_inactive

        -- restore manual control reactors
        for i = 1, #self.units do
            local u = self.units[i]

            if self.recovery_boot_state.unit_states[i] and self.group_map[i] == AUTO_GROUP.MANUAL then
                recovered = false

                if u.get_control_inf().ready then
                    local plc_s = svsessions.get_reactor_session(i)
                    if plc_s ~= nil then
                        plc_s.in_queue.push_command(plc.PLC_S_CMDS.ENABLE)
                        log.info("FAC: startup resume enabling manually controlled reactor unit #" .. i)

                        -- only execute once
                        self.recovery_boot_state.unit_states[i] = nil
                    end
                end
            end
        end

        if recovered then
            self.recovery = RCV_STATE.STOPPED
            self.recovery_boot_state = nil
            log.info("FAC: startup resume sequence completed")
        end
    end
end

-- automatic control pre-update logic
function update.pre_auto()
    -- unlink RTU sessions if they are closed
    for _, v in pairs(self.rtu_list) do util.filter_table(v, function (u) return u.is_connected() end) end

    -- check if test routines are allowed right now
    self.allow_testing = true
    for i = 1, #self.units do
        local u = self.units[i]
        self.allow_testing = self.allow_testing and u.is_safe_idle()
    end

    -- current state for process control
    charge_update = 0
    rate_update = 0

    -- calculate moving averages for induction matrix
    if self.induction[1] ~= nil then
        local matrix = self.induction[1]
        local db = matrix.get_db()

        local build_update = db.build.last_update
        rate_update = db.state.last_update
        charge_update = db.tanks.last_update

        local has_data = build_update > 0 and rate_update > 0 and charge_update > 0

        if matrix.is_faulted() then
            -- a fault occured, cannot reliably update stats
            has_data = false
            self.im_stat_init = false
            self.imtx_faulted_times = { build_update, rate_update, charge_update }
        elseif not self.im_stat_init then
            -- prevent operation with partially invalid data
            -- all fields must have updated since the last fault
            has_data = self.imtx_faulted_times[1] < build_update and
                        self.imtx_faulted_times[2] < rate_update and
                        self.imtx_faulted_times[3] < charge_update
        end

        if has_data then
            local energy = util.joules_to_fe_rf(db.tanks.energy)
            local input  = util.joules_to_fe_rf(db.state.last_input)
            local output = util.joules_to_fe_rf(db.state.last_output)

            if self.im_stat_init then
                self.avg_charge.record(energy, charge_update)
                self.avg_inflow.record(input, rate_update)
                self.avg_outflow.record(output, rate_update)

                if charge_update ~= self.imtx_last_charge_t then
                    local delta = (energy - self.imtx_last_charge) / (charge_update - self.imtx_last_charge_t)

                    self.imtx_last_charge = energy
                    self.imtx_last_charge_t = charge_update

                    -- if the capacity changed, toss out existing data
                    if db.build.max_energy ~= self.imtx_last_capacity then
                        self.imtx_last_capacity = db.build.max_energy
                        self.avg_net.reset()
                    else
                        self.avg_net.record(delta, charge_update)
                    end
                end
            else
                self.im_stat_init = true

                self.avg_charge.reset(energy)
                self.avg_inflow.reset(input)
                self.avg_outflow.reset(output)
                self.avg_net.reset()

                self.imtx_last_capacity = db.build.max_energy
                self.imtx_last_charge = energy
                self.imtx_last_charge_t = charge_update
            end
        else
            -- prevent use by control systems
            rate_update = 0
            charge_update = 0
        end
    else
        self.im_stat_init = false
    end

    self.all_sys_ok = true
    for i = 1, #self.units do
        self.all_sys_ok = self.all_sys_ok and not self.units[i].get_control_inf().degraded
    end
end

-- run auto control
---@param ExtChargeIdling boolean ExtChargeIdling config field
function update.auto_control(ExtChargeIdling)
    local AUTO_SCRAM = self.types.AUTO_SCRAM
    local START_STATUS = self.types.START_STATUS

    local avg_charge  = self.avg_charge.compute()
    local avg_inflow  = self.avg_inflow.compute()
    local avg_outflow = self.avg_outflow.compute()

    local now = os.clock()

    local state_changed = self.mode ~= self.last_mode
    next_mode = self.mode

    -- once auto control is started, sort the priority sublists by limits
    if state_changed then
        self.saturated = false

        log.debug(util.c("FAC: state changed from ", PROCESS_NAMES[self.last_mode + 1], " to ", PROCESS_NAMES[self.mode + 1]))

        settings.set("LastProcessState", self.mode)
        if not settings.save("/supervisor.settings") then
            log.warning("facility_update.auto_control(): failed to save supervisor settings file")
        end

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

            log.debug(util.c("FAC: computed a max combined burn rate of ", self.max_burn_combined, "mB/t"))

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
                -- disable reactors and disengage auto control
                for _, u in pairs(self.prio_defs[i]) do
                    u.disable()
                    u.auto_set_idle(false)
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
            self.waiting_on_ramp = true

            self.status_text = { "MONITORED MODE", "ramping reactors to limit" }
            log.info("FAC: MAX_BURN process mode started")
        elseif self.waiting_on_ramp then
            if all_units_ramped() then
                self.waiting_on_ramp = false

                self.status_text = { "MONITORED MODE", "running reactors at limit" }
                log.info("FAC: MAX_BURN process mode initial ramp completed")
            end
        end

        allocate_burn_rate(self.max_burn_combined, true)
    elseif self.mode == PROCESS.BURN_RATE then
        -- a total aggregate burn rate
        if state_changed then
            self.time_start = now
            self.waiting_on_ramp = true

            self.status_text = { "BURN RATE MODE", "ramping to target" }
            log.info("FAC: BURN_RATE process mode started")
        elseif self.waiting_on_ramp then
            if all_units_ramped() then
                self.waiting_on_ramp = false

                self.status_text = { "BURN RATE MODE", "running" }
                log.info("FAC: BURN_RATE process mode initial ramp completed")
            end
        end

        local unallocated = allocate_burn_rate(self.burn_target, true)
        self.saturated = self.burn_target == self.max_burn_combined or unallocated > 0
    elseif self.mode == PROCESS.CHARGE then
        -- target a level of charge
        if state_changed then
            self.time_start = now
            self.last_time = now
            self.last_error = 0
            self.accumulator = 0

            -- enabling idling on all assigned units
            set_idling(true)

            self.status_text = { "CHARGE MODE", "running control loop" }
            log.info("FAC: CHARGE mode starting PID control")
        elseif self.last_update < charge_update then
            -- convert to kFE to make constants not microscopic
            local error = util.round((self.charge_setpoint - avg_charge) / 1000) / 1000

            -- stop accumulator when saturated to avoid windup
            if not self.saturated then
                self.accumulator = self.accumulator + (error * (now - self.last_time))
            end

            -- local runtime = now - self.time_start
            local integral = self.accumulator
            local derivative = (error - self.last_error) / (now - self.last_time)

            local P = CHARGE_Kp * error
            local I = CHARGE_Ki * integral
            local D = CHARGE_Kd * derivative

            local output = P + I + D

            -- clamp at range -> output clamped (out_c)
            local out_c = math.max(0, math.min(output, self.max_burn_combined))

            self.saturated = output ~= out_c

            if not ExtChargeIdling then
                -- stop idling early if the output is zero, we are at or above the setpoint, and are not losing charge
                set_idling(not ((out_c == 0) and (error <= 0) and (avg_outflow <= 0)))
            end

            -- log.debug(util.sprintf("CHARGE[%f] { CHRG[%f] ERR[%f] INT[%f] => OUT[%f] OUT_C[%f] <= P[%f] I[%f] D[%f] }",
            --     runtime, avg_charge, error, integral, output, out_c, P, I, D))

            allocate_burn_rate(out_c, true)

            self.last_time = now
            self.last_error = error
        end

        self.last_update = charge_update
    elseif self.mode == PROCESS.GEN_RATE then
        -- target a rate of generation
        if state_changed then
            -- estimate an initial output
            local output = self.gen_rate_setpoint / self.charge_conversion

            local unallocated = allocate_burn_rate(output, true)

            self.saturated = output >= self.max_burn_combined or unallocated > 0
            self.waiting_on_ramp = true

            self.status_text = { "GENERATION MODE", "starting up" }
            log.info(util.c("FAC: GEN_RATE process mode initial ramp started (initial target is ", output, " mB/t)"))
        elseif self.waiting_on_ramp then
            if all_units_ramped() then
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
        elseif self.last_update < rate_update then
            -- convert to MFE (in rounded kFE) to make constants not microscopic
            local error = util.round((self.gen_rate_setpoint - avg_inflow) / 1000) / 1000

            -- stop accumulator when saturated to avoid windup
            if not self.saturated then
                self.accumulator = self.accumulator + (error * (now - self.last_time))
            end

            -- local runtime = now - self.time_start
            local integral = self.accumulator
            local derivative = (error - self.last_error) / (now - self.last_time)

            local P = RATE_Kp * error
            local I = RATE_Ki * integral
            local D = RATE_Kd * derivative

            -- velocity (rate) (derivative of charge level => rate) feed forward
            local FF = self.gen_rate_setpoint / self.charge_conversion

            local output = P + I + D + FF

            -- clamp at range -> output clamped (sp_c)
            local out_c = math.max(0, math.min(output, self.max_burn_combined))

            self.saturated = output ~= out_c

            -- log.debug(util.sprintf("GEN_RATE[%f] { RATE[%f] ERR[%f] INT[%f] => OUT[%f] OUT_C[%f] <= P[%f] I[%f] D[%f] }",
            --     runtime, avg_inflow, error, integral, output, out_c, P, I, D))

            allocate_burn_rate(out_c, false)

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
end

-- update automatic safety logic
function update.auto_safety()
    local AUTO_SCRAM = self.types.AUTO_SCRAM

    local astatus = self.ascram_status

    -- matrix related checks
    if self.induction[1] ~= nil then
        local db = self.induction[1].get_db()

        -- check for unformed or faulted state
        local i_ok = db.formed and not self.induction[1].is_faulted()

        -- clear matrix fault if ok again
        if astatus.matrix_fault and i_ok then
            astatus.matrix_fault = false
            log.info("FAC: induction matrix OK, clearing ASCRAM condition")
        else
            astatus.matrix_fault = not i_ok
        end

        -- check matrix fill too high
        local was_fill = astatus.matrix_fill
        astatus.matrix_fill = (db.tanks.energy_fill >= ALARM_LIMS.CHARGE_HIGH) or (astatus.matrix_fill and db.tanks.energy_fill > ALARM_LIMS.CHARGE_RE_ENABLE)

        if was_fill and not astatus.matrix_fill then
            log.info(util.c("FAC: charge state of induction matrix entered acceptable range <= ", ALARM_LIMS.CHARGE_RE_ENABLE * 100, "%"))
        end

        -- system not ready, will need to restart GEN_RATE mode
        -- clears when we enter the fault waiting state
        astatus.gen_fault = self.mode == PROCESS.GEN_RATE and not self.units_ready
    else
        astatus.matrix_fault = true
    end

    -- check for critical unit alarms
    astatus.crit_alarm = false
    for i = 1, #self.units do
        local u = self.units[i]

        if u.has_alarm_min_prio(PRIO.CRITICAL) then
            astatus.crit_alarm = true
            break
        end
    end

    -- check for facility radiation
    if #self.envd > 0 then
        local max_rad = 0

        for i = 1, #self.envd do
            local envd = self.envd[i]
            local e_db = envd.get_db()
            if e_db.radiation_raw > max_rad then max_rad = e_db.radiation_raw end
        end

        astatus.radiation = max_rad >= ALARM_LIMS.FAC_HIGH_RAD
    else
        -- don't clear, if it is true then we lost it with high radiation, so just keep alarming
        -- operator can restart the system or hit the stop/reset button
    end

    if (self.mode ~= PROCESS.INACTIVE) and (self.mode ~= PROCESS.SYSTEM_ALARM_IDLE) then
        local scram = astatus.matrix_fault or astatus.matrix_fill or astatus.crit_alarm or astatus.gen_fault

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
            elseif astatus.matrix_fault then
                next_mode = PROCESS.MATRIX_FAULT_IDLE
                self.ascram_reason = AUTO_SCRAM.MATRIX_FAULT
                self.status_text = { "AUTOMATIC SCRAM", "induction matrix fault" }

                if self.mode ~= PROCESS.MATRIX_FAULT_IDLE then self.return_mode = self.mode end

                log.info("FAC: automatic SCRAM due to induction matrix disconnected, unformed, or faulted")
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
            for i = 1, #self.prio_defs do
                for _, u in pairs(self.prio_defs[i]) do
                    u.auto_cond_rps_reset()
                end
            end
        end
    end
end

-- update last mode, set next mode, and update saved state as needed
function update.post_auto()
    self.last_mode = self.mode
    self.mode = next_mode
end

-- update alarm audio control
function update.alarm_audio()
    local allow_test = self.allow_testing and self.test_tone_set

    local alarms = { false, false, false, false, false, false, false, false, false, false, false, false }

    -- reset tone states before re-evaluting
    for i = 1, #self.tone_states do self.tone_states[i] = false end

    if allow_test then
        alarms = self.test_alarm_states
    else
        -- check all alarms for all units
        for i = 1, #self.units do
            local u = self.units[i]
            for id, alarm in pairs(u.get_alarms()) do
                alarms[id] = alarms[id] or (alarm == ALARM_STATE.TRIPPED)
            end
        end

        if not self.test_tone_reset then
            -- clear testing alarms if we aren't using them
            for i = 1, #self.test_alarm_states do self.test_alarm_states[i] = false end
        end
    end

    -- Evaluate Alarms --

    -- containment breach is worst case CRITICAL alarm, this takes priority
    if alarms[ALARM.ContainmentBreach] then
        self.tone_states[TONE.T_1800Hz_Int_4Hz] = true
    else
        -- critical damage is highest priority CRITICAL level alarm
        if alarms[ALARM.CriticalDamage] then
            self.tone_states[TONE.T_660Hz_Int_125ms] = true
        else
            -- EMERGENCY level alarms + URGENT over temp
            if alarms[ALARM.ReactorDamage] or alarms[ALARM.ReactorOverTemp] or alarms[ALARM.ReactorWasteLeak] then
                self.tone_states[TONE.T_544Hz_440Hz_Alt] = true
            -- URGENT level turbine trip
            elseif alarms[ALARM.TurbineTrip] then
                self.tone_states[TONE.T_745Hz_Int_1Hz] = true
            -- URGENT level reactor lost
            elseif alarms[ALARM.ReactorLost] then
                self.tone_states[TONE.T_340Hz_Int_2Hz] = true
            -- TIMELY level alarms
            elseif alarms[ALARM.ReactorHighTemp] or alarms[ALARM.ReactorHighWaste] or alarms[ALARM.RCSTransient] then
                self.tone_states[TONE.T_800Hz_Int] = true
            end
        end

        -- check RPS transient URGENT level alarm
        if alarms[ALARM.RPSTransient] then
            self.tone_states[TONE.T_1000Hz_Int] = true
            -- disable really painful audio combination
            self.tone_states[TONE.T_340Hz_Int_2Hz] = false
        end
    end

    -- radiation is a big concern, always play this CRITICAL level alarm if active
    if alarms[ALARM.ContainmentRadiation] then
        self.tone_states[TONE.T_800Hz_1000Hz_Alt] = true
        -- we are going to disable the RPS trip alarm audio due to conflict, and if it was enabled
        -- then we can re-enable the reactor lost alarm audio since it doesn't painfully combine with this one
        if self.tone_states[TONE.T_1000Hz_Int] and alarms[ALARM.ReactorLost] then self.tone_states[TONE.T_340Hz_Int_2Hz] = true end
        -- it sounds *really* bad if this is in conjunction with these other tones, so disable them
        self.tone_states[TONE.T_745Hz_Int_1Hz] = false
        self.tone_states[TONE.T_800Hz_Int] = false
        self.tone_states[TONE.T_1000Hz_Int] = false
    end

    -- add to tone states if testing is active
    if allow_test then
        for i = 1, #self.tone_states do
            self.tone_states[i] = self.tone_states[i] or self.test_tone_states[i]
        end

        self.test_tone_reset = false
    else
        if not self.test_tone_reset then
            -- clear testing tones if we aren't using them
            for i = 1, #self.test_tone_states do self.test_tone_states[i] = false end
        end

        -- flag that tones were reset
        self.test_tone_set = false
        self.test_tone_reset = true
    end
end

-- update facility redstone
---@param ack_all function acknowledge all alarms
function update.redstone(ack_all)
    if #self.redstone > 0 then
        -- handle facility SCRAM
        if self.io_ctl.digital_read(IO.F_SCRAM) then
            for i = 1, #self.units do
                local u = self.units[i]
                u.cond_scram()
            end
        end

        -- handle facility ack
        if self.io_ctl.digital_read(IO.F_ACK) then ack_all() end

        -- update facility alarm outputs
        local has_prio_alarm, has_any_alarm = false, false
        for i = 1, #self.units do
            local u = self.units[i]

            if u.has_alarm_min_prio(PRIO.EMERGENCY) then
                has_prio_alarm, has_any_alarm = true, true
                break
            elseif u.has_alarm_min_prio(PRIO.TIMELY) then
                has_any_alarm = true
            end
        end

        self.io_ctl.digital_write(IO.F_ALARM, has_prio_alarm)
        self.io_ctl.digital_write(IO.F_ALARM_ANY, has_any_alarm)

        -- update induction matrix related outputs
        if self.induction[1] ~= nil then
            local db = self.induction[1].get_db()

            self.io_ctl.digital_write(IO.F_MATRIX_LOW, db.tanks.energy_fill < const.RS_THRESHOLDS.IMATRIX_CHARGE_LOW)
            self.io_ctl.digital_write(IO.F_MATRIX_HIGH, db.tanks.energy_fill > const.RS_THRESHOLDS.IMATRIX_CHARGE_HIGH)
            self.io_ctl.analog_write(IO.F_MATRIX_CHG, db.tanks.energy_fill, 0, 1)
        end
    end
end

-- update unit tasks
function update.unit_mgmt()
    local insufficent_po_rate = false
    local need_emcool = false
    local write_state = false

    for i = 1, #self.units do
        local u = self.units[i]

        -- update auto waste processing
        if u.get_control_inf().waste_mode == WASTE_MODE.AUTO then
            if (u.get_sna_rate() * 10.0) < u.get_burn_rate() then
                insufficent_po_rate = true
            end
        end

        -- check if unit activated emergency coolant & uses facility tanks
        if (self.cooling_conf.fac_tank_mode > 0) and u.is_emer_cool_tripped() and (self.cooling_conf.fac_tank_defs[i] == 2) then
            need_emcool = true
        end

        -- check for enabled state changes to save
        if self.last_unit_states[i] ~= u.is_reactor_enabled() then
            self.last_unit_states[i] = u.is_reactor_enabled()
            write_state = true
        end
    end

    -- record unit control states

    if write_state then
        settings.set("LastUnitStates", self.last_unit_states)
        if not settings.save("/supervisor.settings") then
            log.warning("facility_update.unit_mgmt(): failed to save supervisor settings file")
        end
    end

    -- update waste product

    self.current_waste_product = self.waste_product

    if (not self.sps_low_power) and (self.waste_product == WASTE.ANTI_MATTER) and (self.induction[1] ~= nil) then
        local db = self.induction[1].get_db()

        if db.tanks.energy_fill >= 0.15 then
            self.disabled_sps = false
        elseif self.disabled_sps or ((db.tanks.last_update > 0) and (db.tanks.energy_fill < 0.1)) then
            self.disabled_sps = true
            self.current_waste_product = WASTE.POLONIUM
        end
    else
        self.disabled_sps = false
    end

    if self.pu_fallback and insufficent_po_rate then
        self.current_waste_product = WASTE.PLUTONIUM
    end

    -- make sure dynamic tanks are allowing outflow if required
    -- set all, rather than trying to determine which is for which (simpler & safer)
    -- there should be no need for any to be in fill only mode
    if need_emcool then
        for i = 1, #self.tanks do
            local session = self.tanks[i]
            local tank = session.get_db()

            if tank.state.container_mode == CONTAINER_MODE.FILL then
                session.get_cmd_queue().push_data(DTV_RTU_S_DATA.SET_CONT_MODE, CONTAINER_MODE.BOTH)
            end
        end
    end
end

--#endregion

-- link the self instance and return the update interface
---@param fac_self _facility_self
return function (fac_self)
    self = fac_self
    return update
end
