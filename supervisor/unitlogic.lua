local const  = require("scada-common.constants")
local log    = require("scada-common.log")
local rsio   = require("scada-common.rsio")
local types  = require("scada-common.types")
local util   = require("scada-common.util")

local plc    = require("supervisor.session.plc")

local qtypes = require("supervisor.session.rtu.qtypes")

local RPS_TRIP_CAUSE = types.RPS_TRIP_CAUSE
local TRI_FAIL       = types.TRI_FAIL
local CONTAINER_MODE = types.CONTAINER_MODE
local DUMPING_MODE   = types.DUMPING_MODE
local PRIO           = types.ALARM_PRIORITY
local ALARM_STATE    = types.ALARM_STATE

local TBV_RTU_S_DATA = qtypes.TBV_RTU_S_DATA
local DTV_RTU_S_DATA = qtypes.DTV_RTU_S_DATA

local IO = rsio.IO

local PLC_S_CMDS = plc.PLC_S_CMDS

local AISTATE_NAMES = {
    "INACTIVE",
    "TRIPPING",
    "TRIPPED",
    "ACKED",
    "RING_BACK",
    "RING_BACK_TRIPPING"
}

local FLOW_STABILITY_DELAY_MS = const.FLOW_STABILITY_DELAY_MS

local ANNUNC_LIMS = const.ANNUNCIATOR_LIMITS
local ALARM_LIMS = const.ALARM_LIMITS
local RS_THRESH = const.RS_THRESHOLDS

---@class unit_logic_extension
local logic = {}

