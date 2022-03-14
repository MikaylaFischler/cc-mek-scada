function scada_link(plc_comms)
    local linked = false
    local link_timeout = os.startTimer(5)

    plc_comms.send_link_req()
    print_ts("sent link request")
    
    repeat
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
    
        -- handle event
        if event == "timer" and param1 == link_timeout then
            -- no response yet
            print("...no response");
        elseif event == "modem_message" then
            -- server response? cancel timeout
            if link_timeout ~= nil then
                os.cancelTimer(link_timeout)
            end

            local packet = plc_comms.parse_packet(p1, p2, p3, p4, p5)
            if packet then
                -- handle response
                local response = plc_comms.handle_link(packet)
                if response == nil then
                    print_ts("invalid link response, bad channel?\n")
                    break
                elseif response == comms.RPLC_LINKING.COLLISION then
                    print_ts("...reactor PLC ID collision (check config), exiting...\n")
                    break
                elseif response == comms.RPLC_LINKING.ALLOW then
                    print_ts("...linked!\n")
                    linked = true
                    plc_comms.send_rs_io_conns()
                    plc_comms.send_struct()
                    plc_comms.send_status()
                    print_ts("sent initial data\n")
                else
                    print_ts("...denied, exiting...\n")
                    break
                end
            end
        end
    until linked

    return linked
end

-- Internal Safety System
-- identifies dangerous states and SCRAMs reactor if warranted
-- autonomous from main control
function iss_init(reactor)
    local self = {
        reactor = reactor,
        timed_out = false,
        tripped = false,
        trip_cause = ""
    }

    local check = function ()
        local status = "ok"
        local was_tripped = self.tripped
        
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
        elseif self.tripped then
            status = self.trip_cause
        else
            self.tripped = false
        end
    
        if status ~= "ok" then
            self.tripped = true
            self.trip_cause = status
            self.reactor.scram()
        end

        local first_trip = ~was_tripped and self.tripped
    
        return self.tripped, status, first_trip
    end

    local trip_timeout = function ()
        self.tripped = false
        self.trip_cause = "timeout"
        self.timed_out = true
        self.reactor.scram()
    end

    local reset = function ()
        self.timed_out = false
        self.tripped = false
        self.trip_cause = ""
    end

    local status = function (named)
        if named then
            return {
                damage_critical = damage_critical(),
                excess_heated_coolant = excess_heated_coolant(),
                excess_waste = excess_waste(),
                high_temp = high_temp(),
                insufficient_fuel = insufficient_fuel(),
                no_coolant = no_coolant(),
                timed_out = timed_out()
            }
        else
            return {
                damage_critical(),
                excess_heated_coolant(),
                excess_waste(),
                high_temp(),
                insufficient_fuel(),
                no_coolant(),
                timed_out()
            }
        end
    end
    
    local damage_critical = function ()
        return self.reactor.getDamagePercent() >= 100
    end
    
    local excess_heated_coolant = function ()
        return self.reactor.getHeatedCoolantNeeded() == 0
    end
    
    local excess_waste = function ()
        return self.reactor.getWasteNeeded() == 0
    end

    local high_temp = function ()
        -- mekanism: MAX_DAMAGE_TEMPERATURE = 1_200
        return self.reactor.getTemperature() >= 1200
    end
    
    local insufficient_fuel = function ()
        return self.reactor.getFuel() == 0
    end

    local no_coolant = function ()
        return self.reactor.getCoolantFilledPercentage() < 2
    end

    local timed_out = function ()
        return self.timed_out
    end

    return {
        check = check,
        trip_timeout = trip_timeout,
        reset = reset,
        status = status,
        damage_critical = damage_critical,
        excess_heated_coolant = excess_heated_coolant,
        excess_waste = excess_waste,
        high_temp = high_temp,
        insufficient_fuel = insufficient_fuel,
        no_coolant = no_coolant,
        timed_out = timed_out
    }
end
