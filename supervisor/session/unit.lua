local log   = require("scada-common.log")
local rsio  = require("scada-common.rsio")
local types = require("scada-common.types")
local util  = require("scada-common.util")

local rsctl = require("supervisor.session.rsctl")

---@class reactor_control_unit
local unit = {}

local WASTE_MODE = types.WASTE_MODE

local ALARM = types.ALARM
local PRIO = types.ALARM_PRIORITY
local ALARM_STATE = types.ALARM_STATE

local TRI_FAIL = types.TRI_FAIL
local DUMPING_MODE = types.DUMPING_MODE

local IO = rsio.IO

local FLOW_STABILITY_DELAY_MS = 15000

local DT_KEYS = {
    ReactorTemp  = "RTP",
    ReactorFuel  = "RFL",
    ReactorWaste = "RWS",
    ReactorCCool = "RCC",
    ReactorHCool = "RHC",
    BoilerWater  = "BWR",
    BoilerSteam  = "BST",
    BoilerCCool  = "BCC",
    BoilerHCool  = "BHC",
    TurbineSteam = "TST",
    TurbinePower = "TPR"
}

---@alias ALARM_INT_STATE integer
local AISTATE = {
    INACTIVE = 0,
    TRIPPING = 1,
    TRIPPED = 2,
    ACKED = 3,
    RING_BACK = 4,
    RING_BACK_TRIPPING = 5
}

local aistate_string = {
    "INACTIVE",
    "TRIPPING",
    "TRIPPED",
    "ACKED",
    "RING_BACK",
    "RING_BACK_TRIPPING"
}

