local unit = {}

unit.new = function (for_reactor)
    local public = {}

    local self = {
        r_id = for_reactor,
        plc_s = nil,
        turbines = {},
        boilers = {},
        energy_storage = {},
        redstone = {},
        db = {
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

    public.link_plc_session = function (plc_session)
        self.plc_s = plc_session
    end

    public.add_turbine = function (turbine)
        table.insert(self.turbines, turbine)
    end

    public.add_boiler = function (turbine)
        table.insert(self.boilers, boiler)
    end

    public.add_redstone = function (field, accessor)
        -- ensure field exists
        if redstone[field] == nil then
            redstone[field] = {}
        end

        -- insert into list
        table.insert(redstone[field], accessor)
    end

    local _update_annunciator = function ()
        self.db.annunciator.PLCOnline = (self.plc_s ~= nil) and (self.plc_s.open)
        self.db.annunciator.ReactorTrip = false
    end

    public.update = function ()
        -- unlink PLC if session was closed
        if not self.plc_s.open then
            self.plc_s = nil
        end

        -- update annunciator logic
        _update_annunciator()
    end

    public.get_annunciator = function () return self.db.annunciator end

    return public
end

return unit
