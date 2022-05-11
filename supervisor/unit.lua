local unit = {}

-- create a new reactor unit
---@param for_reactor integer
unit.new = function (for_reactor)
    local self = {
        r_id = for_reactor,
        plc_s = nil,
        turbines = {},
        boilers = {},
        energy_storage = {},
        redstone = {},
        db = {
            ---@class annunciator
            annunciator = {
                -- RPS
                -- reactor
                PLCOnline = false,
                ReactorTrip = false,
                ManualReactorTrip = false,
                RCPTrip = false,
                RCSFlowLow = false,
                ReactorTempHigh = false,
                ReactorHighDeltaT = false,
                ReactorOverPower = false,
                HighStartupRate = false,
                -- boiler
                BoilerOnline = false,
                HeatingRateLow = false,
                CoolantFeedMismatch = false,
                -- turbine
                TurbineOnline = false,
                SteamFeedMismatch = false,
                SteamDumpOpen = false,
                TurbineTrip = false,
                TurbineOverUnderSpeed = false
            }
        }
    }

    ---@class reactor_unit
    local public = {}

    -- PRIVATE FUNCTIONS --

    -- update the annunciator
    local _update_annunciator = function ()
        self.db.annunciator.PLCOnline = (self.plc_s ~= nil) and (self.plc_s.open)
        self.db.annunciator.ReactorTrip = false
    end

    -- PUBLIC FUNCTIONS --

    -- link the PLC
    ---@param plc_session plc_session_struct
    public.link_plc_session = function (plc_session)
        self.plc_s = plc_session
    end

    -- link a turbine RTU
    public.add_turbine = function (turbine)
        table.insert(self.turbines, turbine)
    end

    -- link a boiler RTU
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

        -- update annunciator logic
        _update_annunciator()
    end

    -- get the annunciator status
    public.get_annunciator = function () return self.db.annunciator end

    return public
end

return unit