-- update the annunciator
---@param self _unit_self
function logic.update_annunciator(self)
    local DT_KEYS = self.types.DT_KEYS
    local _get_dt = self._get_dt

    local num_boilers = self.num_boilers
    local num_turbines = self.num_turbines
    local annunc = self.db.annunciator

    annunc.RCSFault = false

    -- variables for boiler, or reactor if no boilers used
    local total_boil_rate = 0.0

    -- auxiliary coolant control
    local need_aux_cool = false
    local dis_aux_cool = true

    --#region Reactor

    annunc.AutoControl = self.auto_engaged

    -- check PLC status
    annunc.PLCOnline = self.plc_i ~= nil

    local plc_ready = annunc.PLCOnline

    if plc_ready then
        local plc_db = self.plc_i.get_db()

        -- update ready state
        --  - must be connected to a formed reactor
        --  - can't have a tripped RPS
        --  - must have received status, struct, and RPS status at least once
        plc_ready = plc_db.formed and (not plc_db.no_reactor) and (not plc_db.rps_tripped) and self.plc_i.check_received_all_data()

        -- update auto control limit
        if (plc_db.mek_struct.max_burn > 0) and ((self.db.control.lim_br100 / 100) > plc_db.mek_struct.max_burn) then
            self.db.control.lim_br100 = math.floor(plc_db.mek_struct.max_burn * 100)
        end

        -- some alarms wait until the burn rate has stabilized, so keep track of that
        if math.abs(_get_dt(DT_KEYS.ReactorBurnR)) > 0 then
            self.last_rate_change_ms = util.time_ms()
            self.turbine_flow_stable = false

            for t = 1, self.num_turbines do
                self.turbine_stability_data[t] = { time_state = 0, time_tanks = 0, rotation = 1, input_rate = 0 }
            end
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
                self.damage_decreasing = false
                self.damage_start = util.time_s()
                self.damage_initial = plc_db.mek_status.damage
            end
        else
            self.damage_decreasing = false
            self.damage_start = 0
            self.damage_initial = 0
            self.damage_last = 0
            self.damage_est_last = 0
        end

        -- heartbeat blink about every second
        if self.last_heartbeat + 1000 < plc_db.last_status_update then
            annunc.PLCHeartbeat = not annunc.PLCHeartbeat
            self.last_heartbeat = plc_db.last_status_update
        end

        local flow_low = ANNUNC_LIMS.RCSFlowLow_H2O
        local high_temp = plc_db.max_op_temp_H2O

        if plc_db.mek_status.ccool_type == types.FLUID.SODIUM then
            flow_low = ANNUNC_LIMS.RCSFlowLow_NA
            high_temp = plc_db.max_op_temp_Na
        end

        self.plc_cache.high_temp_lim = math.min(high_temp + ANNUNC_LIMS.OpTempTolerance, 1200)

        -- update other annunciator fields
        annunc.ReactorSCRAM = plc_db.rps_tripped
        annunc.ManualReactorSCRAM = plc_db.rps_trip_cause == types.RPS_TRIP_CAUSE.MANUAL
        annunc.AutoReactorSCRAM = plc_db.rps_trip_cause == types.RPS_TRIP_CAUSE.AUTOMATIC
        annunc.RCPTrip = plc_db.rps_tripped and (plc_db.rps_status.ex_hcool or plc_db.rps_status.low_cool)
        annunc.RCSFlowLow = _get_dt(DT_KEYS.ReactorCCool) < flow_low
        annunc.CoolantLevelLow = plc_db.mek_status.ccool_fill < ANNUNC_LIMS.CoolantLevelLow
        annunc.ReactorTempHigh = plc_db.mek_status.temp >= self.plc_cache.high_temp_lim
        annunc.ReactorHighDeltaT = _get_dt(DT_KEYS.ReactorTemp) > ANNUNC_LIMS.ReactorHighDeltaT
        annunc.FuelInputRateLow = _get_dt(DT_KEYS.ReactorFuel) < -1.0 or plc_db.mek_status.fuel_fill <= ANNUNC_LIMS.FuelLevelLow
        annunc.WasteLineOcclusion = _get_dt(DT_KEYS.ReactorWaste) > 1.0 or plc_db.mek_status.waste_fill >= ANNUNC_LIMS.WasteLevelHigh

        local heating_rate_conv = util.trinary(plc_db.mek_status.ccool_type == types.FLUID.SODIUM, 200000, 20000)
        local high_rate = plc_db.mek_status.burn_rate >= (plc_db.mek_status.ccool_amnt * 0.27 / heating_rate_conv)
        -- this advisory applies when no coolant is buffered (which we can't easily determine)<br>
        -- it's a rough estimation, see GitHub cc-mek-scada/wiki/High-Rate-Calculation
        annunc.HighStartupRate = not plc_db.mek_status.status and high_rate

        -- if no boilers, use reactor heating rate to check for boil rate mismatch
        if num_boilers == 0 then
            total_boil_rate = plc_db.mek_status.heating_rate

            need_aux_cool = plc_db.mek_status.ccool_fill <= RS_THRESH.AUX_COOL_ENABLE
            dis_aux_cool = plc_db.mek_status.ccool_fill >= RS_THRESH.AUX_COOL_DISABLE
        end
    else
        self.plc_cache.ok = false
    end

    --#endregion

    --#region Misc RTUs

    local max_rad, any_faulted = 0, false

    for i = 1, #self.envd do
        local envd = self.envd[i]
        local db = envd.get_db()
        any_faulted = any_faulted or envd.is_faulted()
        if db.radiation_raw > max_rad then max_rad = db.radiation_raw end
    end

    annunc.RadiationMonitor = util.trinary(#self.envd == 0, 1, util.trinary(any_faulted, 2, 3))
    annunc.RadiationWarning = max_rad >= ANNUNC_LIMS.RadiationWarning

    annunc.EmergencyCoolant = 1

    for i = 1, #self.redstone do
        local io = self.redstone[i].get_db().io[IO.U_EMER_COOL]
        if io ~= nil then
            annunc.EmergencyCoolant = util.trinary(io.read(), 3, 2)
            break
        end
    end

    --#endregion

    --#region Boilers

    local boilers_ready = num_boilers == #self.boilers

    -- clear boiler online flags
    for i = 1, num_boilers do annunc.BoilerOnline[i] = false end

    -- aggregated statistics
    local boiler_steam_dt_sum = 0.0
    local boiler_water_dt_sum = 0.0

    if num_boilers > 0 then
        -- go through boilers for stats and online
        for i = 1, #self.boilers do
            local session = self.boilers[i]
            local boiler = session.get_db()
            local idx = session.get_device_idx()

            annunc.RCSFault = annunc.RCSFault or (not boiler.formed) or session.is_faulted()

            -- update ready state
            --  - must be formed
            --  - must have received build, state, and tanks at least once
            boilers_ready = boilers_ready and boiler.formed and
                            (boiler.build.last_update > 0) and
                            (boiler.state.last_update > 0) and
                            (boiler.tanks.last_update > 0)

            total_boil_rate = total_boil_rate + boiler.state.boil_rate
            boiler_steam_dt_sum = _get_dt(DT_KEYS.BoilerSteam .. idx)
            boiler_water_dt_sum = _get_dt(DT_KEYS.BoilerWater .. idx)

            annunc.BoilerOnline[idx] = true
            annunc.WaterLevelLow[idx] = boiler.tanks.water_fill < ANNUNC_LIMS.WaterLevelLow

            need_aux_cool = need_aux_cool or (boiler.tanks.water_fill <= RS_THRESH.AUX_COOL_ENABLE)
            dis_aux_cool = dis_aux_cool and (boiler.tanks.water_fill >= RS_THRESH.AUX_COOL_DISABLE)
        end

        -- check heating rate low
        if self.plc_i ~= nil and #self.boilers > 0 then
            local r_db = self.plc_i.get_db()

            -- check for inactive boilers while reactor is active
            for i = 1, #self.boilers do
                local boiler = self.boilers[i]
                local idx = boiler.get_device_idx()
                local db = boiler.get_db()

                if r_db.mek_status.status then
                    annunc.HeatingRateLow[idx] = db.state.boil_rate == 0
                else
                    annunc.HeatingRateLow[idx] = false
                end
            end
        end
    else
        boiler_steam_dt_sum = _get_dt(DT_KEYS.ReactorHCool)
        boiler_water_dt_sum = _get_dt(DT_KEYS.ReactorCCool)
    end

    --#endregion

    --#region Coolant Feed Mismatch

    -- check coolant feed mismatch if using boilers, otherwise calculate with reactor
    local cfmismatch = false

    if num_boilers > 0 then
        for i = 1, #self.boilers do
            local boiler = self.boilers[i]
            local idx = boiler.get_device_idx()
            local db = boiler.get_db()

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

    annunc.CoolantFeedMismatch = cfmismatch

    --#endregion

    --#region Turbines

    local turbines_ready = num_turbines == #self.turbines

    -- clear turbine online flags
    for i = 1, num_turbines do annunc.TurbineOnline[i] = false end

    -- aggregated statistics
    local total_flow_rate = 0
    local total_input_rate = 0
    local max_water_return_rate = 0
    local turbines_stable = true

    -- recompute blade count on the chance that it may have changed
    self.db.control.blade_count = 0

    -- go through turbines for stats and online
    for i = 1, #self.turbines do
        local session = self.turbines[i]
        local turbine = session.get_db()
        local idx = session.get_device_idx()

        annunc.RCSFault = annunc.RCSFault or (not turbine.formed) or session.is_faulted()
        annunc.TurbineOnline[idx] = true

        -- update ready state
        -- - must be formed
        -- - must have received build, state, and tanks at least once
        turbines_ready = turbines_ready and turbine.formed and
                        (turbine.build.last_update > 0) and
                        (turbine.state.last_update > 0) and
                        (turbine.tanks.last_update > 0)

        total_flow_rate = total_flow_rate + turbine.state.flow_rate
        total_input_rate = total_input_rate + turbine.state.steam_input_rate
        max_water_return_rate = max_water_return_rate + turbine.build.max_water_output

        self.db.control.blade_count = self.db.control.blade_count + turbine.build.blades

        local last = self.turbine_stability_data[i]

        if not self.turbine_flow_stable then
            local rotation = util.turbine_rotation(turbine)
            local rotation_stable = false

            -- see if data updated, and if so, check rotation speed change
            -- minimal change indicates the turbine is converging on a flow rate
            if last.time_tanks < turbine.tanks.last_update then
                if last.time_tanks > 0 then
                    rotation_stable = math.abs(rotation - last.rotation) < 0.00000003
                end

                last.time_tanks = turbine.tanks.last_update
                last.rotation = rotation
            end

            -- flow is stable if the flow rate is at the input rate or at the max (±1 mB/t)
            local flow_stable = false
            if last.time_state < turbine.state.last_update then
                if (last.time_state > 0) and (turbine.state.flow_rate > 0) then
                    flow_stable = math.abs(turbine.state.flow_rate - math.min(turbine.state.steam_input_rate, turbine.build.max_flow_rate)) < 2
                end

                last.time_state = turbine.state.last_update
            end

            if rotation_stable then
                log.debug(util.c("UNIT ", self.r_id, " turbine ", idx, " reached rotational stability (", rotation, ")"))
            end

            if flow_stable then
                log.debug(util.c("UNIT ", self.r_id, " turbine ", idx, " reached flow stability (", turbine.state.flow_rate, " mB/t)"))
            end

            turbines_stable = turbines_stable and (rotation_stable or flow_stable)
        elseif math.abs(turbine.state.steam_input_rate - last.input_rate) > 1 then
            -- reset to unstable to re-check
            last.time_state = 0
            last.time_tanks = 0
            last.rotation = 1

            turbines_stable = false

            log.debug(util.c("UNIT ", self.r_id, " turbine ", idx, " reset stability (new rate ", turbine.state.steam_input_rate, " != ", last.input_rate," mB/t)"))
        end

        last.input_rate = turbine.state.steam_input_rate
    end

    self.turbine_flow_stable = self.turbine_flow_stable or turbines_stable

    -- check for boil rate mismatch (> 4% error) either between reactor and turbine or boiler and turbine
    annunc.BoilRateMismatch = math.abs(total_boil_rate - total_input_rate) > (0.04 * total_boil_rate)

    -- check for steam feed mismatch and max return rate
    local steam_dt_max = util.trinary(num_boilers == 0, ANNUNC_LIMS.SFM_MaxSteamDT_H20, ANNUNC_LIMS.SFM_MaxSteamDT_NA)
    local water_dt_min = util.trinary(num_boilers == 0, ANNUNC_LIMS.SFM_MinWaterDT_H20, ANNUNC_LIMS.SFM_MinWaterDT_NA)
    local sfmismatch = math.abs(total_flow_rate - total_input_rate) > ANNUNC_LIMS.SteamFeedMismatch
    sfmismatch = sfmismatch or boiler_steam_dt_sum > steam_dt_max or boiler_water_dt_sum < water_dt_min
    annunc.SteamFeedMismatch = sfmismatch
    annunc.MaxWaterReturnFeed = max_water_return_rate == total_flow_rate and total_flow_rate ~= 0

    -- turbine safety checks
    for i = 1, #self.turbines do
        local turbine = self.turbines[i]
        local db = turbine.get_db()
        local idx = turbine.get_device_idx()

        -- check if steam dumps are open
        if db.state.dumping_mode == DUMPING_MODE.IDLE then
            annunc.SteamDumpOpen[idx] = TRI_FAIL.OK
        elseif db.state.dumping_mode == DUMPING_MODE.DUMPING_EXCESS then
            annunc.SteamDumpOpen[idx] = TRI_FAIL.PARTIAL
        else
            annunc.SteamDumpOpen[idx] = TRI_FAIL.FULL
        end

        -- check if turbines are at max speed but not keeping up
        annunc.TurbineOverSpeed[idx] = (db.state.flow_rate == db.build.max_flow_rate) and (_get_dt(DT_KEYS.TurbineSteam .. idx) > 0.0)

        -- see notes at cc-mek-scada/wiki/Annunciator-Panels#Generator-Trip
        annunc.GeneratorTrip[idx] = (_get_dt(DT_KEYS.TurbinePower .. idx) > 0.0) and (db.tanks.energy_fill > 0.05)

        -- see notes at cc-mek-scada/wiki/Annunciator-Panels#Turbine-Trip
        local has_steam = db.state.steam_input_rate > 0 or db.tanks.steam_fill > 0.01
        annunc.TurbineTrip[idx] = has_steam and db.state.flow_rate == 0
    end

    --#endregion

    -- update auto control ready state for this unit
    self.db.control.ready = plc_ready and boilers_ready and turbines_ready

    -- update auxiliary coolant command
    if plc_ready then
        self.enable_aux_cool = self.plc_i.get_db().mek_status.status and
                              (self.enable_aux_cool or need_aux_cool) and not (dis_aux_cool and self.turbine_flow_stable)
    else self.enable_aux_cool = false end
end

-- update an alarm state given conditions
---@param self _unit_self unit instance
---@param tripped boolean if the alarm condition is still active
---@param alarm alarm_def alarm table
---@return boolean new_trip if the alarm just changed to being tripped
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
                log.info(util.c("UNIT ", self.r_id, " ALARM ", alarm.id, " (", types.ALARM_NAMES[alarm.id], "): TRIPPED [PRIORITY ",
                    types.ALARM_PRIORITY_NAMES[alarm.tier],"]"))
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
                log.info(util.c("UNIT ", self.r_id, " ALARM ", alarm.id, " (", types.ALARM_NAMES[alarm.id], "): TRIPPED [PRIORITY ",
                    types.ALARM_PRIORITY_NAMES[alarm.tier],"]"))
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
        local change_str = util.c(AISTATE_NAMES[int_state], " -> ", AISTATE_NAMES[alarm.state])
        log.debug(util.c("UNIT ", self.r_id, " ALARM ", alarm.id, " (", types.ALARM_NAMES[alarm.id], "): ", change_str))
        return alarm.state == AISTATE.TRIPPED
    else return false end
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
    local rad_alarm = false
    for i = 1, #self.envd do
        self.last_radiation = self.envd[i].get_db().radiation_raw
        rad_alarm = self.last_radiation >= ALARM_LIMS.HIGH_RADIATION
        break
    end
    _update_alarm_state(self, rad_alarm, self.alarms.ContainmentRadiation)

    -- Reactor Lost
    _update_alarm_state(self, self.had_reactor and self.plc_i == nil, self.alarms.ReactorLost)

    -- Critical Damage
    _update_alarm_state(self, plc_cache.damage >= 100, self.alarms.CriticalDamage)

    -- Reactor Damage
    local rps_dmg_90 = plc_cache.rps_status.high_dmg and not self.last_rps_trips.high_dmg
    if _update_alarm_state(self, (plc_cache.damage > 0) or rps_dmg_90, self.alarms.ReactorDamage) then
        log.debug(util.c(">> Trip Detail Report for ", types.ALARM_NAMES[self.alarms.ReactorDamage.id]," <<"))
        log.debug(util.c("| plc_cache.damage[", plc_cache.damage, "] rps_dmg_90[", rps_dmg_90, "]"))
    end

    -- Over-Temperature
    local rps_high_temp = plc_cache.rps_status.high_temp and not self.last_rps_trips.high_temp
    if _update_alarm_state(self, (plc_cache.temp >= 1200) or rps_high_temp, self.alarms.ReactorOverTemp) then
        log.debug(util.c(">> Trip Detail Report for ", types.ALARM_NAMES[self.alarms.ReactorOverTemp.id]," <<"))
        log.debug(util.c("| plc_cache.temp[", plc_cache.temp, "] rps_high_temp[", rps_high_temp, "]"))
    end

    -- High Temperature
    local high_temp = math.min(math.max(self.plc_cache.high_temp_lim, 1100), 1199.995)
    _update_alarm_state(self, plc_cache.temp >= high_temp, self.alarms.ReactorHighTemp)

    -- Waste Leak
    _update_alarm_state(self, plc_cache.waste >= 1.0, self.alarms.ReactorWasteLeak)

    -- High Waste
    local rps_high_waste = plc_cache.rps_status.ex_waste and not self.last_rps_trips.ex_waste
    if _update_alarm_state(self, (plc_cache.waste > ALARM_LIMS.HIGH_WASTE) or rps_high_waste, self.alarms.ReactorHighWaste) then
        log.debug(util.c(">> Trip Detail Report for ", types.ALARM_NAMES[self.alarms.ReactorHighWaste.id]," <<"))
        log.debug(util.c("| plc_cache.waste[", plc_cache.waste, "] rps_high_waste[", rps_high_waste, "]"))
    end

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
    local gen_trip = false
    for i = 1, #annunc.WaterLevelLow do any_low = any_low or annunc.WaterLevelLow[i] end
    for i = 1, #annunc.TurbineOverSpeed do any_over = any_over or annunc.TurbineOverSpeed[i] end
    for i = 1, #annunc.GeneratorTrip do gen_trip = gen_trip or annunc.GeneratorTrip[i] end

    local rcs_trans = any_low or any_over or gen_trip or annunc.RCPTrip or annunc.MaxWaterReturnFeed

    if plc_cache.active then
        -- these conditions may not indicate an issue when flow is changing after a burn rate change
        if self.num_boilers == 0 then
            if (util.time_ms() - self.last_rate_change_ms) > FLOW_STABILITY_DELAY_MS then
                rcs_trans = rcs_trans or annunc.BoilRateMismatch
            end

            if self.turbine_flow_stable then
                rcs_trans = rcs_trans or annunc.RCSFlowLow or annunc.CoolantFeedMismatch or annunc.SteamFeedMismatch
            end
        else
            if (util.time_ms() - self.last_rate_change_ms) > FLOW_STABILITY_DELAY_MS then
                rcs_trans = rcs_trans or annunc.RCSFlowLow or annunc.BoilRateMismatch or annunc.CoolantFeedMismatch
            end

            if self.turbine_flow_stable then
                rcs_trans = rcs_trans or annunc.SteamFeedMismatch
            end
        end
    end

    if _update_alarm_state(self, rcs_trans, self.alarms.RCSTransient) then
        log.debug(util.c(">> Trip Detail Report for ", types.ALARM_NAMES[self.alarms.RCSTransient.id]," <<"))
        log.debug(util.c("| any_low[", any_low, "] any_over[", any_over, "] gen_trip[", gen_trip, "]"))
        log.debug(util.c("| RCPTrip[", annunc.RCPTrip, "] MaxWaterReturnFeed[", annunc.MaxWaterReturnFeed, "]"))
        log.debug(util.c("| RCSFlowLow[", annunc.RCSFlowLow, "] BoilRateMismatch[", annunc.BoilRateMismatch,
                    "] CoolantFeedMismatch[", annunc.CoolantFeedMismatch, "] SteamFeedMismatch[", annunc.SteamFeedMismatch, "]"))
    end

    -- Turbine Trip
    local any_trip = false
    for i = 1, #annunc.TurbineTrip do any_trip = any_trip or annunc.TurbineTrip[i] end
    _update_alarm_state(self, any_trip, self.alarms.TurbineTrip)

    -- update last trips table
    for key, val in pairs(plc_cache.rps_status) do self.last_rps_trips[key] = val end
end

-- update the internal automatic safety control performed while in auto control mode
---@param public reactor_unit reactor unit public functions
---@param self _unit_self unit instance
function logic.update_auto_safety(public, self)
    local AISTATE = self.types.AISTATE

    if self.auto_engaged then
        local alarmed = false

        for _, alarm in pairs(self.alarms) do
            if alarm.tier <= PRIO.URGENT and (alarm.state == AISTATE.TRIPPED or alarm.state == AISTATE.ACKED) then
                if not self.auto_was_alarmed then
                    log.info(util.c("UNIT ", self.r_id, " AUTO SCRAM due to ALARM ", alarm.id, " (", types.ALARM_NAMES[alarm.id], ") [PRIORITY ",
                        types.ALARM_PRIORITY_NAMES[alarm.tier],"]"))
                end

                alarmed = true
                break
            end
        end

        if alarmed and not self.plc_cache.rps_status.automatic then
            public.auto_scram()
        end

        self.auto_was_alarmed = alarmed
    else
        self.auto_was_alarmed = false
    end
end

-- update the two unit status text messages
---@param self _unit_self unit instance
function logic.update_status_text(self)
    local AISTATE = self.types.AISTATE
    local annunc = self.db.annunciator

    -- check if an alarm is active (tripped or ack'd)
    ---@nodiscard
    ---@param alarm alarm_def alarm entry
    ---@return boolean active
    local function is_active(alarm)
        return alarm.state == AISTATE.TRIPPED or alarm.state == AISTATE.ACKED
    end

    -- update status text (what the reactor doin?)
    if is_active(self.alarms.ContainmentBreach) then
        -- boom? or was boom disabled
        if self.plc_i ~= nil and self.plc_i.get_rps().force_dis then
            self.status_text = { "REACTOR FORCE DISABLED", "meltdown would have occurred" }
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
        elseif (self.plc_cache.damage < self.damage_last) or ((self.plc_cache.damage - self.damage_initial) < 0) then
            self.damage_decreasing = true
            self.status_text = { "CONTAINMENT TOOK DAMAGE", "damage level lowering..." }

            -- reset damage estimation data in case it goes back up again
            self.damage_initial = self.plc_cache.damage
            self.damage_start = util.time_s()
            self.damage_est_last = 0
        elseif (not self.damage_decreasing) or (self.plc_cache.damage > self.damage_last) then
            self.damage_decreasing = false

            if (self.plc_cache.damage - self.damage_initial) > 0 then
                if self.plc_cache.damage > self.damage_last then
                    local rate = (self.plc_cache.damage - self.damage_initial) / (util.time_s() - self.damage_start)
                    self.damage_est_last = (100 - self.plc_cache.damage) / rate
                end

                self.status_text[2] = util.c("damage critical in ", util.sprintf("%.1f", self.damage_est_last), "s")
            else
                self.status_text[2] = "estimating time to critical..."
            end
        else
            self.status_text = { "CONTAINMENT TOOK DAMAGE", "damage level lowering..." }
        end

        self.damage_last = self.plc_cache.damage
    elseif is_active(self.alarms.ContainmentRadiation) then
        self.status_text[1] = "RADIATION DETECTED"

        if self.last_radiation >= const.EXTREME_RADIATION then
            self.status_text[2] = "extremely high radiation level"
        elseif self.last_radiation >= const.SEVERE_RADIATION then
            self.status_text[2] = "severely high radiation level"
        elseif self.last_radiation >= const.VERY_HIGH_RADIATION then
            self.status_text[2] = "very high level of radiation"
        elseif self.last_radiation >= const.HIGH_RADIATION then
            self.status_text[2] = "high level of radiation"
        elseif self.last_radiation >= const.HAZARD_RADIATION then
            self.status_text[2] = "hazardous level of radiation"
        else
            self.status_text[2] = "elevated level of radiation"
        end
    elseif is_active(self.alarms.ReactorOverTemp) then
        self.status_text = { "CORE OVER TEMP", "reactor core temp damaging" }
    elseif is_active(self.alarms.ReactorWasteLeak) then
        self.status_text = { "WASTE LEAK", "radioactive waste leak detected" }
    elseif is_active(self.alarms.ReactorHighTemp) then
        self.status_text = { "CORE TEMP HIGH", "reactor core temperature high" }
    elseif is_active(self.alarms.ReactorHighWaste) then
        self.status_text = { "WASTE LEVEL HIGH", "waste accumulating in reactor" }
    elseif is_active(self.alarms.TurbineTrip) then
        self.status_text = { "TURBINE TRIP", "turbine stall occurred" }
    elseif is_active(self.alarms.RCSTransient) then
        self.status_text = { "RCS TRANSIENT", "check coolant system" }
    -- elseif is_active(self.alarms.RPSTransient) then
        -- RPS status handled when checking reactor status
    elseif self.em_cool_opened then
        self.status_text = { "EMERGENCY COOLANT OPENED", "reset RPS to close valve" }
    -- connection dependent states
    elseif self.plc_i ~= nil then
        local plc_db = self.plc_i.get_db()
        if plc_db.mek_status.status then
            self.status_text[1] = "ACTIVE"

            if annunc.ReactorHighDeltaT then
                self.status_text[2] = "core temperature rising"
            elseif annunc.ReactorTempHigh then
                self.status_text[2] = "core temp high, system nominal"
            elseif annunc.FuelInputRateLow then
                self.status_text[2] = "insufficient fuel input rate"
            elseif annunc.WasteLineOcclusion then
                self.status_text[2] = "insufficient waste output rate"
            elseif (util.time_ms() - self.last_rate_change_ms) <= FLOW_STABILITY_DELAY_MS then
                self.status_text[2] = "awaiting coolant flow stability"
            elseif not self.turbine_flow_stable then
                self.status_text[2] = "awaiting turbine flow stability"
            else
                self.status_text[2] = "system nominal"
            end
        elseif plc_db.rps_tripped then
            local cause = "unknown"

            if plc_db.rps_trip_cause == RPS_TRIP_CAUSE.OK then
                -- hmm...
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.HIGH_DMG then
                cause = "core damage high"
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.HIGH_TEMP then
                cause = "core temperature high"
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.LOW_COOLANT then
                cause = "insufficient coolant"
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.EX_WASTE then
                cause = "excess waste"
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.EX_HCOOLANT then
                cause = "excess heated coolant"
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.NO_FUEL then
                cause = "insufficient fuel"
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.FAULT then
                cause = "hardware fault"
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.TIMEOUT then
                cause = "connection timed out"
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.MANUAL then
                cause = "manual operator SCRAM"
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.AUTOMATIC then
                cause = "automated system SCRAM"
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.SYS_FAIL then
                cause = "PLC system failure"
            elseif plc_db.rps_trip_cause == RPS_TRIP_CAUSE.FORCE_DISABLED then
                cause = "reactor force disabled"
            end

            self.status_text = { "RPS SCRAM", cause }
        elseif annunc.RadiationWarning then
            -- elevated, non-hazardous level of radiation is low priority, so display it now if everything else was fine
            self.status_text = { "RADIATION DETECTED", "elevated level of radiation" }
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
    elseif annunc.RadiationWarning then
        -- in case PLC was disconnected but radiation is present
        self.status_text = { "RADIATION DETECTED", "elevated level of radiation" }
    else
        self.status_text = { "REACTOR OFF-LINE", "awaiting connection..." }
    end
end

-- handle unit redstone I/O
---@param self _unit_self unit instance
function logic.handle_redstone(self)
    local AISTATE = self.types.AISTATE
    local annunc = self.db.annunciator
    local cache = self.plc_cache
    local rps = cache.rps_status

    -- check if an alarm is active (tripped or ack'd)
    ---@nodiscard
    ---@param alarm alarm_def alarm entry
    ---@return boolean active
    local function is_active(alarm)
        return alarm.state == AISTATE.TRIPPED or alarm.state == AISTATE.ACKED
    end

    -- reactor controls
    if self.plc_s ~= nil then
        if (not rps.manual) and self.io_ctl.digital_read(IO.R_SCRAM) then
            -- reactor SCRAM requested but not yet done; perform it
            self.plc_s.in_queue.push_command(PLC_S_CMDS.SCRAM)
        end

        if cache.rps_trip and self.io_ctl.digital_read(IO.R_RESET) then
            -- reactor RPS reset requested but not yet done; perform it
            self.plc_s.in_queue.push_command(PLC_S_CMDS.RPS_RESET)
        end

        if (not self.auto_engaged) and (not cache.active) and
           (not cache.rps_trip) and self.io_ctl.digital_read(IO.R_ENABLE) then
            -- reactor enable requested and allowable, but not yet done; perform it
            self.plc_s.in_queue.push_command(PLC_S_CMDS.ENABLE)
        end
    end

    -- check for request to ack all alarms
    if self.io_ctl.digital_read(IO.U_ACK) then
        for i = 1, #self.db.alarm_states do
            if self.db.alarm_states[i] == ALARM_STATE.TRIPPED then self.db.alarm_states[i] = ALARM_STATE.ACKED end
        end
    end

    -- write reactor status outputs
    self.io_ctl.digital_write(IO.R_ACTIVE, cache.active)
    self.io_ctl.digital_write(IO.R_AUTO_CTRL, self.auto_engaged)
    self.io_ctl.digital_write(IO.R_SCRAMMED, cache.rps_trip)
    self.io_ctl.digital_write(IO.R_AUTO_SCRAM, rps.automatic)
    self.io_ctl.digital_write(IO.R_HIGH_DMG, rps.high_dmg)
    self.io_ctl.digital_write(IO.R_HIGH_TEMP, rps.high_temp)
    self.io_ctl.digital_write(IO.R_LOW_COOLANT, rps.low_cool)
    self.io_ctl.digital_write(IO.R_EXCESS_HC, rps.ex_hcool)
    self.io_ctl.digital_write(IO.R_EXCESS_WS, rps.ex_waste)
    self.io_ctl.digital_write(IO.R_INSUFF_FUEL, rps.no_fuel)
    self.io_ctl.digital_write(IO.R_PLC_FAULT, rps.fault)
    self.io_ctl.digital_write(IO.R_PLC_TIMEOUT, rps.timeout)

    -- write unit outputs

    local has_alarm = false
    for i = 1, #self.db.alarm_states do
        if self.db.alarm_states[i] == ALARM_STATE.TRIPPED or self.db.alarm_states[i] == ALARM_STATE.ACKED then
            has_alarm = true
            break
        end
    end

    self.io_ctl.digital_write(IO.U_ALARM, has_alarm)

    -----------------------
    -- Emergency Coolant --
    -----------------------

    local boiler_water_low = false
    for i = 1, #annunc.WaterLevelLow do boiler_water_low = boiler_water_low or annunc.WaterLevelLow[i] end

    local enable_emer_cool = rps.low_cool or
        (self.auto_engaged and
        (annunc.CoolantLevelLow or (boiler_water_low and rps.ex_hcool)) and
        is_active(self.alarms.ReactorOverTemp))

    if enable_emer_cool and not self.em_cool_opened then
        log.debug(util.c(">> Emergency Coolant Enable Detail Report (Unit ", self.r_id, ") <<"))
        log.debug(util.c("| CoolantLevelLow[", annunc.CoolantLevelLow, "] CoolantLevelLowLow[", rps.low_cool, "] ExcessHeatedCoolant[", rps.ex_hcool, "]"))
        log.debug(util.c("| ReactorOverTemp[", AISTATE_NAMES[self.alarms.ReactorOverTemp.state], "]"))

        for i = 1, #annunc.WaterLevelLow do
            log.debug(util.c("| WaterLevelLow(", i, ")[", annunc.WaterLevelLow[i], "]"))
        end
    end

    -- don't turn off emergency coolant on sufficient coolant level since it might drop again
    -- turn off once system is OK again
    -- if auto control is engaged, alarm check will SCRAM on reactor over temp so that's covered
    if not cache.rps_trip then
        -- set turbines to not dump steam
        for i = 1, #self.turbines do
            local session = self.turbines[i]
            local turbine = session.get_db()

            if turbine.state.dumping_mode ~= DUMPING_MODE.IDLE then
                session.get_cmd_queue().push_data(TBV_RTU_S_DATA.SET_DUMP_MODE, DUMPING_MODE.IDLE)
            end
        end

        if annunc.EmergencyCoolant > 1 and self.em_cool_opened then
            log.info(util.c("UNIT ", self.r_id, " emergency coolant valve closed"))
            log.info(util.c("UNIT ", self.r_id, " turbines set to not dump steam"))
        end

        self.em_cool_opened = false
    elseif enable_emer_cool or self.em_cool_opened then
        -- set turbines to dump excess steam
        for i = 1, #self.turbines do
            local session = self.turbines[i]
            local turbine = session.get_db()

            if turbine.state.dumping_mode ~= DUMPING_MODE.DUMPING_EXCESS then
                session.get_cmd_queue().push_data(TBV_RTU_S_DATA.SET_DUMP_MODE, DUMPING_MODE.DUMPING_EXCESS)
            end
        end

        -- make sure dynamic tanks are allowing outflow
        for i = 1, #self.tanks do
            local session = self.tanks[i]
            local tank = session.get_db()

            if tank.state.container_mode == CONTAINER_MODE.FILL then
                session.get_cmd_queue().push_data(DTV_RTU_S_DATA.SET_CONT_MODE, CONTAINER_MODE.BOTH)
            end
        end

        if annunc.EmergencyCoolant > 1 and not self.em_cool_opened then
            log.info(util.c("UNIT ", self.r_id, " emergency coolant valve opened"))
            log.info(util.c("UNIT ", self.r_id, " turbines set to dump excess steam"))
        end

        self.em_cool_opened = true
    end

    -- set valve state always
    if self.em_cool_opened then self.valves.emer_cool.open() else self.valves.emer_cool.close() end

    -----------------------
    -- Auxiliary Coolant --
    -----------------------

    if self.aux_coolant then
        if self.enable_aux_cool and (not self.aux_cool_opened) then
            log.info(util.c("UNIT ", self.r_id, " auxiliary coolant valve opened"))
            self.aux_cool_opened = true
        elseif (not self.enable_aux_cool) and self.aux_cool_opened then
            log.info(util.c("UNIT ", self.r_id, " auxiliary coolant valve closed"))
            self.aux_cool_opened = false
        end

        -- set valve state always
        if self.aux_cool_opened then self.valves.aux_cool.open() else self.valves.aux_cool.close() end
    end
end

return logic
