local log   = require("scada-common.log")
local types = require("scada-common.types")
local util  = require("scada-common.util")

local ALARM_STATE = types.ALARM_STATE

local TRI_FAIL = types.TRI_FAIL
local DUMPING_MODE = types.DUMPING_MODE

local aistate_string = {
    "INACTIVE",
    "TRIPPING",
    "TRIPPED",
    "ACKED",
    "RING_BACK",
    "RING_BACK_TRIPPING"
}

---@class unit_logic_extension
local logic = {}

-- update the annunciator
---@param self _unit_self
function logic.update_annunciator(self)
    local DT_KEYS = self.types.DT_KEYS
    local _get_dt = self._get_dt

    local num_boilers = self.num_boilers
    local num_turbines = self.num_turbines

    -- variables for boiler, or reactor if no boilers used
    local total_boil_rate = 0.0

    -------------
    -- REACTOR --
    -------------

    -- check PLC status
    self.db.annunciator.PLCOnline = self.plc_i ~= nil

    local plc_ready = self.db.annunciator.PLCOnline

    if self.db.annunciator.PLCOnline then
        local plc_db = self.plc_i.get_db()

        -- update ready state
        --  - can't be tripped
        --  - must have received status at least once
        --  - must have received struct at least once
        plc_ready = (not plc_db.rps_tripped) and (plc_db.last_status_update > 0) and (plc_db.mek_struct.length > 0)

        -- update auto control limit
        if (self.db.control.lim_br10 == 0) or ((self.db.control.lim_br10 / 10) > plc_db.mek_struct.max_burn) then
            self.db.control.lim_br10 = math.floor(plc_db.mek_struct.max_burn * 10)
        end

        -- some alarms wait until the burn rate has stabilized, so keep track of that
        if math.abs(_get_dt(DT_KEYS.ReactorBurnR)) > 0 then
            self.last_rate_change_ms = util.time_ms()
        end

        -- record reactor stats
        self.plc_cache.active = plc_db.mek_status.status
        self.plc_cache.ok = not (plc_db.rps_status.fault or plc_db.rps_status.sys_fail or plc_db.rps_status.force_dis)
        self.plc_cache.rps_trip = plc_db.rps_tripped
        self.plc_cache.rps_status = plc_db.rps_status
        self.plc_cache.damage = plc_db.mek_status.damage
        self.plc_cache.temp = plc_db.mek_status.temp
        self.plc_cache.waste = plc_db.mek_status.waste_fill

        -- track damage
        if plc_db.mek_status.damage > 0 then
            if self.damage_start == 0 then
                self.damage_start = util.time_s()
                self.damage_initial = plc_db.mek_status.damage
            end
        else
            self.damage_start = 0
            self.damage_initial = 0
            self.damage_last = 0
            self.damage_est_last = 0
        end

        -- heartbeat blink about every second
        if self.last_heartbeat + 1000 < plc_db.last_status_update then
            self.db.annunciator.PLCHeartbeat = not self.db.annunciator.PLCHeartbeat
            self.last_heartbeat = plc_db.last_status_update
        end

        -- update other annunciator fields
        self.db.annunciator.ReactorSCRAM = plc_db.rps_tripped
        self.db.annunciator.ManualReactorSCRAM = plc_db.rps_trip_cause == types.rps_status_t.manual
        self.db.annunciator.AutoReactorSCRAM = plc_db.rps_trip_cause == types.rps_status_t.automatic
        self.db.annunciator.RCPTrip = plc_db.rps_tripped and (plc_db.rps_status.ex_hcool or plc_db.rps_status.no_cool)
        self.db.annunciator.RCSFlowLow = plc_db.mek_status.ccool_fill < 0.75 or plc_db.mek_status.hcool_fill > 0.25
        self.db.annunciator.ReactorTempHigh = plc_db.mek_status.temp > 1000
        self.db.annunciator.ReactorHighDeltaT = _get_dt(DT_KEYS.ReactorTemp) > 100
        self.db.annunciator.FuelInputRateLow = _get_dt(DT_KEYS.ReactorFuel) < -1.0 or plc_db.mek_status.fuel_fill <= 0.01
        self.db.annunciator.WasteLineOcclusion = _get_dt(DT_KEYS.ReactorWaste) > 1.0 or plc_db.mek_status.waste_fill >= 0.85
        ---@todo this is dependent on setup, i.e. how much coolant is buffered and the turbine setup
        self.db.annunciator.HighStartupRate = not plc_db.mek_status.status and plc_db.mek_status.burn_rate > 40

        -- if no boilers, use reactor heating rate to check for boil rate mismatch
        if num_boilers == 0 then
            total_boil_rate = plc_db.mek_status.heating_rate
        end
    else
        self.plc_cache.ok = false
    end

    -------------
    -- BOILERS --
    -------------

    local boilers_ready = num_boilers == #self.boilers

    -- clear boiler online flags
    for i = 1, num_boilers do self.db.annunciator.BoilerOnline[i] = false end

    -- aggregated statistics
    local boiler_steam_dt_sum = 0.0
    local boiler_water_dt_sum = 0.0

    if num_boilers > 0 then
        -- go through boilers for stats and online
        for i = 1, #self.boilers do
            local session = self.boilers[i] ---@type unit_session
            local boiler = session.get_db() ---@type boilerv_session_db

            -- update ready state
            --  - must be formed
            --  - must have received build, state, and tanks at least once
            boilers_ready = boilers_ready and boiler.formed and
                            (boiler.build.last_update > 0) and
                            (boiler.state.last_update > 0) and
                            (boiler.tanks.last_update > 0)

            total_boil_rate = total_boil_rate + boiler.state.boil_rate
            boiler_steam_dt_sum = _get_dt(DT_KEYS.BoilerSteam .. self.boilers[i].get_device_idx())
            boiler_water_dt_sum = _get_dt(DT_KEYS.BoilerWater .. self.boilers[i].get_device_idx())

            self.db.annunciator.BoilerOnline[session.get_device_idx()] = true
        end

        -- check heating rate low
        if self.plc_i ~= nil and #self.boilers > 0 then
            local r_db = self.plc_i.get_db()

            -- check for inactive boilers while reactor is active
            for i = 1, #self.boilers do
                local boiler = self.boilers[i]  ---@type unit_session
                local idx = boiler.get_device_idx()
                local db = boiler.get_db()      ---@type boilerv_session_db

                if r_db.mek_status.status then
                    self.db.annunciator.HeatingRateLow[idx] = db.state.boil_rate == 0
                else
                    self.db.annunciator.HeatingRateLow[idx] = false
                end
            end
        end
    else
        boiler_steam_dt_sum = _get_dt(DT_KEYS.ReactorHCool)
        boiler_water_dt_sum = _get_dt(DT_KEYS.ReactorCCool)
    end

    ---------------------------
    -- COOLANT FEED MISMATCH --
    ---------------------------

    -- check coolant feed mismatch if using boilers, otherwise calculate with reactor
    local cfmismatch = false

    if num_boilers > 0 then
        for i = 1, #self.boilers do
            local boiler = self.boilers[i]      ---@type unit_session
            local idx = boiler.get_device_idx()
            local db = boiler.get_db()          ---@type boilerv_session_db

            local gaining_hc = _get_dt(DT_KEYS.BoilerHCool .. idx) > 10.0 or db.tanks.hcool_fill == 1

            -- gaining heated coolant
            cfmismatch = cfmismatch or gaining_hc
            -- losing cooled coolant
            cfmismatch = cfmismatch or _get_dt(DT_KEYS.BoilerCCool .. idx) < -10.0 or (gaining_hc and db.tanks.ccool_fill == 0)
        end
    elseif self.plc_i ~= nil then
        local r_db = self.plc_i.get_db()

        local gaining_hc = _get_dt(DT_KEYS.ReactorHCool) > 10.0 or r_db.mek_status.hcool_fill == 1

        -- gaining heated coolant (steam)
        cfmismatch = cfmismatch or gaining_hc
        -- losing cooled coolant (water)
        cfmismatch = cfmismatch or _get_dt(DT_KEYS.ReactorCCool) < -10.0 or (gaining_hc and r_db.mek_status.ccool_fill == 0)
    end

    self.db.annunciator.CoolantFeedMismatch = cfmismatch

    --------------
    -- TURBINES --
    --------------

    local turbines_ready = num_turbines == #self.turbines

    -- clear turbine online flags
    for i = 1, num_turbines do self.db.annunciator.TurbineOnline[i] = false end

    -- aggregated statistics
    local total_flow_rate = 0
    local total_input_rate = 0
    local max_water_return_rate = 0

    -- recompute blade count on the chance that it may have changed
    self.db.control.blade_count = 0

    -- go through turbines for stats and online
    for i = 1, #self.turbines do
        local session = self.turbines[i]    ---@type unit_session
        local turbine = session.get_db()    ---@type turbinev_session_db

        -- update ready state
        --  - must be formed
        --  - must have received build, state, and tanks at least once
        turbines_ready = turbines_ready and turbine.formed and
                        (turbine.build.last_update > 0) and
                        (turbine.state.last_update > 0) and
                        (turbine.tanks.last_update > 0)

        total_flow_rate = total_flow_rate + turbine.state.flow_rate
        total_input_rate = total_input_rate + turbine.state.steam_input_rate
        max_water_return_rate = max_water_return_rate + turbine.build.max_water_output
        self.db.control.blade_count = self.db.control.blade_count + turbine.build.blades

        self.db.annunciator.TurbineOnline[session.get_device_idx()] = true
    end

    -- check for boil rate mismatch (> 4% error) either between reactor and turbine or boiler and turbine
    self.db.annunciator.BoilRateMismatch = math.abs(total_boil_rate - total_input_rate) > (0.04 * total_boil_rate)

    -- check for steam feed mismatch and max return rate
    local sfmismatch = math.abs(total_flow_rate - total_input_rate) > 10
    sfmismatch = sfmismatch or boiler_steam_dt_sum > 2.0 or boiler_water_dt_sum < -2.0
    self.db.annunciator.SteamFeedMismatch = sfmismatch
    self.db.annunciator.MaxWaterReturnFeed = max_water_return_rate == total_flow_rate and total_flow_rate ~= 0

    -- check if steam dumps are open
    for i = 1, #self.turbines do
        local turbine = self.turbines[i]    ---@type unit_session
        local db = turbine.get_db()         ---@type turbinev_session_db
        local idx = turbine.get_device_idx()

        if db.state.dumping_mode == DUMPING_MODE.IDLE then
            self.db.annunciator.SteamDumpOpen[idx] = TRI_FAIL.OK
        elseif db.state.dumping_mode == DUMPING_MODE.DUMPING_EXCESS then
            self.db.annunciator.SteamDumpOpen[idx] = TRI_FAIL.PARTIAL
        else
            self.db.annunciator.SteamDumpOpen[idx] = TRI_FAIL.FULL
        end
    end

    -- check if turbines are at max speed but not keeping up
    for i = 1, #self.turbines do
        local turbine = self.turbines[i]    ---@type unit_session
        local db = turbine.get_db()         ---@type turbinev_session_db
        local idx = turbine.get_device_idx()

        self.db.annunciator.TurbineOverSpeed[idx] = (db.state.flow_rate == db.build.max_flow_rate) and (_get_dt(DT_KEYS.TurbineSteam .. idx) > 0.0)
    end

    --[[
        Turbine Trip
        a turbine trip is when the turbine stops, which means we are no longer receiving water and lose the ability to cool.
        this can be identified by these conditions:
        - the current flow rate is 0 mB/t and it should not be
            - can initially catch this by detecting a 0 flow rate with a non-zero input rate, but eventually the steam will fill up
            - can later identified by presence of steam in tank with a 0 flow rate
    ]]--
    for i = 1, #self.turbines do
        local turbine = self.turbines[i]    ---@type unit_session
        local db = turbine.get_db()         ---@type turbinev_session_db

        local has_steam = db.state.steam_input_rate > 0 or db.tanks.steam_fill > 0.01
        self.db.annunciator.TurbineTrip[turbine.get_device_idx()] = has_steam and db.state.flow_rate == 0
    end

    -- update auto control ready state for this unit
    self.db.control.ready = plc_ready and boilers_ready and turbines_ready
