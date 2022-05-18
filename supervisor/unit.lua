local types = require "scada-common.types"
local util  = require "scada-common.util"

local unit = {}

---@alias TRI_FAIL integer
local TRI_FAIL = {
    OK = 0,
    PARTIAL = 1,
    FULL = 2
}

-- create a new reactor unit
---@param for_reactor integer reactor unit number
---@param num_boilers integer number of boilers expected
---@param num_turbines integer number of turbines expected
unit.new = function (for_reactor, num_boilers, num_turbines)
    local self = {
        r_id = for_reactor,
        plc_s = nil,    ---@class plc_session
        counts = { boilers = num_boilers, turbines = num_turbines },
        turbines = {},
        boilers = {},
        energy_storage = {},
        redstone = {},
        deltas = {
            last_reactor_temp = nil,
            last_reactor_temp_time = 0
        },
        db = {
            ---@class annunciator
            annunciator = {
                -- reactor
                PLCOnline = false,
                ReactorTrip = false,
                ManualReactorTrip = false,
                RCPTrip = false,
                RCSFlowLow = false,
                ReactorTempHigh = false,
                ReactorHighDeltaT = false,
                HighStartupRate = false,
                -- boiler
                BoilerOnline = TRI_FAIL.OK,
                HeatingRateLow = false,
                BoilRateMismatch = false,
                CoolantFeedMismatch = false,
                -- turbine
                TurbineOnline = TRI_FAIL.OK,
                SteamFeedMismatch = false,
                SteamDumpOpen = false,
                TurbineOverSpeed = false,
                TurbineTrip = false
            }
        }
    }

    ---@class reactor_unit
    local public = {}

    -- PRIVATE FUNCTIONS --

    -- update the annunciator
    local _update_annunciator = function ()
        -- check PLC status
        self.db.annunciator.PLCOnline = (self.plc_s ~= nil) and (self.plc_s.open)

        if self.plc_s ~= nil then
            -------------
            -- REACTOR --
            -------------

            local plc_db = self.plc_s.get_db()

            -- compute deltas
            local reactor_delta_t = 0
            if self.deltas.last_reactor_temp ~= nil then
                reactor_delta_t = (plc_db.mek_status.temp - self.deltas.last_reactor_temp) / (util.time_s() - self.deltas.last_reactor_temp_time)
            else
                self.deltas.last_reactor_temp = plc_db.mek_status.temp
                self.deltas.last_reactor_temp_time = util.time_s()
            end

            -- update annunciator
            self.db.annunciator.ReactorTrip = plc_db.rps_tripped
            self.db.annunciator.ManualReactorTrip = plc_db.rps_trip_cause == types.rps_status_t.manual
            self.db.annunciator.RCPTrip = plc_db.rps_tripped and (plc_db.rps_status.ex_hcool or plc_db.rps_status.no_cool)
            self.db.annunciator.RCSFlowLow = plc_db.mek_status.ccool_fill < 0.75 or plc_db.mek_status.hcool_fill > 0.25
            self.db.annunciator.ReactorTempHigh = plc_db.mek_status.temp > 1000
            self.db.annunciator.ReactorHighDeltaT = reactor_delta_t > 100
            -- @todo this is dependent on setup, i.e. how much coolant is buffered and the turbine setup
            self.db.annunciator.HighStartupRate = not plc_db.control_state and plc_db.mek_status.burn_rate > 40
        end

        -------------
        -- BOILERS --
        -------------

        -- check boiler online status
        local connected_boilers = #self.boilers
        if connected_boilers == 0 and self.num_boilers > 0 then
            self.db.annunciator.BoilerOnline = TRI_FAIL.FULL
        elseif connected_boilers > 0 and connected_boilers ~= self.num_boilers then
            self.db.annunciator.BoilerOnline = TRI_FAIL.PARTIAL
        else
            self.db.annunciator.BoilerOnline = TRI_FAIL.OK
        end

        local total_boil_rate = 0.0
        local no_boil_count = 0
        for i = 1, #self.boilers do
            local boiler = self.boilers[i].get_db() ---@type boiler_session_db
            local boil_rate = boiler.state.boil_rate
            if boil_rate == 0 then
                no_boil_count = no_boil_count + 1
            else
                total_boil_rate = total_boil_rate + boiler.state.boil_rate
            end
        end

        if no_boil_count == 0 and self.num_boilers > 0 then
            self.db.annunciator.HeatingRateLow = TRI_FAIL.FULL
        elseif no_boil_count > 0 and no_boil_count ~= self.num_boilers then
            self.db.annunciator.HeatingRateLow = TRI_FAIL.PARTIAL
        else
            self.db.annunciator.HeatingRateLow = TRI_FAIL.OK
        end

        if self.plc_s ~= nil then
            local expected_boil_rate = self.plc_s.get_db().mek_status.heating_rate / 10.0
            self.db.annunciator.BoilRateMismatch = math.abs(expected_boil_rate - total_boil_rate) > 25.0
        else
            self.db.annunciator.BoilRateMismatch = false
        end

        --------------
        -- TURBINES --
        --------------

        -- check turbine online status
        local connected_turbines = #self.turbines
        if connected_turbines == 0 and self.num_turbines > 0 then
            self.db.annunciator.TurbineOnline = TRI_FAIL.FULL
        elseif connected_turbines > 0 and connected_turbines ~= self.num_turbines then
            self.db.annunciator.TurbineOnline = TRI_FAIL.PARTIAL
        else
            self.db.annunciator.TurbineOnline = TRI_FAIL.OK
        end

        --[[
            Turbine Under/Over Speed
        ]]--

        --[[
            Turbine Trip
            a turbine trip is when the turbine stops, which means we are no longer receiving water and lose the ability to cool
            this can be identified by these conditions:
            - the current flow rate is 0 mB/t and it should not be
                - it should not be if the boiler or reactor has a non-zero heating rate
                - can initially catch this by detecting a 0 flow rate with a non-zero input rate, but eventually the steam will fill up
                - can later identified by presence of steam in tank with a 0 flow rate
        ]]--
    end

    -- unlink disconnected units
    ---@param sessions table
    local _unlink_disconnected_units = function (sessions)
        util.filter_table(sessions, function (u) return u.is_connected() end)
    end

    -- PUBLIC FUNCTIONS --

    -- link the PLC
    ---@param plc_session plc_session_struct
    public.link_plc_session = function (plc_session)
        self.plc_s = plc_session
        self.deltas.last_reactor_temp = self.plc_s.get_db().mek_status.temp
        self.deltas.last_reactor_temp_time = util.time_s()
    end

    -- link a turbine RTU session
    ---@param turbine unit_session
    public.add_turbine = function (turbine)
        table.insert(self.turbines, turbine)
    end

    -- link a boiler RTU session
    ---@param boiler unit_session
    public.add_boiler = function (boiler)
        table.insert(self.boilers, boiler)
    end

    -- link a redstone RTU capability
    public.add_redstone = function (field, accessor)
        -- ensure field exists
        if self.redstone[field] == nil then
            self.redstone[field] = {}
        end

        -- insert into list
        table.insert(self.redstone[field], accessor)
    end

    -- update (iterate) this session
    public.update = function ()
        -- unlink PLC if session was closed
        if not self.plc_s.open then
            self.plc_s = nil
        end

        -- unlink RTU unit sessions if they are closed
        _unlink_disconnected_units(self.boilers)
        _unlink_disconnected_units(self.turbines)

        -- update annunciator logic
        _update_annunciator()
    end

    -- get the annunciator status
    public.get_annunciator = function () return self.db.annunciator end

    return public
end

return unit