-- check if an alarm is active (tripped or ack'd)
---@param alarm table alarm entry
---@return boolean active
local function is_active(alarm)
    return alarm.state == AISTATE.TRIPPED or alarm.state == AISTATE.ACKED
end

---@class alarm_def
---@field state ALARM_INT_STATE internal alarm state
---@field trip_time integer time (ms) when first tripped
---@field hold_time integer time (s) to hold before tripping
---@field id ALARM alarm ID
---@field tier integer alarm urgency tier (0 = highest)

-- create a new reactor unit
---@param for_reactor integer reactor unit number
---@param num_boilers integer number of boilers expected
---@param num_turbines integer number of turbines expected
function unit.new(for_reactor, num_boilers, num_turbines)
    local self = {
        r_id = for_reactor,
        plc_s = nil,    ---@class plc_session_struct
        plc_i = nil,    ---@class plc_session
        turbines = {},
        boilers = {},
        redstone = {},
        -- state tracking
        deltas = {},
        last_heartbeat = 0,
        damage_initial = 0,
        damage_start = 0,
        damage_last = 0,
        damage_est_last = 0,
        waste_mode = WASTE_MODE.AUTO,
        status_text = { "Unknown", "Awaiting Connection..." },
        -- logic for alarms
        had_reactor = false,
        start_ms = 0,
        plc_cache = {
            active = false,
            ok = false,
            rps_trip = false,
            rps_status = {},  ---@type rps_status
            damage = 0,
            temp = 0,
            waste = 0
        },
        ---@class alarm_monitors
        alarms = {
            -- reactor lost under the condition of meltdown imminent
            ContainmentBreach    = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ContainmentBreach, tier = PRIO.CRITICAL },
            -- radiation monitor alarm for this unit
            ContainmentRadiation = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ContainmentRadiation, tier = PRIO.CRITICAL },
            -- reactor offline after being online
            ReactorLost          = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorLost, tier = PRIO.URGENT },
            -- damage >100%
            CriticalDamage       = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.CriticalDamage, tier = PRIO.CRITICAL },
            -- reactor damage increasing
            ReactorDamage        = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorDamage, tier = PRIO.EMERGENCY },
            -- reactor >1200K
            ReactorOverTemp      = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorOverTemp, tier = PRIO.URGENT },
            -- reactor >1100K
            ReactorHighTemp      = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 2, id = ALARM.ReactorHighTemp, tier = PRIO.TIMELY },
            -- waste = 100%
            ReactorWasteLeak     = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorWasteLeak, tier = PRIO.EMERGENCY },
            -- waste >85%
            ReactorHighWaste     = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 2, id = ALARM.ReactorHighWaste, tier = PRIO.TIMELY },
            -- RPS trip occured
            RPSTransient         = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.RPSTransient, tier = PRIO.URGENT },
            -- BoilRateMismatch, CoolantFeedMismatch, SteamFeedMismatch, MaxWaterReturnFeed
            RCSTransient         = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 5, id = ALARM.RCSTransient, tier = PRIO.TIMELY },
            -- "It's just a routine turbin' trip!" -Bill Gibson, "The China Syndrome"
            TurbineTrip          = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.TurbineTrip, tier = PRIO.URGENT }
        },
        ---@class unit_db
        db = {
            ---@class annunciator
            annunciator = {
                -- reactor
                PLCOnline = false,
                PLCHeartbeat = false,   -- alternate true/false to blink, each time there is a keep_alive
                ReactorSCRAM = false,
                ManualReactorSCRAM = false,
                AutoReactorSCRAM = false,
                RCPTrip = false,
                RCSFlowLow = false,
                CoolantLevelLow = false,
                ReactorTempHigh = false,
                ReactorHighDeltaT = false,
                FuelInputRateLow = false,
                WasteLineOcclusion = false,
                HighStartupRate = false,
                -- boiler
                BoilerOnline = {},
                HeatingRateLow = {},
                WaterLevelLow = {},
                BoilRateMismatch = false,
                CoolantFeedMismatch = false,
                -- turbine
                TurbineOnline = {},
                SteamFeedMismatch = false,
                MaxWaterReturnFeed = false,
                SteamDumpOpen = {},
                TurbineOverSpeed = {},
                TurbineTrip = {}
            },
            ---@class alarms
            alarm_states = {
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE
            }
        }
    }

    -- init redstone RTU I/O controller
    local rs_rtu_io_ctl = rsctl.new(self.redstone)

    -- init boiler table fields
    for _ = 1, num_boilers do
        table.insert(self.db.annunciator.BoilerOnline, false)
        table.insert(self.db.annunciator.HeatingRateLow, false)
    end

    -- init turbine table fields
    for _ = 1, num_turbines do
        table.insert(self.db.annunciator.TurbineOnline, false)
        table.insert(self.db.annunciator.SteamDumpOpen, TRI_FAIL.OK)
        table.insert(self.db.annunciator.TurbineOverSpeed, false)
        table.insert(self.db.annunciator.TurbineTrip, false)
    end

    -- PRIVATE FUNCTIONS --

    --#region time derivative utility functions

    -- compute a change with respect to time of the given value
    ---@param key string value key
    ---@param value number value
    ---@param time number timestamp for value
    local function _compute_dt(key, value, time)
        if self.deltas[key] then
            local data = self.deltas[key]

            if time > data.last_t then
                data.dt = (value - data.last_v) / (time - data.last_t)

                data.last_v = value
                data.last_t = time
            end
        else
            self.deltas[key] = {
                last_t = time,
                last_v = value,
                dt = 0.0
            }
        end
    end

    -- clear a delta
    ---@param key string value key
    local function _reset_dt(key) self.deltas[key] = nil end

    -- get the delta t of a value
    ---@param key string value key
    ---@return number
    local function _get_dt(key)
        if self.deltas[key] then return self.deltas[key].dt else return 0.0 end
    end

    --#endregion

    --#region redstone I/O

    local __rs_w = rs_rtu_io_ctl.digital_write
    local __rs_r = rs_rtu_io_ctl.digital_read

    -- waste valves
    local waste_pu  = { open = function () __rs_w(IO.WASTE_PU,   true) end, close = function () __rs_w(IO.WASTE_PU,   false) end }
    local waste_sna = { open = function () __rs_w(IO.WASTE_PO,   true) end, close = function () __rs_w(IO.WASTE_PO,   false) end }
    local waste_po  = { open = function () __rs_w(IO.WASTE_POPL, true) end, close = function () __rs_w(IO.WASTE_POPL, false) end }
    local waste_sps = { open = function () __rs_w(IO.WASTE_AM,   true) end, close = function () __rs_w(IO.WASTE_AM,   false) end }

    --#endregion

    --#region task helpers

    -- update an alarm state given conditions
    ---@param tripped boolean if the alarm condition is still active
    ---@param alarm alarm_def alarm table
    local function _update_alarm_state(tripped, alarm)
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

    -- update all delta computations
    local function _dt__compute_all()
        if self.plc_s ~= nil then
            local plc_db = self.plc_i.get_db()

            local last_update_s = plc_db.last_status_update / 1000.0

            _compute_dt(DT_KEYS.ReactorTemp, plc_db.mek_status.temp, last_update_s)
            _compute_dt(DT_KEYS.ReactorFuel, plc_db.mek_status.fuel, last_update_s)
            _compute_dt(DT_KEYS.ReactorWaste, plc_db.mek_status.waste, last_update_s)
            _compute_dt(DT_KEYS.ReactorCCool, plc_db.mek_status.ccool_amnt, last_update_s)
            _compute_dt(DT_KEYS.ReactorHCool, plc_db.mek_status.hcool_amnt, last_update_s)
        end

        for i = 1, #self.boilers do
            local boiler = self.boilers[i]  ---@type unit_session
            local db = boiler.get_db()      ---@type boilerv_session_db

            local last_update_s = db.tanks.last_update / 1000.0

            _compute_dt(DT_KEYS.BoilerWater .. boiler.get_device_idx(), db.tanks.water.amount, last_update_s)
            _compute_dt(DT_KEYS.BoilerSteam .. boiler.get_device_idx(), db.tanks.steam.amount, last_update_s)
            _compute_dt(DT_KEYS.BoilerCCool .. boiler.get_device_idx(), db.tanks.ccool.amount, last_update_s)
            _compute_dt(DT_KEYS.BoilerHCool .. boiler.get_device_idx(), db.tanks.hcool.amount, last_update_s)
        end

        for i = 1, #self.turbines do
            local turbine = self.turbines[i]    ---@type unit_session
            local db = turbine.get_db()         ---@type turbinev_session_db

            local last_update_s = db.tanks.last_update / 1000.0

            _compute_dt(DT_KEYS.TurbineSteam .. turbine.get_device_idx(), db.tanks.steam.amount, last_update_s)
            ---@todo unused currently?
            _compute_dt(DT_KEYS.TurbinePower .. turbine.get_device_idx(), db.tanks.energy, last_update_s)
        end
    end

    --#endregion

    --#region alarms and annunciator

    -- update the annunciator
    local function _update_annunciator()
        -- update deltas
        _dt__compute_all()

        -- variables for boiler, or reactor if no boilers used
        local total_boil_rate = 0.0

        -------------
        -- REACTOR --
        -------------

        -- check PLC status
        self.db.annunciator.PLCOnline = (self.plc_s ~= nil) and (self.plc_s.open)

        if self.plc_i ~= nil then
            local plc_db = self.plc_i.get_db()

            -- record reactor start time (some alarms are delayed during reactor heatup)
            if self.start_ms == 0 and plc_db.mek_status.status then
                self.start_ms = util.time_ms()
            elseif not plc_db.mek_status.status then
                self.start_ms = 0
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

                total_boil_rate = total_boil_rate + boiler.state.boil_rate
                boiler_steam_dt_sum = _get_dt(DT_KEYS.BoilerSteam .. self.boilers[i].get_device_idx())
                boiler_water_dt_sum = _get_dt(DT_KEYS.BoilerWater .. self.boilers[i].get_device_idx())

                self.db.annunciator.BoilerOnline[session.get_device_idx()] = true
            end

            -- check heating rate low
            if self.plc_s ~= nil and #self.boilers > 0 then
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
        elseif self.plc_s ~= nil then
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

        -- clear turbine online flags
        for i = 1, num_turbines do self.db.annunciator.TurbineOnline[i] = false end

        -- aggregated statistics
        local total_flow_rate = 0
        local total_input_rate = 0
        local max_water_return_rate = 0

        -- go through turbines for stats and online
        for i = 1, #self.turbines do
            local session = self.turbines[i]    ---@type unit_session
            local turbine = session.get_db()    ---@type turbinev_session_db

            total_flow_rate = total_flow_rate + turbine.state.flow_rate
            total_input_rate = total_input_rate + turbine.state.steam_input_rate
            max_water_return_rate = max_water_return_rate + turbine.build.max_water_output

            self.db.annunciator.TurbineOnline[session.get_device_idx()] = true
        end

        -- check for boil rate mismatch (either between reactor and turbine or boiler and turbine)
        self.db.annunciator.BoilRateMismatch = math.abs(total_boil_rate - total_input_rate) > 4

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
    end

    -- evaluate alarm conditions
    local function _update_alarms()
        local annunc = self.db.annunciator
        local plc_cache = self.plc_cache

        -- Containment Breach
        -- lost plc with critical damage (rip plc, you will be missed)
        _update_alarm_state((not plc_cache.ok) and (plc_cache.damage > 99), self.alarms.ContainmentBreach)

        -- Containment Radiation
        ---@todo containment radiation alarm
        _update_alarm_state(false, self.alarms.ContainmentRadiation)

        -- Reactor Lost
        _update_alarm_state(self.had_reactor and self.plc_s == nil, self.alarms.ReactorLost)

        -- Critical Damage
        _update_alarm_state(plc_cache.damage >= 100, self.alarms.CriticalDamage)

        -- Reactor Damage
        _update_alarm_state(plc_cache.damage > 0, self.alarms.ReactorDamage)

        -- Over-Temperature
        _update_alarm_state(plc_cache.temp >= 1200, self.alarms.ReactorOverTemp)

        -- High Temperature
        _update_alarm_state(plc_cache.temp > 1150, self.alarms.ReactorHighTemp)

        -- Waste Leak
        _update_alarm_state(plc_cache.waste >= 0.99, self.alarms.ReactorWasteLeak)

        -- High Waste
        _update_alarm_state(plc_cache.waste > 0.50, self.alarms.ReactorHighWaste)

        -- RPS Transient (excludes timeouts and manual trips)
        local rps_alarm = false
        if plc_cache.rps_status.manual ~= nil then
            if plc_cache.rps_trip then
                for key, val in pairs(plc_cache.rps_status) do
                    if key ~= "manual" and key ~= "timeout" then rps_alarm = rps_alarm or val end
                end
            end
        end

        _update_alarm_state(rps_alarm, self.alarms.RPSTransient)

        -- RCS Transient
        local any_low = annunc.CoolantLevelLow
        local any_over = false
        for i = 1, #annunc.WaterLevelLow do any_low = any_low or annunc.WaterLevelLow[i] end
        for i = 1, #annunc.TurbineOverSpeed do any_over = any_over or annunc.TurbineOverSpeed[i] end

        local rcs_trans = any_low or any_over or annunc.RCPTrip or annunc.RCSFlowLow or annunc.MaxWaterReturnFeed

        -- annunciator indicators for these states may not indicate a real issue when:
        --  > flow is ramping up right after reactor start
        --  > flow is ramping down after reactor shutdown
        if (util.time_ms() - self.start_ms > FLOW_STABILITY_DELAY_MS) and plc_cache.active then
            rcs_trans = rcs_trans or annunc.BoilRateMismatch or annunc.CoolantFeedMismatch or annunc.SteamFeedMismatch
        end

        _update_alarm_state(rcs_trans, self.alarms.RCSTransient)

        -- Turbine Trip
        local any_trip = false
        for i = 1, #annunc.TurbineTrip do any_trip = any_trip or annunc.TurbineTrip[i] end
        _update_alarm_state(any_trip, self.alarms.TurbineTrip)
    end

    --#endregion

    -- unlink disconnected units
    ---@param sessions table
    local function _unlink_disconnected_units(sessions)
        util.filter_table(sessions, function (u) return u.is_connected() end)
    end

    -- PUBLIC FUNCTIONS --

    ---@class reactor_unit
    local public = {}

    -- ADD/LINK DEVICES --

    -- link the PLC
    ---@param plc_session plc_session_struct
    function public.link_plc_session(plc_session)
        self.had_reactor = true
        self.plc_s = plc_session
        self.plc_i = plc_session.instance

        -- reset deltas
        _reset_dt(DT_KEYS.ReactorTemp)
        _reset_dt(DT_KEYS.ReactorFuel)
        _reset_dt(DT_KEYS.ReactorWaste)
        _reset_dt(DT_KEYS.ReactorCCool)
        _reset_dt(DT_KEYS.ReactorHCool)
    end

    -- link a redstone RTU session
    ---@param rs_unit unit_session
    function public.add_redstone(rs_unit)
        table.insert(self.redstone, rs_unit)
    end

    -- link a turbine RTU session
    ---@param turbine unit_session
    function public.add_turbine(turbine)
        if #self.turbines < num_turbines and turbine.get_device_idx() <= num_turbines then
            table.insert(self.turbines, turbine)

            -- reset deltas
            _reset_dt(DT_KEYS.TurbineSteam .. turbine.get_device_idx())
            _reset_dt(DT_KEYS.TurbinePower .. turbine.get_device_idx())

            return true
        else
            return false
        end
    end

    -- link a boiler RTU session
    ---@param boiler unit_session
    function public.add_boiler(boiler)
        if #self.boilers < num_boilers and boiler.get_device_idx() <= num_boilers then
            table.insert(self.boilers, boiler)

            -- reset deltas
            _reset_dt(DT_KEYS.BoilerWater .. boiler.get_device_idx())
            _reset_dt(DT_KEYS.BoilerSteam .. boiler.get_device_idx())
            _reset_dt(DT_KEYS.BoilerCCool .. boiler.get_device_idx())
            _reset_dt(DT_KEYS.BoilerHCool .. boiler.get_device_idx())

            return true
        else
            return false
        end
    end

    -- purge devices associated with the given RTU session ID
    ---@param session integer RTU session ID
    function public.purge_rtu_devices(session)
        util.filter_table(self.turbines, function (s) return s.get_session_id() ~= session end)
        util.filter_table(self.boilers,  function (s) return s.get_session_id() ~= session end)
        util.filter_table(self.redstone, function (s) return s.get_session_id() ~= session end)
    end

    -- UPDATE SESSION --

    -- update (iterate) this unit
    function public.update()
        -- unlink PLC if session was closed
        if self.plc_s ~= nil and not self.plc_s.open then
            self.plc_s = nil
            self.plc_i = nil
        end

        -- unlink RTU unit sessions if they are closed
        _unlink_disconnected_units(self.boilers)
        _unlink_disconnected_units(self.turbines)
        _unlink_disconnected_units(self.redstone)

        -- update annunciator logic
        _update_annunciator()

        -- update alarm status
        _update_alarms()

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
                elseif (util.time_ms() - self.start_ms) <= FLOW_STABILITY_DELAY_MS then
                    if num_turbines > 1 then
                        self.status_text[2] = "turbines spinning up"
                    else
                        self.status_text[2] = "turbine spinning up"
                    end
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

    -- OPERATIONS --

    -- acknowledge all alarms (if possible)
    function public.ack_all()
        for i = 1, #self.db.alarm_states do
            if self.db.alarm_states[i] == ALARM_STATE.TRIPPED then
                self.db.alarm_states[i] = ALARM_STATE.ACKED
            end
        end
    end

    -- acknowledge an alarm (if possible)
    ---@param id ALARM alarm ID
    function public.ack_alarm(id)
        if (type(id) == "number") and (self.db.alarm_states[id] == ALARM_STATE.TRIPPED) then
            self.db.alarm_states[id] = ALARM_STATE.ACKED
        end
    end

    -- reset an alarm (if possible)
    ---@param id ALARM alarm ID
    function public.reset_alarm(id)
        if (type(id) == "number") and (self.db.alarm_states[id] == ALARM_STATE.RING_BACK) then
            self.db.alarm_states[id] = ALARM_STATE.INACTIVE
        end
    end

    -- route reactor waste
    ---@param mode WASTE_MODE waste handling mode
    function public.set_waste(mode)
        if mode == WASTE_MODE.AUTO then
            ---@todo automatic waste routing
            self.waste_mode = mode
        elseif mode == WASTE_MODE.PLUTONIUM then
            -- route through plutonium generation
            self.waste_mode = mode
            waste_pu.open()
            waste_sna.close()
            waste_po.close()
            waste_sps.close()
        elseif mode == WASTE_MODE.POLONIUM then
            -- route through polonium generation into pellets
            self.waste_mode = mode
            waste_pu.close()
            waste_sna.open()
            waste_po.open()
            waste_sps.close()
        elseif mode == WASTE_MODE.ANTI_MATTER then
            -- route through polonium generation into SPS
            self.waste_mode = mode
            waste_pu.close()
            waste_sna.open()
            waste_po.close()
            waste_sps.open()
        else
            log.debug(util.c("invalid waste mode setting ", mode))
        end
    end

    -- READ STATES/PROPERTIES --

    -- get build properties of all machines
    function public.get_build()
        local build = {}

        if self.plc_s ~= nil then
            build.reactor = self.plc_i.get_struct()
        end

        build.boilers = {}
        for i = 1, #self.boilers do
            local boiler = self.boilers[i]  ---@type unit_session
            build.boilers[boiler.get_device_idx()] = { boiler.get_db().formed, boiler.get_db().build }
        end

        build.turbines = {}
        for i = 1, #self.turbines do
            local turbine = self.turbines[i]  ---@type unit_session
            build.turbines[turbine.get_device_idx()] = { turbine.get_db().formed, turbine.get_db().build }
        end

        return build
    end

    -- get reactor status
    function public.get_reactor_status()
        local status = {}

        if self.plc_s ~= nil then
            local reactor = self.plc_i
            status = { reactor.get_status(), reactor.get_rps(), reactor.get_general_status() }
        end

        return status
    end

    -- get RTU statuses
    function public.get_rtu_statuses()
        local status = {}

        -- status of boilers (including tanks)
        status.boilers = {}
        for i = 1, #self.boilers do
            local boiler = self.boilers[i]  ---@type unit_session
            status.boilers[boiler.get_device_idx()] = {
                boiler.is_faulted(),
                boiler.get_db().formed,
                boiler.get_db().state,
                boiler.get_db().tanks
            }
        end

        -- status of turbines (including tanks)
        status.turbines = {}
        for i = 1, #self.turbines do
            local turbine = self.turbines[i]  ---@type unit_session
            status.turbines[turbine.get_device_idx()] = {
                turbine.is_faulted(),
                turbine.get_db().formed,
                turbine.get_db().state,
                turbine.get_db().tanks
            }
        end

        ---@todo other RTU statuses

        return status
    end

    -- get the annunciator status
    function public.get_annunciator() return self.db.annunciator end

    -- get the alarm states
    function public.get_alarms() return self.db.alarm_states end

    -- get unit state (currently only waste mode)
    function public.get_state()
        return { self.status_text[1], self.status_text[2], self.waste_mode }
    end

    -- get the reactor ID
    function public.get_id() return self.r_id end

    return public
end

return unit