end

-- update an alarm state given conditions
---@param self _unit_self unit instance
---@param tripped boolean if the alarm condition is still active
---@param alarm alarm_def alarm table
local function _update_alarm_state(self, tripped, alarm)
    local AISTATE = self.types.AISTATE
    local int_state = alarm.state
    local ext_state = self.db.alarm_states[alarm.id]

    -- alarm inactive
    if int_state == AISTATE.INACTIVE then
        if tripped then
            alarm.trip_time = util.time_ms()
            if alarm.hold_time > 0 then
                alarm.state = AISTATE.TRIPPING
                self.db.alarm_states[alarm.id] = ALARM_STATE.INACTIVE
            else
                alarm.state = AISTATE.TRIPPED
                self.db.alarm_states[alarm.id] = ALARM_STATE.TRIPPED
                log.info(util.c("UNIT ", self.r_id, " ALARM ", alarm.id, " (", types.alarm_string[alarm.id], "): TRIPPED [PRIORITY ",
                    types.alarm_prio_string[alarm.tier + 1],"]"))
            end
        else
            alarm.trip_time = util.time_ms()
            self.db.alarm_states[alarm.id] = ALARM_STATE.INACTIVE
        end
    -- alarm condition met, but not yet for required hold time
    elseif (int_state == AISTATE.TRIPPING) or (int_state == AISTATE.RING_BACK_TRIPPING) then
        if tripped then
            local elapsed = util.time_ms() - alarm.trip_time
            if elapsed > (alarm.hold_time * 1000) then
                alarm.state = AISTATE.TRIPPED
                self.db.alarm_states[alarm.id] = ALARM_STATE.TRIPPED
                log.info(util.c("UNIT ", self.r_id, " ALARM ", alarm.id, " (", types.alarm_string[alarm.id], "): TRIPPED [PRIORITY ",
                    types.alarm_prio_string[alarm.tier + 1],"]"))
            end
        elseif int_state == AISTATE.RING_BACK_TRIPPING then
            alarm.trip_time = 0
            alarm.state = AISTATE.RING_BACK
            self.db.alarm_states[alarm.id] = ALARM_STATE.RING_BACK
        else
            alarm.trip_time = 0
            alarm.state = AISTATE.INACTIVE
            self.db.alarm_states[alarm.id] = ALARM_STATE.INACTIVE
        end
    -- alarm tripped and alarming
    elseif int_state == AISTATE.TRIPPED then
        if tripped then
            if ext_state == ALARM_STATE.ACKED then
                -- was acked by coordinator
                alarm.state = AISTATE.ACKED
            end
        else
            alarm.state = AISTATE.RING_BACK
            self.db.alarm_states[alarm.id] = ALARM_STATE.RING_BACK
        end
    -- alarm acknowledged but still tripped
    elseif int_state == AISTATE.ACKED then
        if not tripped then
            alarm.state = AISTATE.RING_BACK
            self.db.alarm_states[alarm.id] = ALARM_STATE.RING_BACK
        end
    -- alarm no longer tripped, operator must reset to clear
    elseif int_state == AISTATE.RING_BACK then
        if tripped then
            alarm.trip_time = util.time_ms()
            if alarm.hold_time > 0 then
                alarm.state = AISTATE.RING_BACK_TRIPPING
            else
                alarm.state = AISTATE.TRIPPED
                self.db.alarm_states[alarm.id] = ALARM_STATE.TRIPPED
            end
        elseif ext_state == ALARM_STATE.INACTIVE then
            -- was reset by coordinator
            alarm.state = AISTATE.INACTIVE
            alarm.trip_time = 0
        end
    else
        log.error(util.c("invalid alarm state for unit ", self.r_id, " alarm ", alarm.id), true)
    end

    -- check for state change
    if alarm.state ~= int_state then
        local change_str = util.c(aistate_string[int_state + 1], " -> ", aistate_string[alarm.state + 1])
        log.debug(util.c("UNIT ", self.r_id, " ALARM ", alarm.id, " (", types.alarm_string[alarm.id], "): ", change_str))
    end
