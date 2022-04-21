-- #REQUIRES comms.lua
-- #REQUIRES ppm.lua

local PROTOCOLS = comms.PROTOCOLS
local RPLC_TYPES = comms.RPLC_TYPES
local RPLC_LINKING = comms.RPLC_LINKING

-- Internal Safety System
-- identifies dangerous states and SCRAMs reactor if warranted
-- autonomous from main SCADA supervisor/coordinator control
function iss_init(reactor)
    local self = {
        reactor = reactor,
        timed_out = false,
        tripped = false,
        trip_cause = ""
    }

    -- re-link a reactor after a peripheral re-connect
    local reconnect_reactor = function (reactor)
        self.reactor = reactor
    end

    -- check for critical damage
    local damage_critical = function ()
        local damage_percent = self.reactor.getDamagePercent()
        if damage_percent == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log._error("ISS: failed to check reactor damage")
            return false
        else
            return damage_percent >= 100
        end
    end

    -- check for heated coolant backup
    local excess_heated_coolant = function ()
        local hc_needed = self.reactor.getHeatedCoolantNeeded()
        if hc_needed == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log._error("ISS: failed to check reactor heated coolant level")
            return false
        else
            return hc_needed == 0
        end
    end

    -- check for excess waste
    local excess_waste = function ()
        local w_needed = self.reactor.getWasteNeeded()
        if w_needed == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log._error("ISS: failed to check reactor waste level")
            return false
        else
            return w_needed == 0
        end
    end

    -- check if the reactor is at a critically high temperature
    local high_temp = function ()
        -- mekanism: MAX_DAMAGE_TEMPERATURE = 1_200
        local temp = self.reactor.getTemperature()
        if temp == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log._error("ISS: failed to check reactor temperature")
            return false
        else
            return temp >= 1200
        end
    end

    -- check if there is no fuel
    local insufficient_fuel = function ()
        local fuel = self.reactor.getFuel()
        if fuel == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log._error("ISS: failed to check reactor fuel level")
            return false
        else
            return fuel == 0
        end
    end

    -- check if there is no coolant
    local no_coolant = function ()
        local coolant_filled = self.reactor.getCoolantFilledPercentage()
        if coolant_filled == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log._error("ISS: failed to check reactor coolant level")
            return false
        else
            return coolant_filled < 2
        end
    end

    -- if PLC timed out
    local timed_out = function ()
        return self.timed_out
    end

    -- check all safety conditions
    local check = function ()
        local status = "ok"
        local was_tripped = self.tripped
        
        -- check system states in order of severity
        if damage_critical() then
            log._warning("ISS: damage critical!")
            status = "dmg_crit"
        elseif high_temp() then
            log._warning("ISS: high temperature!")
            status = "high_temp"
        elseif excess_heated_coolant() then
            log._warning("ISS: heated coolant backup!")
            status = "heated_coolant_backup"
        elseif excess_waste() then
            log._warning("ISS: full waste!")
            status = "full_waste"
        elseif insufficient_fuel() then
            log._warning("ISS: no fuel!")
            status = "no_fuel"
        elseif self.tripped then
            status = self.trip_cause
        else
            self.tripped = false
        end
    
        -- if a new trip occured...
        if status ~= "ok" then
            log._warning("ISS: reactor SCRAM")
            self.tripped = true
            self.trip_cause = status
            if self.reactor.scram() == ppm.ACCESS_FAULT then
                log._error("ISS: failed reactor SCRAM")
            end
        end

        local first_trip = not was_tripped and self.tripped
    
        return self.tripped, status, first_trip
    end

    -- report a PLC comms timeout
    local trip_timeout = function ()
        self.tripped = false
        self.trip_cause = "timeout"
        self.timed_out = true
        self.reactor.scram()
    end

    -- reset the ISS
    local reset = function ()
        self.timed_out = false
        self.tripped = false
        self.trip_cause = ""
    end

    -- get the ISS status
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

    return {
        reconnect_reactor = reconnect_reactor,
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

-- reactor PLC communications
function comms_init(id, modem, local_port, server_port, reactor, iss)
    local self = {
        id = id,
        seq_num = 0,
        modem = modem,
        s_port = server_port,
        l_port = local_port,
        reactor = reactor,
        iss = iss,
        status_cache = nil,
        scrammed = false,
        linked = false
    }

    -- open modem
    if not self.modem.isOpen(self.l_port) then
        self.modem.open(self.l_port)
    end

    -- PRIVATE FUNCTIONS --

    local _send = function (msg)
        local packet = scada_packet()
        packet.make(self.seq_num, PROTOCOLS.RPLC, msg)
        self.modem.transmit(self.s_port, self.l_port, packet.raw())
        self.seq_num = self.seq_num + 1
    end

    -- variable reactor status information, excluding heating rate
    local _reactor_status = function ()
        ppm.clear_fault()
        return {
            status     = self.reactor.getStatus(),
            burn_rate  = self.reactor.getBurnRate(),
            act_burn_r = self.reactor.getActualBurnRate(),
            temp       = self.reactor.getTemperature(),
            damage     = self.reactor.getDamagePercent(),
            boil_eff   = self.reactor.getBoilEfficiency(),
            env_loss   = self.reactor.getEnvironmentalLoss(),

            fuel       = self.reactor.getFuel(),
            fuel_need  = self.reactor.getFuelNeeded(),
            fuel_fill  = self.reactor.getFuelFilledPercentage(),
            waste      = self.reactor.getWaste(),
            waste_need = self.reactor.getWasteNeeded(),
            waste_fill = self.reactor.getWasteFilledPercentage(),
            cool_type  = self.reactor.getCoolant()['name'],
            cool_amnt  = self.reactor.getCoolant()['amount'],
            cool_need  = self.reactor.getCoolantNeeded(),
            cool_fill  = self.reactor.getCoolantFilledPercentage(),
            hcool_type = self.reactor.getHeatedCoolant()['name'],
            hcool_amnt = self.reactor.getHeatedCoolant()['amount'],
            hcool_need = self.reactor.getHeatedCoolantNeeded(),
            hcool_fill = self.reactor.getHeatedCoolantFilledPercentage()
        }, ppm.faulted()
    end

    local _update_status_cache = function ()
        local status, faulted = _reactor_status()
        local changed = false

        if not faulted then
            for key, value in pairs(status) do
                if value ~= self.status_cache[key] then
                    changed = true
                    break
                end
            end
        end

        if changed then
            self.status_cache = status
        end

        return changed
    end

    -- keep alive ack
    local _send_keep_alive_ack = function ()
        local keep_alive_data = {
            id = self.id,
            timestamp = os.time(),
            type = RPLC_TYPES.KEEP_ALIVE
        }

        _send(keep_alive_data)
    end

    -- general ack
    local _send_ack = function (type, succeeded)
        local ack_data = {
            id = self.id,
            type = type,
            ack = succeeded
        }

        _send(ack_data)
    end

    -- send structure properties (these should not change)
    -- (server will cache these)
    local _send_struct = function ()
        ppm.clear_fault()
        local mek_data = {
            heat_cap  = self.reactor.getHeatCapacity(),
            fuel_asm  = self.reactor.getFuelAssemblies(),
            fuel_sa   = self.reactor.getFuelSurfaceArea(),
            fuel_cap  = self.reactor.getFuelCapacity(),
            waste_cap = self.reactor.getWasteCapacity(),
            cool_cap  = self.reactor.getCoolantCapacity(),
            hcool_cap = self.reactor.getHeatedCoolantCapacity(),
            max_burn  = self.reactor.getMaxBurnRate()
        }

        if not faulted then
            local struct_packet = {
                id = self.id,
                type = RPLC_TYPES.MEK_STRUCT,
                mek_data = mek_data
            }

            _send(struct_packet)
        else
            log._error("failed to send structure: PPM fault")
        end
    end

    local _send_iss_status = function ()
        local iss_status = {
            id = self.id,
            type = RPLC_TYPES.ISS_GET,
            status = iss.status()
        }

        _send(iss_status)
    end

    -- PUBLIC FUNCTIONS --

    -- reconnect a newly connected modem
    local reconnect_modem = function (modem)
        self.modem = modem

        -- open modem
        if not self.modem.isOpen(self.l_port) then
            self.modem.open(self.l_port)
        end
    end

    -- reconnect a newly connected reactor
    local reconnect_reactor = function (reactor)
        self.reactor = reactor
        _update_status_cache()
    end

    -- parse an RPLC packet
    local parse_packet = function(side, sender, reply_to, message, distance)
        local pkt = nil
        local s_pkt = scada_packet()

        -- parse packet as generic SCADA packet
        s_pkt.recieve(side, sender, reply_to, message, distance)

        if s_pkt.is_valid() then
            -- get as RPLC packet
            if s_pkt.protocol() == PROTOCOLS.RPLC then
                local rplc_pkt = comms.rplc_packet()
                if rplc_pkt.decode(s_pkt) then
                    pkt = rplc_pkt.get()
                end
            -- get as SCADA management packet
            elseif s_pkt.protocol() == PROTOCOLS.SCADA_MGMT then
                local mgmt_pkt = comms.mgmt_packet()
                if mgmt_pkt.decode(s_pkt) then
                    pkt = mgmt_packet.get()
                end
            else
                log._error("illegal packet type " .. s_pkt.protocol(), true)
            end
        end

        return pkt
    end

    -- handle an RPLC packet
    local handle_packet = function (packet, plc_state)
        if packet ~= nil then
            if packet.scada_frame.protocol() == PROTOCOLS.RPLC then
                if self.linked then
                    if packet.type == RPLC_TYPES.KEEP_ALIVE then
                        -- keep alive request received, echo back
                        local timestamp = packet.data[1]
                        local trip_time = os.time() - ts

                        if trip_time < 0 then
                            log._warning("PLC KEEP_ALIVE trip time less than 0 (" .. trip_time .. ")") 
                        elseif trip_time > 1 then
                            log._warning("PLC KEEP_ALIVE trip time > 1s (" .. trip_time .. ")")
                        end

                        _send_keep_alive_ack()
                    elseif packet.type == RPLC_TYPES.LINK_REQ then
                        -- link request confirmation
                        log._debug("received unsolicited link request response")

                        local link_ack = packet.data[1]
                        
                        if link_ack == RPLC_LINKING.ALLOW then
                            _send_struct()
                            send_status()
                            log._debug("re-sent initial status data")
                        elseif link_ack == RPLC_LINKING.DENY then
                            -- @todo: make sure this doesn't become a MITM security risk
                            print_ts("received unsolicited link denial, unlinking\n")
                            log._debug("unsolicited rplc link request denied")
                        elseif link_ack == RPLC_LINKING.COLLISION then
                            -- @todo: make sure this doesn't become a MITM security risk
                            print_ts("received unsolicited link collision, unlinking\n")
                            log._warning("unsolicited rplc link request collision")
                        else
                            print_ts("invalid unsolicited link response\n")
                            log._error("unsolicited unknown rplc link request response")
                        end

                        self.linked = link_ack == RPLC_LINKING.ALLOW
                    elseif packet.type == RPLC_TYPES.MEK_STRUCT then
                        -- request for physical structure
                        _send_struct()
                    elseif packet.type == RPLC_TYPES.MEK_SCRAM then
                        -- disable the reactor
                        self.scrammed = true
                        plc_state.scram = true
                        _send_ack(packet.type, self.reactor.scram() == ppm.ACCESS_OK)
                    elseif packet.type == RPLC_TYPES.MEK_ENABLE then
                        -- enable the reactor
                        self.scrammed = false
                        plc_state.scram = false
                        _send_ack(packet.type, self.reactor.activate() == ppm.ACCESS_OK)
                    elseif packet.type == RPLC_TYPES.MEK_BURN_RATE then
                        -- set the burn rate
                        local burn_rate = packet.data[1]
                        local max_burn_rate = self.reactor.getMaxBurnRate()
                        local success = false

                        if max_burn_rate ~= ppm.ACCESS_FAULT then
                            if burn_rate > 0 and burn_rate <= max_burn_rate then
                                success = self.reactor.setBurnRate(burn_rate)
                            end
                        end

                        _send_ack(packet.type, success == ppm.ACCESS_OK)
                    elseif packet.type == RPLC_TYPES.ISS_GET then
                        -- get the ISS status
                        _send_iss_status(iss.status())
                    elseif packet.type == RPLC_TYPES.ISS_CLEAR then
                        -- clear the ISS status
                        iss.reset()
                        _send_ack(packet.type, true)
                    else
                        log._warning("received unknown RPLC packet type " .. packet.type)
                    end
                elseif packet.type == RPLC_TYPES.LINK_REQ then
                    -- link request confirmation
                    local link_ack = packet.data[1]
                    
                    if link_ack == RPLC_LINKING.ALLOW then
                        print_ts("...linked!\n")
                        log._debug("rplc link request approved")

                        _send_struct()
                        send_status()

                        log._debug("sent initial status data")
                    elseif link_ack == RPLC_LINKING.DENY then
                        print_ts("...denied, retrying...\n")
                        log._debug("rplc link request denied")
                    elseif link_ack == RPLC_LINKING.COLLISION then
                        print_ts("reactor PLC ID collision (check config), retrying...\n")
                        log._warning("rplc link request collision")
                    else
                        print_ts("invalid link response, bad channel? retrying...\n")
                        log._error("unknown rplc link request response")
                    end

                    self.linked = link_ack == RPLC_LINKING.ALLOW
                else
                    log._debug("discarding non-link packet before linked")
                end
            elseif packet.scada_frame.protocol() == PROTOCOLS.SCADA_MGMT then
                -- todo
            end
        end
    end

    -- attempt to establish link with supervisor
    local send_link_req = function ()
        local linking_data = {
            id = self.id,
            type = RPLC_TYPES.LINK_REQ
        }

        _send(linking_data)
    end

    -- send live status information
    -- overridden : if ISS force disabled reactor
    -- degraded   : if PLC status is degraded
    local send_status = function (overridden, degraded)
        local mek_data = nil

        if _update_status_cache() then
            mek_data = self.status_cache
        end

        local sys_status = {
            id = self.id,
            type = RPLC_TYPES.STATUS,
            timestamp = os.time(),
            control_state = not self.scrammed,
            overridden = overridden,
            degraded = degraded,
            heating_rate = self.reactor.getHeatingRate(),
            mek_data = mek_data
        }

        _send(sys_status)
    end

    local send_iss_alarm = function (cause)
        local iss_alarm = {
            id = self.id,
            type = RPLC_TYPES.ISS_ALARM,
            cause = cause,
            status = iss.status()
        }

        _send(iss_alarm)
    end

    local is_scrammed = function () return self.scrammed end
    local is_linked = function () return self.linked end
    local unlink = function () self.linked = false end

    return {
        reconnect_modem = reconnect_modem,
        reconnect_reactor = reconnect_reactor,
        parse_packet = parse_packet,
        handle_packet = handle_packet,
        send_link_req = send_link_req,
        send_status = send_status,
        send_iss_alarm = send_iss_alarm,
        is_scrammed = is_scrammed,
        is_linked = is_linked,
        unlink = unlink
    }
end
