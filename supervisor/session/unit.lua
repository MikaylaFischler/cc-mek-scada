local types = require "scada-common.types"
local util  = require "scada-common.util"
local log   = require "scada-common.log"

local unit = {}

local TRI_FAIL = types.TRI_FAIL
local DUMPING_MODE = types.DUMPING_MODE

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
    TurbineSteam = "TST"
}

-- create a new reactor unit
---@param for_reactor integer reactor unit number
---@param num_boilers integer number of boilers expected
---@param num_turbines integer number of turbines expected
function unit.new(for_reactor, num_boilers, num_turbines)
    local self = {
        r_id = for_reactor,
        plc_s = nil,    ---@class plc_session_struct
        plc_i = nil,    ---@class plc_session
        counts = { boilers = num_boilers, turbines = num_turbines },
        turbines = {},
        boilers = {},
        redstone = {},
        deltas = {},
        last_heartbeat = 0,
        db = {
            ---@class annunciator
            annunciator = {
                -- reactor
                PLCOnline = false,
                PLCHeartbeat = false,   -- alternate true/false to blink, each time there is a keep_alive
                ReactorSCRAM = false,
                ManualReactorSCRAM = false,
                RCPTrip = false,
                RCSFlowLow = false,
                ReactorTempHigh = false,
                ReactorHighDeltaT = false,
                FuelInputRateLow = false,
                WasteLineOcclusion = false,
                HighStartupRate = false,
                -- boiler
                BoilerOnline = {},
                HeatingRateLow = {},
                BoilRateMismatch = false,
                CoolantFeedMismatch = false,
                -- turbine
                TurbineOnline = {},
                SteamFeedMismatch = false,
                MaxWaterReturnFeed = false,
                SteamDumpOpen = {},
                TurbineOverSpeed = {},
                TurbineTrip = {}
            }
        }
    }

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

    ---@class reactor_unit
    local public = {}

    -- PRIVATE FUNCTIONS --

    -- compute a change with respect to time of the given value
    ---@param key string value key
    ---@param value number value
    local function _compute_dt(key, value)
        if self.deltas[key] then
            local data = self.deltas[key]

            data.dt = (value - data.last_v) / (util.time_s() - data.last_t)

            data.last_v = value
            data.last_t = util.time_s()
        else
            self.deltas[key] = {
                last_t = util.time_s(),
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
        if self.deltas[key] then
            return self.deltas[key].dt
        else
            return 0.0
        end
    end

    -- update all delta computations
    local function _dt__compute_all()
        if self.plc_s ~= nil then
            local plc_db = self.plc_i.get_db()

            -- @todo Meknaism 10.1+ will change fuel/waste to need _amnt
            _compute_dt(DT_KEYS.ReactorTemp, plc_db.mek_status.temp)
            _compute_dt(DT_KEYS.ReactorFuel, plc_db.mek_status.fuel)
            _compute_dt(DT_KEYS.ReactorWaste, plc_db.mek_status.waste)
            _compute_dt(DT_KEYS.ReactorCCool, plc_db.mek_status.ccool_amnt)
            _compute_dt(DT_KEYS.ReactorHCool, plc_db.mek_status.hcool_amnt)
        end

        for i = 1, #self.boilers do
            local boiler = self.boilers[i]  ---@type unit_session
            local db = boiler.get_db()      ---@type boiler_session_db

            -- @todo Meknaism 10.1+ will change water/steam to need .amount
            _compute_dt(DT_KEYS.BoilerWater .. boiler.get_device_idx(), db.tanks.water)
            _compute_dt(DT_KEYS.BoilerSteam .. boiler.get_device_idx(), db.tanks.steam)
            _compute_dt(DT_KEYS.BoilerCCool .. boiler.get_device_idx(), db.tanks.ccool.amount)
            _compute_dt(DT_KEYS.BoilerHCool .. boiler.get_device_idx(), db.tanks.hcool.amount)
        end

        for i = 1, #self.turbines do
            local turbine = self.turbines[i]    ---@type unit_session
            local db = turbine.get_db()         ---@type turbine_session_db

            _compute_dt(DT_KEYS.TurbineSteam .. turbine.get_device_idx(), db.tanks.steam)
            -- @todo Mekanism 10.1+ needed
            -- _compute_dt(DT_KEYS.TurbinePower .. turbine.get_device_idx(), db.?)
        end
    end

    -- update the annunciator
    local function _update_annunciator()
        -- update deltas
        _dt__compute_all()

        -------------
        -- REACTOR --
        -------------

        -- check PLC status
        self.db.annunciator.PLCOnline = (self.plc_s ~= nil) and (self.plc_s.open)

        if self.plc_s ~= nil then
            local plc_db = self.plc_i.get_db()

            -- heartbeat blink about every second
            if self.last_heartbeat + 1000 < plc_db.last_status_update then
                self.db.annunciator.PLCHeartbeat = not self.db.annunciator.PLCHeartbeat
                self.last_heartbeat = plc_db.last_status_update
            end

            -- update other annunciator fields
            self.db.annunciator.ReactorSCRAM = plc_db.overridden
            self.db.annunciator.ManualReactorSCRAM = plc_db.rps_trip_cause == types.rps_status_t.manual
            self.db.annunciator.RCPTrip = plc_db.rps_tripped and (plc_db.rps_status.ex_hcool or plc_db.rps_status.no_cool)
            self.db.annunciator.RCSFlowLow = plc_db.mek_status.ccool_fill < 0.75 or plc_db.mek_status.hcool_fill > 0.25
            self.db.annunciator.ReactorTempHigh = plc_db.mek_status.temp > 1000
            self.db.annunciator.ReactorHighDeltaT = _get_dt(DT_KEYS.ReactorTemp) > 100
            self.db.annunciator.FuelInputRateLow = _get_dt(DT_KEYS.ReactorFuel) < 0.0 or plc_db.mek_status.fuel_fill <= 0.01
            -- @todo this is catagorized as not urgent, but the >= 0.99 is extremely urgent, revist this (RPS will kick in though)
            self.db.annunciator.WasteLineOcclusion = _get_dt(DT_KEYS.ReactorWaste) > 0.0 or plc_db.mek_status.waste_fill >= 0.99
            -- @todo this is dependent on setup, i.e. how much coolant is buffered and the turbine setup
            self.db.annunciator.HighStartupRate = not plc_db.control_state and plc_db.mek_status.burn_rate > 40
        end

        -------------
        -- BOILERS --
        -------------

        -- clear boiler online flags
        for i = 1, self.counts.boilers do self.db.annunciator.BoilerOnline[i] = false end

        -- aggregated statistics
        local total_boil_rate = 0.0
        local boiler_steam_dt_sum = 0.0
        local boiler_water_dt_sum = 0.0

        -- go through boilers for stats and online
        for i = 1, #self.boilers do
            local session = self.boilers[i] ---@type unit_session
            local boiler = session.get_db() ---@type boiler_session_db

            total_boil_rate = total_boil_rate + boiler.state.boil_rate
            boiler_steam_dt_sum = _get_dt(DT_KEYS.BoilerSteam .. self.boilers[i].get_device_idx())
            boiler_water_dt_sum = _get_dt(DT_KEYS.BoilerWater .. self.boilers[i].get_device_idx())

            self.db.annunciator.BoilerOnline[session.get_device_idx()] = true
        end

        -- check heating rate low
        if self.plc_s ~= nil then
            local r_db = self.plc_i.get_db()

            -- check for inactive boilers while reactor is active
            for i = 1, #self.boilers do
                local boiler = self.boilers[i]  ---@type unit_session
                local idx = boiler.get_device_idx()
                local db = boiler.get_db()      ---@type boiler_session_db

                if r_db.mek_status.status then
                    self.db.annunciator.HeatingRateLow[idx] = db.state.boil_rate == 0
                else
                    self.db.annunciator.HeatingRateLow[idx] = false
                end
            end

            -- check for rate mismatch
            local expected_boil_rate = r_db.mek_status.heating_rate / 10.0
            self.db.annunciator.BoilRateMismatch = math.abs(expected_boil_rate - total_boil_rate) > 25.0
        end

        -- check coolant feed mismatch
        local cfmismatch = false
        for i = 1, #self.boilers do
            local boiler = self.boilers[i]  ---@type unit_session
            local idx = boiler.get_device_idx()
            local db = boiler.get_db()      ---@type boiler_session_db

            -- gaining heated coolant
            cfmismatch = cfmismatch or _get_dt(DT_KEYS.BoilerHCool .. idx) > 0 or db.tanks.hcool_fill == 1
            -- losing cooled coolant
            cfmismatch = cfmismatch or _get_dt(DT_KEYS.BoilerCCool .. idx) < 0 or db.tanks.ccool_fill == 0
        end

        self.db.annunciator.CoolantFeedMismatch = cfmismatch

        --------------
        -- TURBINES --
        --------------

        -- clear turbine online flags
        for i = 1, self.counts.turbines do self.db.annunciator.TurbineOnline[i] = false end

        -- aggregated statistics
        local total_flow_rate = 0
        local total_input_rate = 0
        local max_water_return_rate = 0

        -- go through turbines for stats and online
        for i = 1, #self.turbines do
            local session = self.turbine[i]     ---@type unit_session
            local turbine = session.get_db()    ---@type turbine_session_db

            total_flow_rate = total_flow_rate + turbine.state.flow_rate
            total_input_rate = total_input_rate + turbine.state.steam_input_rate
            max_water_return_rate = max_water_return_rate + turbine.build.max_water_output

            self.db.annunciator.TurbineOnline[session.get_device_idx()] = true
        end

        -- check for steam feed mismatch and max return rate
        local sfmismatch = math.abs(total_flow_rate - total_input_rate) > 10
        sfmismatch = sfmismatch or boiler_steam_dt_sum > 0 or boiler_water_dt_sum < 0
        self.db.annunciator.SteamFeedMismatch = sfmismatch
        self.db.annunciator.MaxWaterReturnFeed = max_water_return_rate == total_flow_rate and total_flow_rate ~= 0

        -- check if steam dumps are open
        for i = 1, #self.turbines do
            local turbine = self.turbines[i]    ---@type unit_session
            local db = turbine.get_db()         ---@type turbine_session_db
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
            local db = turbine.get_db()         ---@type turbine_session_db
            local idx = turbine.get_device_idx()

            self.db.annunciator.TurbineOverSpeed[idx] = (db.state.flow_rate == db.build.max_flow_rate) and (_get_dt(DT_KEYS.TurbineSteam .. idx) > 0)
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
            local db = turbine.get_db()         ---@type turbine_session_db

            local has_steam = db.state.steam_input_rate > 0 or db.tanks.steam_fill > 0.01
            self.db.annunciator.TurbineTrip[turbine.get_device_idx()] = has_steam and db.state.flow_rate == 0
        end
    end

    -- unlink disconnected units
    ---@param sessions table
    local function _unlink_disconnected_units(sessions)
        util.filter_table(sessions, function (u) return u.is_connected() end)
    end

    -- PUBLIC FUNCTIONS --

    -- link the PLC
    ---@param plc_session plc_session_struct
    function public.link_plc_session(plc_session)
        self.plc_s = plc_session
        self.plc_i = plc_session.instance

        -- reset deltas
        _reset_dt(DT_KEYS.ReactorTemp)
        _reset_dt(DT_KEYS.ReactorFuel)
        _reset_dt(DT_KEYS.ReactorWaste)
        _reset_dt(DT_KEYS.ReactorCCool)
        _reset_dt(DT_KEYS.ReactorHCool)
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

    -- link a redstone RTU capability
    function public.add_redstone(field, accessor)
        -- ensure field exists
        if self.redstone[field] == nil then
            self.redstone[field] = {}
        end

        -- insert into list
        table.insert(self.redstone[field], accessor)
    end

    -- update (iterate) this unit
    function public.update()
        -- unlink PLC if session was closed
        if self.plc_s ~= nil and not self.plc_s.open then
            self.plc_s = nil
        end

        -- unlink RTU unit sessions if they are closed
        _unlink_disconnected_units(self.boilers)
        _unlink_disconnected_units(self.turbines)

        -- update annunciator logic
        _update_annunciator()
    end

    -- get build properties of all machines
    function public.get_build()
        local build = {}

        if self.plc_s ~= nil then
            build.reactor = self.plc_i.get_struct()
        end

        build.boilers = {}
        for i = 1, #self.boilers do
            local boiler = self.boilers[i]  ---@type unit_session
            build.boilers[boiler.get_device_idx()] = { boiler.get_db().build, boiler.get_db().formed }
        end

        build.turbines = {}
        for i = 1, #self.turbines do
            local turbine = self.turbines[i]  ---@type unit_session
            build.turbines[turbine.get_device_idx()] = { turbine.get_db().build, turbine.get_db().formed }
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
            status.boilers[boiler.get_device_idx()] = { boiler.get_db().state, boiler.get_db().tanks }
        end

        -- status of turbines (including tanks)
        status.turbines = {}
        for i = 1, #self.turbines do
            local turbine = self.turbines[i]  ---@type unit_session
            status.turbines[turbine.get_device_idx()] = { turbine.get_db().state, turbine.get_db().tanks }
        end

        ---@todo other RTU statuses

        return status
    end

    -- get the annunciator status
    function public.get_annunciator() return self.db.annunciator end

    -- get the reactor ID
    function public.get_id() return self.r_id end

    return public
end

return unit