end

-- evaluate alarm conditions
---@param self _unit_self unit instance
function logic.update_alarms(self)
    local annunc = self.db.annunciator
    local plc_cache = self.plc_cache

    -- Containment Breach
    -- lost plc with critical damage (rip plc, you will be missed)
    _update_alarm_state(self, (not plc_cache.ok) and (plc_cache.damage > 99), self.alarms.ContainmentBreach)

    -- Containment Radiation
    ---@todo containment radiation alarm
    _update_alarm_state(self, false, self.alarms.ContainmentRadiation)

    -- Reactor Lost
    _update_alarm_state(self, self.had_reactor and self.plc_i == nil, self.alarms.ReactorLost)

    -- Critical Damage
    _update_alarm_state(self, plc_cache.damage >= 100, self.alarms.CriticalDamage)

    -- Reactor Damage
    local rps_dmg_90 = plc_cache.rps_status.dmg_crit and not self.last_rps_trips.dmg_crit
    _update_alarm_state(self, (plc_cache.damage > 0) or rps_dmg_90, self.alarms.ReactorDamage)

    -- Over-Temperature
    local rps_high_temp = plc_cache.rps_status.high_temp and not self.last_rps_trips.high_temp
    _update_alarm_state(self, (plc_cache.temp >= 1200) or rps_high_temp, self.alarms.ReactorOverTemp)

    -- High Temperature
    _update_alarm_state(self, plc_cache.temp > 1150, self.alarms.ReactorHighTemp)

    -- Waste Leak
    _update_alarm_state(self, plc_cache.waste >= 0.99, self.alarms.ReactorWasteLeak)

    -- High Waste
    local rps_high_waste = plc_cache.rps_status.ex_waste and not self.last_rps_trips.ex_waste
    _update_alarm_state(self, (plc_cache.waste > 0.50) or rps_high_waste, self.alarms.ReactorHighWaste)

    -- RPS Transient (excludes timeouts and manual trips)
    local rps_alarm = false
    if plc_cache.rps_status.manual ~= nil then
        if plc_cache.rps_trip then
            for key, val in pairs(plc_cache.rps_status) do
                if key ~= "manual" and key ~= "timeout" then rps_alarm = rps_alarm or val end
            end
        end
    end

    _update_alarm_state(self, rps_alarm, self.alarms.RPSTransient)

    -- RCS Transient
    local any_low = annunc.CoolantLevelLow
    local any_over = false
    for i = 1, #annunc.WaterLevelLow do any_low = any_low or annunc.WaterLevelLow[i] end
    for i = 1, #annunc.TurbineOverSpeed do any_over = any_over or annunc.TurbineOverSpeed[i] end

    local rcs_trans = any_low or any_over or annunc.RCPTrip or annunc.RCSFlowLow or annunc.MaxWaterReturnFeed

    -- annunciator indicators for these states may not indicate a real issue when:
    --  > flow is ramping up right after reactor start
    --  > flow is ramping down after reactor shutdown
    if ((util.time_ms() - self.last_rate_change_ms) > self.defs.FLOW_STABILITY_DELAY_MS) and plc_cache.active then
        rcs_trans = rcs_trans or annunc.BoilRateMismatch or annunc.CoolantFeedMismatch or annunc.SteamFeedMismatch
    end

    _update_alarm_state(self, rcs_trans, self.alarms.RCSTransient)

    -- Turbine Trip
    local any_trip = false
    for i = 1, #annunc.TurbineTrip do any_trip = any_trip or annunc.TurbineTrip[i] end
    _update_alarm_state(self, any_trip, self.alarms.TurbineTrip)

    -- update last trips table
    for key, val in pairs(plc_cache.rps_status) do
        self.last_rps_trips[key] = val
    end
