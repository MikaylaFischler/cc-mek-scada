local log   = require("scada-common.log")
local rsio  = require("scada-common.rsio")
local types = require("scada-common.types")
local util  = require("scada-common.util")

local logic = require("supervisor.session.unitlogic")
local plc   = require("supervisor.session.plc")
local rsctl = require("supervisor.session.rsctl")

---@class reactor_control_unit
local unit = {}

local WASTE_MODE = types.WASTE_MODE

local ALARM = types.ALARM
local PRIO = types.ALARM_PRIORITY
local ALARM_STATE = types.ALARM_STATE

local TRI_FAIL = types.TRI_FAIL
local DUMPING_MODE = types.DUMPING_MODE

local PLC_S_CMDS = plc.PLC_S_CMDS

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
    ---@class _unit_self
    local self = {
        r_id = for_reactor,
        plc_s = nil,    ---@class plc_session_struct
        plc_i = nil,    ---@class plc_session
        num_boilers = num_boilers,
        num_turbines = num_turbines,
        types = { DT_KEYS = DT_KEYS, AISTATE = AISTATE },
        defs = { FLOW_STABILITY_DELAY_MS = FLOW_STABILITY_DELAY_MS },
        turbines = {},
        boilers = {},
        redstone = {},
        -- auto control
        ramp_target_br10 = 0,
        -- state tracking
        deltas = {},
        last_heartbeat = 0,
        damage_initial = 0,
        damage_start = 0,
        damage_last = 0,
        damage_est_last = 0,
        waste_mode = WASTE_MODE.AUTO,
        status_text = { "UNKNOWN", "awaiting connection..." },
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
                AutoControl = false,
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
            },
            -- fields for facility control
            ---@class unit_control
            control = {
                ready = false,
                degraded = false,
                blade_count = 0,
                br10 = 0,
                lim_br10 = 0
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
    function self._get_dt(key)
        if self.deltas[key] then return self.deltas[key].dt else return 0.0 end
    end

    -- update all delta computations
    local function _dt__compute_all()
        if self.plc_i ~= nil then
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

    --#region redstone I/O

    local __rs_w = rs_rtu_io_ctl.digital_write
    local __rs_r = rs_rtu_io_ctl.digital_read

    -- waste valves
    local waste_pu  = { open = function () __rs_w(IO.WASTE_PU,   true) end, close = function () __rs_w(IO.WASTE_PU,   false) end }
    local waste_sna = { open = function () __rs_w(IO.WASTE_PO,   true) end, close = function () __rs_w(IO.WASTE_PO,   false) end }
    local waste_po  = { open = function () __rs_w(IO.WASTE_POPL, true) end, close = function () __rs_w(IO.WASTE_POPL, false) end }
    local waste_sps = { open = function () __rs_w(IO.WASTE_AM,   true) end, close = function () __rs_w(IO.WASTE_AM,   false) end }

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
    --#region

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

        -- send or re-send waste settings
        public.set_waste(self.waste_mode)
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

    --#endregion

    -- AUTO CONTROL --
    --#region

    -- engage automatic control
    function public.a_engage()
        self.db.annunciator.AutoControl = true
        if self.plc_i ~= nil then
            self.plc_i.auto_lock(true)
        end
    end

    -- disengage automatic control
    function public.a_disengage()
        self.db.annunciator.AutoControl = false
        if self.plc_i ~= nil then
            self.plc_i.auto_lock(false)
            self.db.control.br10 = 0
        end
    end

    -- set the automatic burn rate based on the last set br10
    ---@param ramp boolean true to ramp to rate, false to set right away
    function public.a_commit_br10(ramp)
        if self.db.annunciator.AutoControl then
            if self.plc_i ~= nil then
                self.plc_i.auto_set_burn(self.db.control.br10 / 10, ramp)

                if ramp then self.ramp_target_br10 = self.db.control.br10 end
            end
        end
    end

    -- check if ramping is complete (burn rate is same as target)
    ---@return boolean complete
    function public.a_ramp_complete()
        if self.plc_i ~= nil then
            local cur_rate = math.floor(self.plc_i.get_db().mek_status.burn_rate * 10)
            return (cur_rate == self.ramp_target_br10) or (self.ramp_target_br10 == 0)
        else return true end
    end

    -- perform an automatic SCRAM
    function public.a_scram()
        if self.plc_s ~= nil then
            self.plc_s.in_queue.push_command(PLC_S_CMDS.ASCRAM)
        end
    end

    --#endregion

    -- UPDATE SESSION --

    -- update (iterate) this unit
    function public.update()
        -- unlink PLC if session was closed
        if self.plc_s ~= nil and not self.plc_s.open then
            self.plc_s = nil
            self.plc_i = nil
            self.db.control.br10 = 0
            self.db.control.lim_br10 = 0
        end

        -- unlink RTU unit sessions if they are closed
        _unlink_disconnected_units(self.boilers)
        _unlink_disconnected_units(self.turbines)
        _unlink_disconnected_units(self.redstone)

        -- update degraded state for auto control
        self.db.control.degraded = (#self.boilers ~= num_boilers) or (#self.turbines ~= num_turbines) or (self.plc_i == nil)

        -- update deltas
        _dt__compute_all()

        -- update annunciator logic
        logic.update_annunciator(self)

        -- update alarm status
        logic.update_alarms(self)

        -- update status text
        logic.update_status_text(self)
    end

    -- OPERATIONS --

    -- queue a command to SCRAM the reactor
    function public.scram()
        if self.plc_s ~= nil then
            self.plc_s.in_queue.push_command(PLC_S_CMDS.SCRAM)
        end
    end

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

    -- set the automatic control max burn rate for this unit
    ---@param limit number burn rate limit for auto control
    function public.set_burn_limit(limit)
        if limit > 0 then
            self.db.control.lim_br10 = math.floor(limit * 10)

            if self.plc_i ~= nil then
                if limit > self.plc_i.get_struct().max_burn then
                    self.db.control.lim_br10 = math.floor(self.plc_i.get_struct().max_burn * 10)
                end
            end
        end
    end

    -- READ STATES/PROPERTIES --

    -- get build properties of all machines
    function public.get_build()
        local build = {}

        if self.plc_i ~= nil then
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
        if self.plc_i ~= nil then
            status = { self.plc_i.get_status(), self.plc_i.get_rps(), self.plc_i.get_general_status() }
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

    -- get information required for automatic reactor control
    function public.get_control_inf() return self.db.control end

    -- get unit state
    function public.get_state()
        return { self.status_text[1], self.status_text[2], self.waste_mode, self.db.control.ready, self.db.control.degraded }
    end

    -- get the reactor ID
    function public.get_id() return self.r_id end

    return public
end

return unit
