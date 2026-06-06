local audio      = require("scada-common.audio")
local const      = require("scada-common.constants")
local log        = require("scada-common.log")
local rsio       = require("scada-common.rsio")
local types      = require("scada-common.types")
local util       = require("scada-common.util")

local alarm_ctl  = require("supervisor.alarm_ctl")

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

local FLOW_STABILITY_DELAY_S = const.FLOW_STABILITY_DELAY_MS / 1000

local CHARGE_CLOSE_LOOP_WINDOW_S = 15

local CHARGE_Kp = 0.127
local CHARGE_Ki = 0.009  -- only used when near setpoint/stable
local CHARGE_Kd = 0.5

local RATE_Kp = 0.0
local RATE_Ki = 0.52
local RATE_Kd = 0.0

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
            local last_br = {}  ---@type integer[]
            local avail   = {}  ---@type { cap: integer, ctl: unit_control }[]
            local redist  = false

            -- split unallocated across this priority group
            local splits = {}
            local split  = math.floor(unallocated / #units)
            for u = 1, #units do splits[u] = split end
            splits[#units] = splits[#units] + (unallocated % #units)

            -- go through all reactor units in this group
            for id = 1, #units do
                local u = units[id]

                local ctl         = u.get_control_inf()
                local lim_br100   = u.auto_get_effective_limit()
                local f_lim_br100 = u.auto_get_fuel_limited()

                if abort_on_fault and (lim_br100 ~= ctl.lim_br100) then
                    -- effective limit differs from set limit, unit is degraded
                    return unallocated, true
                end

                last_br[u.get_id()] = ctl.br100

                if splits[id] <= f_lim_br100 then
                    ctl.br100 = splits[id]

                    unallocated = math.max(0, unallocated - ctl.br100)

                    if splits[id] < f_lim_br100 then
                        table.insert(avail, { cap = f_lim_br100 - splits[id], ctl = ctl })
                    end
                else
                    if splits[id] <= lim_br100 then
                        -- still assign the most we can so that it can recover from rate limiting
                        ctl.br100 = splits[id]
                    else
                        ctl.br100 = lim_br100
                    end

                    -- we are sorted by user limit, so it only makes sense to redistribute in this group if fuel limiting activated
                    redist = redist or (f_lim_br100 ~= lim_br100)

                    -- we know we can't go higher even if assigned, so use f_lim_br100 for the remainder
                    -- we still might go past this though, but it should correct itself afterwards
                    unallocated = math.max(0, unallocated - f_lim_br100)

                    if id < #units then
                        local remaining = #units - id
                        split = math.floor(unallocated / remaining)
                        for x = (id + 1), #units do splits[x] = split end
                        splits[#units] = splits[#units] + (unallocated % remaining)
                    end
                end
            end

            -- if we were fuel limited, we need to go through the list again since it wasn't sorted by fuel limited capacity
            if redist then
                -- check if only one with available capacity, otherwise we need to go through sorting
                if #avail == 1 then
                    local ctl = avail[1].ctl
                    local add = math.min(unallocated, avail[1].cap)

                    ctl.br100   = ctl.br100 + add
                    unallocated = math.max(0, unallocated - add)
                elseif #avail > 1 then
                    -- sort by capacity, ascending
                    table.sort(avail, function (a, b) return a.cap < b.cap end)

                    -- redistribute remainder
                    splits = {}
                    split  = math.floor(unallocated / #avail)
                    for x = 1, #avail do splits[x] = split end
                    splits[#avail] = splits[#avail] + (unallocated % #avail)

                    for id = 1, #avail do
                        local ctl  = avail[id].ctl
                        local used = math.min(splits[id], avail[id].cap)

                        ctl.br100   = ctl.br100 + used
                        unallocated = math.max(0, unallocated - used)
                    end
                end
            end

            -- commit burn rates
            for id = 1, #units do
                local u = units[id]
                if last_br[u.get_id()] ~= u.get_control_inf().br100 then u.auto_commit_br100(ramp) end
            end
        end
    end

    return unallocated, false
end

-- check if all auto-controlled units sum to meet the specified burn rate
---@nodiscard
local function reached_rate(burn_rate)
    local sum = 0.0

    for i = 1, #self.prio_defs do
        local units = self.prio_defs[i]
        for u = 1, #units do
            sum = sum + units[u].get_burn_rate()
        end
    end

    return sum == burn_rate
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

            self.imtx_percent = db.tanks.energy_fill * 100

            if self.im_stat_init then
                self.avg_charge.update(energy, charge_update)
                self.avg_inflow.update(input, rate_update)
                self.avg_outflow.update(output, rate_update)

                if charge_update ~= self.imtx_last_charge_t then
                    local delta = (energy - self.imtx_last_charge) / (charge_update - self.imtx_last_charge_t)

                    self.imtx_last_charge = energy
                    self.imtx_last_charge_t = charge_update

                    -- if the capacity changed, toss out existing data
                    if db.build.max_energy ~= self.imtx_last_capacity then
                        self.imtx_last_capacity = db.build.max_energy
                        self.avg_net.reset()
                    else
                        self.avg_net.update(delta, charge_update)
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

    -- calculate energy generated by turbines under auto control
    local turbine_gen = 0
    for i = 1, #self.prio_defs do
        local units = self.prio_defs[i]
        for u = 1, #units do
            turbine_gen = turbine_gen + units[u].get_generation_rate()
        end
    end

    self.turbine_gen_rate = util.joules_to_fe_rf(turbine_gen)

    -- update ok state
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

    local avg_charge  = self.avg_charge.get()
    local avg_inflow  = self.avg_inflow.get()
    local avg_outflow = self.avg_outflow.get()

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

        if self.last_mode == PROCESS.INACTIVE or self.last_mode == PROCESS.MATRIX_FAULT_IDLE or
           self.last_mode == PROCESS.SYSTEM_ALARM_IDLE or self.last_mode == PROCESS.GEN_RATE_FAULT_IDLE then
            self.start_fail = START_STATUS.OK

            if (self.mode ~= PROCESS.MATRIX_FAULT_IDLE) and (self.mode ~= PROCESS.SYSTEM_ALARM_IDLE) then
                -- auto clear ASCRAM
                self.ascram = false
                self.ascram_reason = AUTO_SCRAM.NONE
            end

            local gen_multiplier = nil
            local turbine_flow_perf = nil
            self.max_burn_combined = 0.0

            for i = 1, #self.prio_defs do
                table.sort(self.prio_defs[i],
                    ---@param a reactor_unit
                    ---@param b reactor_unit
                    function (a, b) return a.get_control_inf().lim_br100 < b.get_control_inf().lim_br100 end
                )

                for _, u in pairs(self.prio_defs[i]) do
                    local u_mult = u.get_control_inf().generator_mult
                    local u_perf = u.get_control_inf().turbine_flow_perf

                    if gen_multiplier == nil then
                        gen_multiplier = u_mult
                    elseif ((gen_multiplier ~= u_mult) or u.get_control_inf().generator_mismatch) and ((self.mode == PROCESS.CHARGE) or (self.mode == PROCESS.GEN_RATE)) then
                        log.warning("FAC: cannot start CHARGE or GEN_RATE process with inconsistent turbine blade counts")
                        log.info("FAC: all assigned unit's turbine's must have the same number of blades and enough coils to support those blades")
                        next_mode = PROCESS.INACTIVE
                        self.start_fail = START_STATUS.BLADE_MISMATCH
                    end

                    if turbine_flow_perf == nil then
                        turbine_flow_perf = u_perf
                    elseif ((turbine_flow_perf ~= u_perf) or u.get_control_inf().turbine_mismatch) and (self.mode == PROCESS.CHARGE) then
                        log.warning("FAC: cannot start CHARGE process with inconsistent turbine construction")
                        log.info("FAC: all assigned unit's turbine's must have the same steam capacity to maximum flow rate ratio")
                        next_mode = PROCESS.INACTIVE
                        self.start_fail = START_STATUS.BLADE_MISMATCH
                    end

                    if self.start_fail == START_STATUS.OK then u.auto_engage() end

                    self.max_burn_combined = self.max_burn_combined + (u.get_control_inf().lim_br100 / 100.0)
                end
            end

            log.debug(util.c("FAC: computed a max combined burn rate of ", self.max_burn_combined, "mB/t"))

            if gen_multiplier == nil then
                -- no units
                log.warning("FAC: cannot start process control with 0 units assigned")
                next_mode = PROCESS.INACTIVE
                self.start_fail = START_STATUS.NO_UNITS
            else
                self.charge_conversion = util.joules_to_fe_rf(gen_multiplier * (const.mek.JOULES_PER_MB * const.mek.STEAM_ENERGY_EFF / const.mek.WATER_THERMAL_ENTHALPY))

                local p_ratio = const.mek.STANDARD_FE_PER_MB / self.charge_conversion
                self.ref_P_scaler = util.trinary(p_ratio <= 1, p_ratio, 2 ^ ((p_ratio - 1) / 6))

                local d_ratio = (const.mek.REF_TURBINE_CAP / const.mek.REF_TURBINE_FLOW) / turbine_flow_perf
                self.ref_D_scaler = util.trinary(d_ratio <= 1, d_ratio, 2 ^ ((d_ratio - 1) / 20))

                log.debug(util.c("FAC: computed charge conversion factor ", self.charge_conversion, " from generator multiplier ", gen_multiplier,
                    " (using Mekanism constants JOULES_PER_MB = ", const.mek.JOULES_PER_MB, ", STEAM_ENERGY_EFF = ", const.mek.STEAM_ENERGY_EFF,
                    ", WATER_THERMAL_ENTHALPY = ", const.mek.WATER_THERMAL_ENTHALPY, ")"))
                log.debug(util.c("FAC: computed P scaler ", self.ref_P_scaler, " (ratio was ", p_ratio, ") and D scaler ", self.ref_D_scaler, " (ratio was ", d_ratio, ")"))
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
    self.units_ready = nil

    local assign_count = 0
    for i = 1, #self.prio_defs do
        for _, u in pairs(self.prio_defs[i]) do
            assign_count = assign_count + 1

            self.units_ready = (self.units_ready or (self.units_ready == nil)) and u.get_control_inf().ready
        end
    end

    -- nil to false, no units assigned, so auto control is not ready
    self.units_ready = self.units_ready or false

    -- perform mode-specific operations
    if self.mode == PROCESS.INACTIVE then
        if assign_count == 0 then
            self.status_text = { "NOT READY", "no units assigned" }
        elseif not self.units_ready then
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
            if all_units_ramped() or reached_rate(self.sp.burn_target) then
                self.waiting_on_ramp = false

                self.status_text = { "BURN RATE MODE", "running" }
                log.info("FAC: BURN_RATE process mode initial ramp completed")
            end
        end

        local unallocated = allocate_burn_rate(self.sp.burn_target, true)
        self.saturated = self.sp.burn_target == self.max_burn_combined or unallocated > 0
    elseif self.mode == PROCESS.RANGE_CONTROL then
        -- run units at their limits if within the enable range
        if state_changed then
            self.time_start = now
            self.waiting_on_ramp = false
            self.range_control_en = false

            self.status_text = { "CHARGE RANGE MODE", "idle, sufficient charge" }
            log.info("FAC: RANGE_CONTROL process mode started")
        elseif self.range_control_en and (self.imtx_percent >= self.sp.range_stop) then
            self.range_control_en = false
            self.waiting_on_ramp = false

            self.status_text = { "CHARGE RANGE MODE", "stopped, sufficient charge" }
            log.info("FAC: RANGE_CONTROL process mode started")
        elseif (not self.range_control_en) and (self.imtx_percent <= self.sp.range_start) then
            self.range_control_en = true
            self.waiting_on_ramp = true

            self.status_text = { "CHARGE RANGE MODE", "ramping reactors to limit" }
            log.info("FAC: CONTROL process mode ramp completed")
        elseif self.waiting_on_ramp then
            if all_units_ramped() then
                self.waiting_on_ramp = false

                self.status_text = { "CHARGE RANGE MODE", "running reactors at limit" }
                log.info("FAC: CONTROL process mode ramp completed")
            end
        end

        local burn_rate = util.trinary(self.range_control_en, self.max_burn_combined, 0)
        local unallocated = allocate_burn_rate(burn_rate, true)

        self.saturated = burn_rate == self.max_burn_combined or unallocated > 0
    elseif self.mode == PROCESS.CHARGE then
        -- target a level of charge
        if state_changed then
            self.time_start = now
            self.last_time = now
            self.last_error = 0
            self.accumulator = 0
            self.feedforward = 0

            self.charge_control_open = nil

            -- window in seconds * 20 TPS * maximum generation rate per tick
            self.loop_close_limit = self.sp.charge_setpoint - (CHARGE_CLOSE_LOOP_WINDOW_S * 20 * self.max_burn_combined * self.charge_conversion)
            log.debug(util.c("FAC: computed generation capacity of ", self.max_burn_combined * self.charge_conversion, " FE/t"))
            log.debug(util.c("FAC: computed loop close limit of ", self.loop_close_limit, " FE"))

            -- enabling idling on all assigned units
            set_idling(true)

            self.status_text = { "CHARGE LEVEL MODE", "initialized" }
            log.info("FAC: CHARGE mode starting up")
        elseif self.last_update < charge_update then
            local open_loop = false

            if avg_charge <= self.sp.charge_setpoint then
                local force_open_loop = (avg_outflow >= self.max_burn_combined * self.charge_conversion) and (avg_outflow >= avg_inflow)
                open_loop = force_open_loop or (avg_charge < self.loop_close_limit)
            end

            -- convert to kFE to make constants not microscopic
            local error = (self.sp.charge_setpoint - avg_charge) / 1000000

            if open_loop then
                self.status_text = { "CHARGE LEVEL MODE", "running at max burn" }

                if self.charge_control_open ~= true then
                    log.info("FAC: CHARGE mode running open loop")
                end

                allocate_burn_rate(self.max_burn_combined, true)

                self.last_time = now
                self.last_error = error
                self.accumulator = 0
                self.saturated = true
            else
                self.status_text = { "CHARGE LEVEL MODE", "running control loop" }

                if self.charge_control_open ~= false then
                    log.info("FAC: CHARGE mode running closed loop")
                end

                -- stop accumulator when saturated to avoid windup
                if not self.saturated then
                    -- it has no control when negative, so don't allow that
                    self.accumulator = math.max(0, self.accumulator + (error * (now - self.last_time)))
                end

                -- local runtime = now - self.time_start
                local integral = self.accumulator
                local derivative = (error - self.last_error) / (now - self.last_time)

                local P = self.ref_P_scaler * CHARGE_Kp * error
                local I = self.ref_P_scaler * CHARGE_Ki * integral
                local D = self.ref_D_scaler * CHARGE_Kd * derivative

                local FF = avg_outflow / self.charge_conversion

                -- switch from PD to PID control once near target with reduced PD, FF handles external load
                -- zero accumulator when not stabilized
                if math.abs(P) > 1 or math.abs(D) > 1 then
                    self.accumulator = 0
                    I = 0
                else
                    P = P / 1.25
                    D = D / 2
                end

                local output = P + I + D + FF

                -- clamp at range -> output clamped (out_c)
                local out_c = math.max(0, math.min(output, self.max_burn_combined))

                self.feedforward = FF
                self.saturated = output ~= out_c

                -- reset accumulator if FF has taken over completly
                if FF >= self.max_burn_combined then
                    self.accumulator = 0
                end

                if not ExtChargeIdling then
                    -- stop idling early if the output is zero, we are at or above the setpoint, and are not losing charge
                    set_idling(not ((out_c == 0) and (error <= 0) and (avg_outflow <= 0)))
                end

                -- log.debug(util.sprintf("CHARGE[%f] { CHRG[%f] ERR[%f] INT[%f] => OUT[%f] OUT_C[%f] <= P[%f] I[%f] D[%f] FF[%f] <= DISCHG[%f] }",
                --     runtime, avg_charge, error, integral, output, out_c, P, I, D, FF, avg_outflow))

                allocate_burn_rate(out_c, true)

                self.last_time = now
                self.last_error = error
            end

            self.charge_control_open = open_loop
        end

        self.last_update = charge_update
    elseif self.mode == PROCESS.GEN_RATE then
        -- target a rate of generation
        if state_changed then
            -- estimate an initial output (feed-forward)
            local output = self.sp.gen_rate_setpoint / self.charge_conversion

            self.feedforward = output

            local unallocated = allocate_burn_rate(output, true)

            self.saturated = output >= self.max_burn_combined or unallocated > 0
            self.waiting_on_ramp = true

            self.status_text = { "GENERATION MODE", "starting up" }
            log.info(util.c("FAC: GEN_RATE process mode initial ramp started (initial target is ", output, " mB/t)"))
        elseif self.waiting_on_ramp then
            if all_units_ramped() or reached_rate(self.sp.gen_rate_setpoint / self.charge_conversion) then
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
            local error = util.round((self.sp.gen_rate_setpoint - self.turbine_gen_rate) / 1000) / 1000

            -- stop accumulator when saturated to avoid windup
            if not self.saturated then
                self.accumulator = self.accumulator + (error * (now - self.last_time))
            end

            -- local runtime = now - self.time_start
            local integral = self.accumulator
            local derivative = (error - self.last_error) / (now - self.last_time)

            local P = self.ref_P_scaler * RATE_Kp * error
            local I = self.ref_P_scaler * RATE_Ki * integral
            local D = self.ref_D_scaler * RATE_Kd * derivative

            local FF = self.feedforward

            local output = P + I + D + FF

            -- clamp at range -> output clamped (sp_c)
            local out_c = math.max(0, math.min(output, self.max_burn_combined))

            self.saturated = output ~= out_c

            -- log.debug(util.sprintf("GEN_RATE[%f] { RATE[%f] GEN[%f] ERR[%f] INT[%f] => OUT[%f] OUT_C[%f] <= P[%f] I[%f] D[%f] FF[%f] }",
            --     runtime, avg_inflow, self.turbine_gen_rate, error, integral, output, out_c, P, I, D, FF))

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
        local scram = astatus.matrix_fault or astatus.matrix_fill or astatus.crit_alarm or astatus.radiation or astatus.gen_fault

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

-- update facility alarm states
function update.update_alarms()
    -- Facility Radiation
    alarm_ctl.update_alarm_state("FAC", self.alarm_states, self.ascram_status.radiation, self.alarms.FacilityRadiation, true)
end

-- update alarm audio control
function update.alarm_audio()
    local allow_test = self.allow_testing and self.test_tone_set

    local alarms = { false, false, false, false, false, false, false, false, false, false, false, false, false }

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

        -- record facility alarms
        alarms[ALARM.FacilityRadiation] = self.alarm_states[ALARM.FacilityRadiation] == ALARM_STATE.TRIPPED

        -- clear testing alarms if we aren't using them
        if not self.test_tone_reset then
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
    if alarms[ALARM.ContainmentRadiation] or alarms[ALARM.FacilityRadiation] then
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