end

-- update the two unit status text messages
---@param self _unit_self unit instance
function logic.update_status_text(self)
    local AISTATE = self.types.AISTATE

    -- check if an alarm is active (tripped or ack'd)
    ---@param alarm table alarm entry
    ---@return boolean active
    local function is_active(alarm)
        return alarm.state == AISTATE.TRIPPED or alarm.state == AISTATE.ACKED
    end

    -- update status text (what the reactor doin?)
    if is_active(self.alarms.ContainmentBreach) then
        -- boom? or was boom disabled
        if self.plc_i ~= nil and self.plc_i.get_rps().force_dis then
            self.status_text = { "REACTOR FORCE DISABLED", "meltdown would have occured" }
        else
            self.status_text = { "CORE MELTDOWN", "reactor destroyed" }
        end
    elseif is_active(self.alarms.CriticalDamage) then
        -- so much for it being a "routine turbin' trip"...
        self.status_text = { "MELTDOWN IMMINENT", "evacuate facility immediately" }
    elseif is_active(self.alarms.ReactorDamage) then
        -- attempt to determine when a chance of a meltdown will occur
        self.status_text[1] = "CONTAINMENT TAKING DAMAGE"
        if self.plc_cache.damage >= 100 then
            self.status_text[2] = "damage critical"
        elseif (self.plc_cache.damage - self.damage_initial) > 0 then
            if self.plc_cache.damage > self.damage_last then
                self.damage_last = self.plc_cache.damage
                local rate = (self.plc_cache.damage - self.damage_initial) / (util.time_s() - self.damage_start)
                self.damage_est_last = (100 - self.plc_cache.damage) / rate
            end

            self.status_text[2] = util.c("damage critical in ", util.sprintf("%.1f", self.damage_est_last), "s")
        else
            self.status_text[2] = "estimating time to critical..."
        end
    elseif is_active(self.alarms.ContainmentRadiation) then
        self.status_text = { "RADIATION DETECTED", "radiation levels above normal" }
    -- elseif is_active(self.alarms.RPSTransient) then
        -- RPS status handled when checking reactor status
    elseif is_active(self.alarms.RCSTransient) then
        self.status_text = { "RCS TRANSIENT", "check coolant system" }
    elseif is_active(self.alarms.ReactorOverTemp) then
        self.status_text = { "CORE OVER TEMP", "reactor core temperature >=1200K" }
    elseif is_active(self.alarms.ReactorWasteLeak) then
        self.status_text = { "WASTE LEAK", "radioactive waste leak detected" }
    elseif is_active(self.alarms.ReactorHighTemp) then
        self.status_text = { "CORE TEMP HIGH", "reactor core temperature >1150K" }
    elseif is_active(self.alarms.ReactorHighWaste) then
        self.status_text = { "WASTE LEVEL HIGH", "waste accumulating in reactor" }
    elseif is_active(self.alarms.TurbineTrip) then
        self.status_text = { "TURBINE TRIP", "turbine stall occured" }
    -- connection dependent states
    elseif self.plc_i ~= nil then
        local plc_db = self.plc_i.get_db()
        if plc_db.mek_status.status then
            self.status_text[1] = "ACTIVE"

            if self.db.annunciator.ReactorHighDeltaT then
                self.status_text[2] = "core temperature rising"
            elseif self.db.annunciator.ReactorTempHigh then
                self.status_text[2] = "core temp high, system nominal"
            elseif self.db.annunciator.FuelInputRateLow then
                self.status_text[2] = "insufficient fuel input rate"
            elseif self.db.annunciator.WasteLineOcclusion then
                self.status_text[2] = "insufficient waste output rate"
            elseif (util.time_ms() - self.last_rate_change_ms) <= self.defs.FLOW_STABILITY_DELAY_MS then
                self.status_text[2] = "awaiting flow stability"
            else
                self.status_text[2] = "system nominal"
            end
        elseif plc_db.rps_tripped then
            local cause = "unknown"

            if plc_db.rps_trip_cause == "ok" then
                -- hmm...
            elseif plc_db.rps_trip_cause == "dmg_crit" then
                cause = "core damage critical"
            elseif plc_db.rps_trip_cause == "high_temp" then
                cause = "core temperature high"
            elseif plc_db.rps_trip_cause == "no_coolant" then
                cause = "insufficient coolant"
            elseif plc_db.rps_trip_cause == "full_waste" then
                cause = "excess waste"
            elseif plc_db.rps_trip_cause == "heated_coolant_backup" then
                cause = "excess heated coolant"
            elseif plc_db.rps_trip_cause == "no_fuel" then
                cause = "insufficient fuel"
            elseif plc_db.rps_trip_cause == "fault" then
                cause = "hardware fault"
            elseif plc_db.rps_trip_cause == "timeout" then
                cause = "connection timed out"
            elseif plc_db.rps_trip_cause == "manual" then
                cause = "manual operator SCRAM"
            elseif plc_db.rps_trip_cause == "automatic" then
                cause = "automated system SCRAM"
            elseif plc_db.rps_trip_cause == "sys_fail" then
                cause = "PLC system failure"
            elseif plc_db.rps_trip_cause == "force_disabled" then
                cause = "reactor force disabled"
            end

            self.status_text = { "RPS SCRAM", cause }
        else
            self.status_text[1] = "IDLE"

            local temp = plc_db.mek_status.temp
            if temp < 350 then
                self.status_text[2] = "core cold"
            elseif temp < 600 then
                self.status_text[2] = "core warm"
            else
                self.status_text[2] = "core hot"
            end
        end
    else
        self.status_text = { "Reactor Off-line", "awaiting connection..." }
    end
end

return logic
