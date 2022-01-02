-- Internal Safety System
-- identifies dangerous states and SCRAMs reactor if warranted
-- autonomous from main control
function iss_init(reactor)
    local self = {
        _reactor = reactor,
        _tripped = false,
        _trip_cause = ""
    }

    local check = function ()
        local status = "ok"
        
        -- check system states in order of severity
        if self.damage_critical() then
            status = "dmg_crit"
        elseif self.high_temp() then
            status = "high_temp"
        elseif self.excess_heated_coolant() then
            status = "heated_coolant_backup"
        elseif self.excess_waste() then
            status = "full_waste"
        elseif self.insufficient_fuel() then
            status = "no_fuel"
        elseif self._tripped then
            status = self._trip_cause
        else
            self._tripped = false
        end
    
        if status ~= "ok" then
            self._tripped = true
            self._trip_cause = status
            self._reactor.scram()
        end
    
        return self._tripped, status
    end

    local reset = function ()
        self._tripped = false
        self._trip_cause = ""
    end
    
    local damage_critical = function ()
        return self._reactor.getDamagePercent() >= 100
    end
    
    local excess_heated_coolant = function ()
        return self._reactor.getHeatedCoolantNeeded() == 0
    end
    
    local excess_waste = function ()
        return self._reactor.getWasteNeeded() == 0
    end

    local high_temp = function ()
        -- mekanism: MAX_DAMAGE_TEMPERATURE = 1_200
        return self._reactor.getTemperature() >= 1200
    end
    
    local insufficient_fuel = function ()
        return self._reactor.getFuel() == 0
    end

    local no_coolant = function()
        return self._reactor.getCoolantFilledPercentage() < 2
    end

    return {
        check = check,
        reset = reset,
        damage_critical = damage_critical,
        excess_heated_coolant = excess_heated_coolant,
        excess_waste = excess_waste,
        high_temp = high_temp,
        insufficient_fuel = insufficient_fuel,
        no_coolant = no_coolant
    }
end
