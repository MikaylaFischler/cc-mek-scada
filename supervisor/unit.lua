local log        = require("scada-common.log")
local rsio       = require("scada-common.rsio")
local types      = require("scada-common.types")
local util       = require("scada-common.util")

local logic      = require("supervisor.unitlogic")

local plc        = require("supervisor.session.plc")
local rsctl      = require("supervisor.session.rsctl")
local svsessions = require("supervisor.session.svsessions")

local WASTE_MODE    = types.WASTE_MODE
local WASTE         = types.WASTE_PRODUCT
local ALARM         = types.ALARM
local PRIO          = types.ALARM_PRIORITY
local ALARM_STATE   = types.ALARM_STATE
local TRI_FAIL      = types.TRI_FAIL
local RTU_ID_FAIL   = types.RTU_ID_FAIL
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE

local PLC_S_CMDS = plc.PLC_S_CMDS

local IO = rsio.IO

local DT_KEYS = {
    ReactorBurnR = "RBR",
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

---@enum ALARM_INT_STATE
local AISTATE = {
    INACTIVE = 1,
    TRIPPING = 2,
    TRIPPED = 3,
    ACKED = 4,
    RING_BACK = 5,
    RING_BACK_TRIPPING = 6
}

---@class alarm_def
---@field state ALARM_INT_STATE internal alarm state
---@field trip_time integer time (ms) when first tripped
---@field hold_time integer time (s) to hold before tripping
---@field id ALARM alarm ID
---@field tier integer alarm urgency tier (0 = highest)

-- burn rate to idle at
local IDLE_RATE = 0.01

---@class reactor_control_unit
local unit = {}

-- create a new reactor unit
---@nodiscard
---@param reactor_id integer reactor unit number
---@param num_boilers integer number of boilers expected
---@param num_turbines integer number of turbines expected
---@param ext_idle boolean extended idling mode
---@param aux_coolant boolean if this unit has auxiliary coolant
function unit.new(reactor_id, num_boilers, num_turbines, ext_idle, aux_coolant)
    -- time (ms) to idle for auto idling
    local IDLE_TIME = util.trinary(ext_idle, 60000, 10000)

    local log_tag = "UNIT " .. reactor_id .. ": "

    ---@class _unit_self
    local self = {
        r_id = reactor_id,
        plc_s = nil,    ---@type plc_session_struct
        plc_i = nil,    ---@type plc_session
        num_boilers = num_boilers,
        num_turbines = num_turbines,
        aux_coolant = aux_coolant,
        types = { DT_KEYS = DT_KEYS, AISTATE = AISTATE },
        -- rtus
        rtu_list = {},  ---@type unit_session[][]
        redstone = {},  ---@type redstone_session[]
        boilers = {},   ---@type boilerv_session[]
        turbines = {},  ---@type turbinev_session[]
        tanks = {},     ---@type dynamicv_session[]
        snas = {},      ---@type sna_session[]
        envd = {},      ---@type envd_session[]
        -- redstone control
        io_ctl = nil,   ---@type rs_controller
---@diagnostic disable-next-line: missing-fields
        valves = {},    ---@type unit_valves
        em_cool_opened = false,
        aux_cool_opened = false,
        -- auto control
        auto_engaged = false,
        auto_idle = false,
        auto_idling = false,
        auto_idle_start = 0,
        auto_was_alarmed = false,
        ramp_target_br100 = 0,
        -- state tracking
        deltas = {},    ---@type { last_t: number, last_v: number, dt: number }[]
        last_heartbeat = 0,
        last_radiation = 0,
        damage_decreasing = false,
        damage_initial = 0,
        damage_start = 0,
        damage_last = 0,
        damage_est_last = 0,
        waste_product = WASTE.PLUTONIUM, ---@type WASTE_PRODUCT
        status_text = { "UNKNOWN", "awaiting connection..." },
        enable_aux_cool = false,
        -- logic for alarms
        had_reactor = false,
        turbine_flow_stable = false,
        turbine_stability_data = {}, ---@type { time_state: integer, time_tanks: integer, rotation: number, input_rate: integer }[]
        last_rate_change_ms = 0,
        ---@type rps_status
        last_rps_trips = {
            high_dmg = false,
            high_temp = false,
            low_cool = false,
            ex_waste = false,
            ex_hcool = false,
            no_fuel = false,
            fault = false,
            timeout = false,
            manual = false,
            automatic = false,
            sys_fail = false,
            force_dis = false
        },
        plc_cache = {
            active = false,
            ok = false,
            rps_trip = false,
            ---@type rps_status
            rps_status = {
                high_dmg = false,
                high_temp = false,
                low_cool = false,
                ex_waste = false,
                ex_hcool = false,
                no_fuel = false,
                fault = false,
                timeout = false,
                manual = false,
                automatic = false,
                sys_fail = false,
                force_dis = false
            },
            damage = 0,
            temp = 0,
            waste = 0,
            high_temp_lim = 1150
        },
        ---@type { [string]: alarm_def }
        alarms = {
            -- reactor lost under the condition of meltdown imminent
            ContainmentBreach    = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ContainmentBreach, tier = PRIO.CRITICAL },
            -- radiation monitor alarm for this unit
            ContainmentRadiation = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ContainmentRadiation, tier = PRIO.CRITICAL },
            -- reactor offline after being online
            ReactorLost          = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorLost, tier = PRIO.TIMELY },
            -- damage >100%
            CriticalDamage       = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.CriticalDamage, tier = PRIO.CRITICAL },
            -- reactor damage increasing
            ReactorDamage        = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorDamage, tier = PRIO.EMERGENCY },
            -- reactor >1200K
            ReactorOverTemp      = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorOverTemp, tier = PRIO.URGENT },
            -- reactor >= computed high temp limit
            ReactorHighTemp      = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 1, id = ALARM.ReactorHighTemp, tier = PRIO.TIMELY },
            -- waste = 100%
            ReactorWasteLeak     = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 0, id = ALARM.ReactorWasteLeak, tier = PRIO.EMERGENCY },
            -- waste >85%
            ReactorHighWaste     = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 2, id = ALARM.ReactorHighWaste, tier = PRIO.URGENT },
            -- RPS trip occured
            RPSTransient         = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 2, id = ALARM.RPSTransient, tier = PRIO.TIMELY },
            -- CoolantLevelLow, WaterLevelLow, TurbineOverSpeed, MaxWaterReturnFeed, RCPTrip, RCSFlowLow, BoilRateMismatch, CoolantFeedMismatch,
            -- SteamFeedMismatch, MaxWaterReturnFeed, RCS hardware fault
            RCSTransient         = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 5, id = ALARM.RCSTransient, tier = PRIO.TIMELY },
            -- "It's just a routine turbin' trip!" -Bill Gibson, "The China Syndrome"
            TurbineTrip          = { state = AISTATE.INACTIVE, trip_time = 0, hold_time = 2, id = ALARM.TurbineTrip, tier = PRIO.URGENT }
        },
        ---@class unit_db
        db = {
            ---@class annunciator
            annunciator = {
                -- reactor
                PLCOnline = false,
                PLCHeartbeat = false,   -- alternate true/false to blink, each time there is a keep_alive
                RadiationMonitor = 1,
                AutoControl = false,
                ReactorSCRAM = false,
                ManualReactorSCRAM = false,
                AutoReactorSCRAM = false,
                RadiationWarning = false,
                RCPTrip = false,
                RCSFlowLow = false,
                CoolantLevelLow = false,
                ReactorTempHigh = false,
                ReactorHighDeltaT = false,
                FuelInputRateLow = false,
                WasteLineOcclusion = false,
                HighStartupRate = false,
                -- cooling
                RCSFault = false,
                EmergencyCoolant = 1,
                CoolantFeedMismatch = false,
                BoilRateMismatch = false,
                SteamFeedMismatch = false,
                MaxWaterReturnFeed = false,
                -- boilers
                BoilerOnline = {},     ---@type boolean[]
                HeatingRateLow = {},   ---@type boolean[]
                WaterLevelLow = {},    ---@type boolean[]
                -- turbines
                TurbineOnline = {},    ---@type boolean[]
                SteamDumpOpen = {},    ---@type integer[]
                TurbineOverSpeed = {}, ---@type boolean[]
                GeneratorTrip = {},    ---@type boolean[]
                TurbineTrip = {}       ---@type boolean[]
            },
            ---@type { [ALARM]: ALARM_STATE }
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
                br100 = 0,
                lim_br100 = 0,
                waste_mode = WASTE_MODE.AUTO ---@type WASTE_MODE
            }
        }
    }

    -- list for RTU session management
    self.rtu_list = { self.redstone, self.boilers, self.turbines, self.tanks, self.snas, self.envd }

    -- init redstone RTU I/O controller
    self.io_ctl = rsctl.new(self.redstone)

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
        table.insert(self.db.annunciator.GeneratorTrip, false)
        table.insert(self.db.annunciator.TurbineTrip, false)
        table.insert(self.turbine_stability_data, { time_state = 0, time_tanks = 0, rotation = 1, input_rate = 0 })
    end

    -- PRIVATE FUNCTIONS --

    --#region Time Derivative Utility Functions

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
    ---@nodiscard
    ---@param key string value key
    ---@return number value value or 0 if not known
    function self._get_dt(key) if self.deltas[key] then return self.deltas[key].dt else return 0.0 end end

    -- update all delta computations
    local function _dt__compute_all()
        if self.plc_i ~= nil then
            local plc_db = self.plc_i.get_db()

            local last_update_s = plc_db.last_status_update / 1000.0

            _compute_dt(DT_KEYS.ReactorBurnR, plc_db.mek_status.act_burn_rate, last_update_s)
            _compute_dt(DT_KEYS.ReactorTemp, plc_db.mek_status.temp, last_update_s)
            _compute_dt(DT_KEYS.ReactorFuel, plc_db.mek_status.fuel, last_update_s)
            _compute_dt(DT_KEYS.ReactorWaste, plc_db.mek_status.waste, last_update_s)
            _compute_dt(DT_KEYS.ReactorCCool, plc_db.mek_status.ccool_amnt, last_update_s)
            _compute_dt(DT_KEYS.ReactorHCool, plc_db.mek_status.hcool_amnt, last_update_s)
        end

        for i = 1, #self.boilers do
            local boiler = self.boilers[i]
            local db = boiler.get_db()

            local last_update_s = db.tanks.last_update / 1000.0

            _compute_dt(DT_KEYS.BoilerWater .. boiler.get_device_idx(), db.tanks.water.amount, last_update_s)
            _compute_dt(DT_KEYS.BoilerSteam .. boiler.get_device_idx(), db.tanks.steam.amount, last_update_s)
            _compute_dt(DT_KEYS.BoilerCCool .. boiler.get_device_idx(), db.tanks.ccool.amount, last_update_s)
            _compute_dt(DT_KEYS.BoilerHCool .. boiler.get_device_idx(), db.tanks.hcool.amount, last_update_s)
        end

        for i = 1, #self.turbines do
            local turbine = self.turbines[i]
            local db = turbine.get_db()

            local last_update_s = db.tanks.last_update / 1000.0

            _compute_dt(DT_KEYS.TurbineSteam .. turbine.get_device_idx(), db.tanks.steam.amount, last_update_s)
            _compute_dt(DT_KEYS.TurbinePower .. turbine.get_device_idx(), db.tanks.energy, last_update_s)
        end
    end

    --#endregion

    --#region Redstone I/O

    -- create a generic valve interface
    ---@nodiscard
    ---@param port IO_PORT
    local function _make_valve_iface(port)
        ---@class unit_valve_iface
        local iface = {
            open = function () self.io_ctl.digital_write(port, true) end,
            close = function () self.io_ctl.digital_write(port, false) end,
            -- check valve state
            ---@nodiscard
            ---@return 0|1|2 0 for not connected, 1 for inactive, 2 for active
            check = function () return util.trinary(self.io_ctl.is_connected(port), util.trinary(self.io_ctl.digital_read(port), 2, 1), 0) end
        }
        return iface
    end

    -- valves
    local waste_pu  = _make_valve_iface(IO.WASTE_PU)
    local waste_sna = _make_valve_iface(IO.WASTE_PO)
    local waste_po  = _make_valve_iface(IO.WASTE_POPL)
    local waste_sps = _make_valve_iface(IO.WASTE_AM)
    local emer_cool = _make_valve_iface(IO.U_EMER_COOL)
    local aux_cool  = _make_valve_iface(IO.U_AUX_COOL)

    ---@class unit_valves
    self.valves = {
        waste_pu = waste_pu,
        waste_sna = waste_sna,
        waste_po = waste_po,
        waste_sps = waste_sps,
        emer_cool = emer_cool,
        aux_cool = aux_cool
    }

    -- route reactor waste for a given waste product
    ---@param product WASTE_PRODUCT waste product to route valves for
    local function _set_waste_valves(product)
        self.waste_product = product

        if product == WASTE.PLUTONIUM then
            -- route through plutonium generation
            waste_pu.open()
            waste_sna.close()
            waste_po.close()
            waste_sps.close()
        elseif product == WASTE.POLONIUM then
            -- route through polonium generation into pellets
            waste_pu.close()
            waste_sna.open()
            waste_po.open()
            waste_sps.close()
        elseif product == WASTE.ANTI_MATTER then
            -- route through polonium generation into SPS
            waste_pu.close()
            waste_sna.open()
            waste_po.close()
            waste_sps.open()
        end
    end

    --#endregion

    -- PUBLIC FUNCTIONS --

    ---@class reactor_unit
    local public = {}

    --#region Add/Link Devices

    -- link the PLC
    ---@param plc_session plc_session_struct
    function public.link_plc_session(plc_session)
        self.had_reactor = true
        self.plc_s = plc_session
        self.plc_i = plc_session.instance

        log.debug(util.c(log_tag, "linked PLC [", plc_session.s_addr, ":", plc_session.r_chan, "]"))

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
        log.debug(util.c(log_tag, "linked redstone [", rs_unit.get_unit_id(), "@", rs_unit.get_session_id(), "]"))

        -- send or re-send waste settings
        _set_waste_valves(self.waste_product)
    end

    -- link a turbine RTU session
    ---@param turbine unit_session
    ---@return boolean linked turbine accepted to associated device slot
    function public.add_turbine(turbine)
        local fail_code, fail_str = svsessions.check_rtu_id(turbine, self.turbines, num_turbines)
        local ok = fail_code == RTU_ID_FAIL.OK

        if ok then
            table.insert(self.turbines, turbine)
            log.debug(util.c(log_tag, "linked turbine #", turbine.get_device_idx(), " [", turbine.get_unit_id(), "@", turbine.get_session_id(), "]"))

            -- reset deltas
            _reset_dt(DT_KEYS.TurbineSteam .. turbine.get_device_idx())
            _reset_dt(DT_KEYS.TurbinePower .. turbine.get_device_idx())
        else
            log.warning(util.c(log_tag, "rejected turbine linking due to failure code ", fail_code, " (", fail_str, ")"))
        end

        return ok
    end

    -- link a boiler RTU session
    ---@param boiler unit_session
    ---@return boolean linked boiler accepted to associated device slot
    function public.add_boiler(boiler)
        local fail_code, fail_str = svsessions.check_rtu_id(boiler, self.boilers, num_boilers)
        local ok = fail_code == RTU_ID_FAIL.OK

        if ok then
            table.insert(self.boilers, boiler)
            log.debug(util.c(log_tag, "linked boiler #", boiler.get_device_idx(), " [", boiler.get_unit_id(), "@", boiler.get_session_id(), "]"))

            -- reset deltas
            _reset_dt(DT_KEYS.BoilerWater .. boiler.get_device_idx())
            _reset_dt(DT_KEYS.BoilerSteam .. boiler.get_device_idx())
            _reset_dt(DT_KEYS.BoilerCCool .. boiler.get_device_idx())
            _reset_dt(DT_KEYS.BoilerHCool .. boiler.get_device_idx())
        else
            log.warning(util.c(log_tag, "rejected boiler linking due to failure code ", fail_code, " (", fail_str, ")"))
        end

        return ok
    end

    -- link a dynamic tank RTU session
    ---@param dynamic_tank unit_session
    ---@return boolean linked dynamic tank accepted (max 1)
    function public.add_tank(dynamic_tank)
        local fail_code, fail_str = svsessions.check_rtu_id(dynamic_tank, self.tanks, 1)
        local ok = fail_code == RTU_ID_FAIL.OK

        if ok then
            table.insert(self.tanks, dynamic_tank)
            log.debug(util.c(log_tag, "linked dynamic tank [", dynamic_tank.get_unit_id(), "@", dynamic_tank.get_session_id(), "]"))
        else
            log.warning(util.c(log_tag, "rejected dynamic tank linking due to failure code ", fail_code, " (", fail_str, ")"))
        end

        return ok
    end

    -- link a solar neutron activator RTU session
    ---@param sna unit_session
    function public.add_sna(sna) table.insert(self.snas, sna) end

    -- link an environment detector RTU session
    ---@param envd unit_session
    ---@return boolean linked environment detector accepted
    function public.add_envd(envd)
        local fail_code, fail_str = svsessions.check_rtu_id(envd, self.envd, 99)
        local ok = fail_code == RTU_ID_FAIL.OK

        if ok then
            table.insert(self.envd, envd)
            log.debug(util.c(log_tag, "linked environment detector #", envd.get_device_idx(), " [", envd.get_unit_id(), "@", envd.get_session_id(), "]"))
        else
            log.warning(util.c(log_tag, "rejected environment detector linking due to failure code ", fail_code, " (", fail_str, ")"))
        end

        return ok
    end

    -- purge devices associated with the given RTU session ID
    ---@param session integer RTU session ID
    function public.purge_rtu_devices(session)
        for _, v in pairs(self.rtu_list) do util.filter_table(v, function (s) return s.get_session_id() ~= session end) end
    end

    --#endregion

    --#region Update Session

    -- update (iterate) this unit
    function public.update()
        -- unlink PLC if session was closed
        if self.plc_s ~= nil and not self.plc_s.open then
            self.plc_s = nil
            self.plc_i = nil
            self.db.control.br100 = 0
        end

        -- unlink RTU sessions if they are closed
        for _, v in pairs(self.rtu_list) do util.filter_table(v, function (u) return u.is_connected() end) end

        -- update degraded state for auto control
        self.db.control.degraded = (#self.boilers ~= num_boilers) or (#self.turbines ~= num_turbines) or (self.plc_i == nil)

        -- check boilers formed/faulted
        for i = 1, #self.boilers do
            local sess = self.boilers[i]
            local boiler = sess.get_db()
            if sess.is_faulted() or not boiler.formed then
                self.db.control.degraded = true
            end
        end

        -- check turbines formed/faulted
        for i = 1, #self.turbines do
            local sess = self.turbines[i]
            local turbine = sess.get_db()
            if sess.is_faulted() or not turbine.formed then
                self.db.control.degraded = true
            end
        end

        -- plc instance checks
        if self.plc_i ~= nil then
            -- check if degraded
            local rps = self.plc_i.get_rps()
            if rps.fault or rps.sys_fail then self.db.control.degraded = true end

            -- re-engage auto lock if it reconnected without it
            if self.auto_engaged and not self.plc_i.is_auto_locked() then self.plc_i.auto_lock(true) end

            -- stop idling when completed
            if self.auto_idling and (((util.time_ms() - self.auto_idle_start) > IDLE_TIME) or not self.auto_idle) then
                log.info(util.c(log_tag, "completed idling period"))
                self.auto_idling = false
                self.plc_i.auto_set_burn(0, false)
            end
        end

        -- update deltas
        _dt__compute_all()

        -- update annunciator logic
        logic.update_annunciator(self)

        -- update alarm status
        logic.update_alarms(self)

        -- if in auto mode, SCRAM on certain alarms
        logic.update_auto_safety(public, self)

        -- update status text
        logic.update_status_text(self)

        -- handle redstone I/O
        if #self.redstone > 0 then
            logic.handle_redstone(self)
        elseif not self.plc_cache.rps_trip then
            self.em_cool_opened = false
        end
    end

    --#endregion

    --#region Auto Control Operations

    -- engage automatic control
    function public.auto_engage()
        self.auto_engaged = true
        if self.plc_i ~= nil then
            log.debug(util.c(log_tag, "engaged auto control"))
            self.plc_i.auto_lock(true)
        end
    end

    -- disengage automatic control
    function public.auto_disengage()
        self.auto_engaged = false
        if self.plc_i ~= nil then
            log.debug(util.c(log_tag, "disengaged auto control"))
            self.plc_i.auto_lock(false)
            self.db.control.br100 = 0
        end
    end

    -- set automatic control idling mode to change behavior when given a burn rate command of zero<br>
    -- - enabling it will hold the reactor at 0.01 mB/t for a period when commanded zero before disabling
    -- - disabling it will stop the reactor when commanded zero
    ---@param idle boolean true to enable, false to disable (and stop)
    function public.auto_set_idle(idle)
        if idle and not self.auto_idle then
            self.auto_idling = false
            self.auto_idle_start = 0
        end

        if idle ~= self.auto_idle then
            log.debug(util.c(log_tag, "idling mode changed to ", idle))
        end

        self.auto_idle = idle
    end

    -- get the actual limit of this unit<br>
    -- if it is degraded or not ready, the limit will be 0
    ---@nodiscard
    ---@return integer lim_br100
    function public.auto_get_effective_limit()
        local ctrl = self.db.control
        if (not ctrl.ready) or ctrl.degraded or self.plc_cache.rps_trip then
            -- log.debug(util.c(log_tag, "effective limit is zero! ready[", ctrl.ready, "] degraded[", ctrl.degraded, "] rps_trip[", self.plc_cache.rps_trip, "]"))
            ctrl.br100 = 0
            return 0
        else return ctrl.lim_br100 end
    end

    -- set the automatic burn rate based on the last set burn rate in 100ths
    ---@param ramp boolean true to ramp to rate, false to set right away
    function public.auto_commit_br100(ramp)
        if self.auto_engaged then
            if self.plc_i ~= nil then
                log.debug(util.c(log_tag, "commit br100 of ", self.db.control.br100, " with ramp set to ", ramp))

                local rate = self.db.control.br100 / 100

                if self.auto_idle then
                    if rate <= IDLE_RATE then
                        if self.auto_idle_start == 0 then
                            self.auto_idling = true
                            self.auto_idle_start = util.time_ms()
                            log.info(util.c(log_tag, "started idling at ", IDLE_RATE, " mB/t"))

                            rate = IDLE_RATE
                        elseif (util.time_ms() - self.auto_idle_start) > IDLE_TIME then
                            if self.auto_idling then
                                self.auto_idling = false
                                log.info(util.c(log_tag, "completed idling period"))
                            end
                        else
                            log.debug(util.c(log_tag, "continuing idle at ", IDLE_RATE, " mB/t"))

                            rate = IDLE_RATE
                        end
                    else
                        self.auto_idling = false
                        self.auto_idle_start = 0
                    end
                end

                self.plc_i.auto_set_burn(rate, ramp)

                if ramp then self.ramp_target_br100 = self.db.control.br100 end
            end
        end
    end

    -- check if ramping is complete (burn rate is same as target)
    ---@nodiscard
    ---@return boolean complete
    function public.auto_ramp_complete()
        if self.plc_i ~= nil then
            return self.plc_i.is_ramp_complete() or
                (self.plc_i.get_status().act_burn_rate == 0 and self.db.control.br100 == 0) or
                public.auto_get_effective_limit() == 0
        else return true end
    end

    -- perform an automatic SCRAM
    function public.auto_scram()
        if self.plc_s ~= nil then
            self.db.control.br100 = 0
            self.plc_s.in_queue.push_command(PLC_S_CMDS.ASCRAM)
        end
    end

    -- queue a command to clear timeout/auto-scram if set
    function public.auto_cond_rps_reset()
        if self.plc_s ~= nil and self.plc_i ~= nil and (not self.auto_was_alarmed) and (not self.em_cool_opened) then
            local rps = self.plc_i.get_rps()
            if rps.timeout or rps.automatic then
                self.plc_i.auto_lock(true)  -- if it timed out/restarted, auto lock was lost, so re-lock it
                self.plc_s.in_queue.push_command(PLC_S_CMDS.RPS_AUTO_RESET)
            end
        end
    end

    -- set automatic waste product if mode is set to auto
    ---@param product WASTE_PRODUCT waste product to generate
    function public.auto_set_waste(product)
        if self.db.control.waste_mode == WASTE_MODE.AUTO then
            self.waste_product = product
            _set_waste_valves(product)
        end
    end

    --#endregion

    --#region Operations

    -- queue a command to disable the reactor
    function public.disable()
        if self.plc_s ~= nil then
            self.plc_s.in_queue.push_command(PLC_S_CMDS.DISABLE)
        end
    end

    -- queue a command to SCRAM the reactor
    function public.scram()
        if self.plc_s ~= nil then
            self.plc_s.in_queue.push_command(PLC_S_CMDS.SCRAM)
        end
    end

    -- queue a SCRAM command only if a manual SCRAM has not already occured
    function public.cond_scram()
        if self.plc_s ~= nil and not self.plc_cache.rps_status.manual then
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
        if type(id) == "number" and self.db.alarm_states[id] == ALARM_STATE.TRIPPED then
            self.db.alarm_states[id] = ALARM_STATE.ACKED
        end
    end

    -- reset an alarm (if possible)
    ---@param id ALARM alarm ID
    function public.reset_alarm(id)
        if type(id) == "number" and self.db.alarm_states[id] == ALARM_STATE.RING_BACK then
            self.db.alarm_states[id] = ALARM_STATE.INACTIVE
        end
    end

    -- set waste processing mode
    ---@param mode WASTE_MODE processing mode
    function public.set_waste_mode(mode)
        self.db.control.waste_mode = mode

        if mode == WASTE_MODE.MANUAL_PLUTONIUM then
            _set_waste_valves(WASTE.PLUTONIUM)
        elseif mode == WASTE_MODE.MANUAL_POLONIUM then
            _set_waste_valves(WASTE.POLONIUM)
        elseif mode == WASTE_MODE.MANUAL_ANTI_MATTER then
            _set_waste_valves(WASTE.ANTI_MATTER)
        elseif mode > WASTE_MODE.MANUAL_ANTI_MATTER then
            log.debug(util.c("invalid waste mode setting ", mode))
        end
    end

    -- set the automatic control max burn rate for this unit
    ---@param limit number burn rate limit for auto control
    function public.set_burn_limit(limit)
        if limit > 0 then
            self.db.control.lim_br100 = math.floor(limit * 100)

            if (self.plc_i ~= nil) and (type(self.plc_i.get_struct().max_burn) == "number") then
                if limit > self.plc_i.get_struct().max_burn then
                    self.db.control.lim_br100 = math.floor(self.plc_i.get_struct().max_burn * 100)
                end
            end
        end
    end

    --#endregion

    --#region Read States/Properties

    -- check if an alarm of at least a certain priority level is tripped
    ---@nodiscard
    ---@param min_prio ALARM_PRIORITY alarms with this priority or higher will be checked
    ---@return boolean tripped
    function public.has_alarm_min_prio(min_prio)
        for _, alarm in pairs(self.alarms) do
            if alarm.tier <= min_prio and (alarm.state == AISTATE.TRIPPED or alarm.state == AISTATE.ACKED) then
                return true
            end
        end

        return false
    end

    -- check the active state of the reactor (if connected)
    ---@nodiscard
    function public.is_reactor_enabled()
        if self.plc_i ~= nil then return self.plc_i.get_status().status else return false end
    end

    -- check if the reactor is connected, is stopped, the RPS is not tripped, and no alarms are active
    ---@nodiscard
    function public.is_safe_idle()
        -- can't be disconnected
        if self.plc_i == nil then return false end

        -- reactor must be stopped and RPS can't be tripped
        if self.plc_i.get_status().status or self.plc_i.get_db().rps_tripped then return false end

        -- alarms must be inactive and not tripping
        for _, alarm in pairs(self.alarms) do
            if not (alarm.state == AISTATE.INACTIVE or alarm.state == AISTATE.RING_BACK) then return false end
        end

        return true
    end

    -- check if emergency coolant activation has been tripped
    ---@nodiscard
    function public.is_emer_cool_tripped() return self.em_cool_opened end

    -- get build properties of machines
    --
    -- filter options
    -- - nil to include all builds
    -- - -1 to include only PLC build
    -- - RTU_UNIT_TYPE to include all builds of machines of that type
    ---@nodiscard
    ---@param filter -1|RTU_UNIT_TYPE? filter as described above
    function public.get_build(filter)
        local all = filter == nil
        local build = {}

        if all or (filter == -1) then
            if self.plc_i ~= nil then
                build.reactor = self.plc_i.get_struct()
            end
        end

        if all or (filter == RTU_UNIT_TYPE.BOILER_VALVE) then
            build.boilers = {}
            for i = 1, #self.boilers do
                local boiler = self.boilers[i]
                build.boilers[boiler.get_device_idx()] = { boiler.get_db().formed, boiler.get_db().build }
            end
        end

        if all or (filter == RTU_UNIT_TYPE.TURBINE_VALVE) then
            build.turbines = {}
            for i = 1, #self.turbines do
                local turbine = self.turbines[i]
                build.turbines[turbine.get_device_idx()] = { turbine.get_db().formed, turbine.get_db().build }
            end
        end

        if all or (filter == RTU_UNIT_TYPE.DYNAMIC_VALVE) then
            build.tanks = {}
            for i = 1, #self.tanks do
                local tank = self.tanks[i]
                build.tanks[tank.get_device_idx()] = { tank.get_db().formed, tank.get_db().build }
            end
        end

        return build
    end

    -- get reactor status
    ---@nodiscard
    function public.get_reactor_status()
        local status = {}
        if self.plc_i ~= nil then
            status = { self.plc_i.get_status(), self.plc_i.get_rps(), self.plc_i.get_general_status() }
        end

        return status
    end

    -- get the current burn rate (actual rate)
    ---@nodiscard
    function public.get_burn_rate()
        local rate = 0
        if self.plc_i ~= nil then rate = self.plc_i.get_status().act_burn_rate end
        return rate or 0
    end

    -- check which RTUs are connected
    ---@nodiscard
    function public.check_rtu_conns()
        ---@class unit_connections
        ---@field boilers boolean[]
        ---@field turbines boolean[]
        ---@field tanks boolean[]
        local conns = {}

        conns.boilers = {}
        for i = 1, #self.boilers do
            conns.boilers[self.boilers[i].get_device_idx()] = true
        end

        conns.turbines = {}
        for i = 1, #self.turbines do
            conns.turbines[self.turbines[i].get_device_idx()] = true
        end

        conns.tanks = {}
        for i = 1, #self.tanks do
            conns.tanks[self.tanks[i].get_device_idx()] = true
        end

        return conns
    end

    -- get RTU statuses
    ---@nodiscard
    function public.get_rtu_statuses()
        local status = {}

        -- status of boilers (including tanks)
        status.boilers = {}
        for i = 1, #self.boilers do
            local boiler = self.boilers[i]
            local db = boiler.get_db()
            status.boilers[boiler.get_device_idx()] = { boiler.is_faulted(), db.formed, db.state, db.tanks }
        end

        -- status of turbines (including tanks)
        status.turbines = {}
        for i = 1, #self.turbines do
            local turbine = self.turbines[i]
            local db = turbine.get_db()
            status.turbines[turbine.get_device_idx()] = { turbine.is_faulted(), db.formed, db.state, db.tanks }
        end

        -- status of dynamic tanks
        status.tanks = {}
        for i = 1, #self.tanks do
            local tank = self.tanks[i]
            local db = tank.get_db()
            status.tanks[tank.get_device_idx()] = { tank.is_faulted(), db.formed, db.state, db.tanks }
        end

        -- SNA statistical information
        local total_peak, total_avail, total_out = 0, 0, 0
        for i = 1, #self.snas do
            local db = self.snas[i].get_db()
            total_peak = total_peak + db.state.peak_production
            total_avail = total_avail + db.state.production_rate
            local out_from_in = util.trinary(db.tanks.input.amount >= 10, db.tanks.input.amount / 10, 0)
            total_out = total_out + math.min(out_from_in, db.state.production_rate)
        end
        status.sna = { #self.snas, total_peak, total_avail, total_out }

        -- radiation monitors (environment detectors)
        status.envds = {}
        for i = 1, #self.envd do
            local envd = self.envd[i]
            local db = envd.get_db()
            status.envds[envd.get_device_idx()] = { envd.is_faulted(), db.radiation, db.radiation_raw }
        end

        return status
    end

    -- get the current total max production rate
    ---@nodiscard
    ---@return number total_avail_rate
    function public.get_sna_rate()
        local total_avail_rate = 0

        for i = 1, #self.snas do
            local db = self.snas[i].get_db()
            total_avail_rate = total_avail_rate + db.state.production_rate
        end

        return total_avail_rate
    end

    -- get the annunciator status
    ---@nodiscard
    function public.get_annunciator() return self.db.annunciator end

    -- get the alarm states
    ---@nodiscard
    function public.get_alarms() return self.db.alarm_states end

    -- get information required for automatic reactor control
    ---@nodiscard
    function public.get_control_inf() return self.db.control end

    -- get unit state
    ---@nodiscard
    function public.get_state()
        return {
            self.status_text[1],
            self.status_text[2],
            self.db.control.ready,
            self.db.control.degraded,
            self.db.control.waste_mode,
            self.waste_product,
            self.last_rate_change_ms,
            self.turbine_flow_stable
        }
    end

    -- get valve states
    ---@nodiscard
    function public.get_valves()
        local v = self.valves
        return {
            v.waste_pu.check(),
            v.waste_sna.check(),
            v.waste_po.check(),
            v.waste_sps.check(),
            v.emer_cool.check(),
            v.aux_cool.check()
        }
    end

    -- get the reactor ID
    ---@nodiscard
    function public.get_id() return self.r_id end

    --#endregion

    return public
end

return unit
