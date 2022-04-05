-- #REQUIRES comms.lua

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

    local reconnect_reactor = function (reactor)
        self.reactor = reactor
    end

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

        local first_trip = not was_tripped and self.tripped
    
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

function rplc_packet()
    local self = {
        frame = nil,
        id = nil,
        type = nil,
        length = nil,
        body = nil
    }

    local _rplc_type_valid = function ()
        return self.type == RPLC_TYPES.KEEP_ALIVE or
                self.type == RPLC_TYPES.LINK_REQ or
                self.type == RPLC_TYPES.STATUS or
                self.type == RPLC_TYPES.MEK_STRUCT or
                self.type == RPLC_TYPES.MEK_SCRAM or
                self.type == RPLC_TYPES.MEK_ENABLE or
                self.type == RPLC_TYPES.MEK_BURN_RATE or
                self.type == RPLC_TYPES.ISS_ALARM or
                self.type == RPLC_TYPES.ISS_GET or
                self.type == RPLC_TYPES.ISS_CLEAR
    end

    -- make an RPLC packet
    local make = function (id, packet_type, length, data)
        self.id = id
        self.type = packet_type
        self.length = length
        self.data = data
    end

    -- decode an RPLC packet from a SCADA frame
    local decode = function (frame)
        if frame then
            self.frame = frame
            
            if frame.protocol() == comms.PROTOCOLS.RPLC then
                local data = frame.data()
                local ok = #data > 2
    
                if ok then
                    make(data[1], data[2], data[3], { table.unpack(data, 4, #data) })
                    ok = _rplc_type_valid()
                end
    
                return ok
            else
                log._debug("attempted RPLC parse of incorrect protocol " .. frame.protocol(), true)
                return false    
            end
        else
            log._debug("nil frame encountered", true)
            return false
        end
    end

    local get = function ()
        return {
            scada_frame = self.frame,
            id = self.id,
            type = self.type,
            length = self.length,
            data = self.data
        }
    end

    return {
        make = make,
        decode = decode,
        get = get
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
        }
    end

    local _update_status_cache = function ()
        local status = _reactor_status()
        local changed = false

        for key, value in pairs(status) do
            if value ~= self.status_cache[key] then
                changed = true
                break
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

        local struct_packet = {
            id = self.id,
            type = RPLC_TYPES.MEK_STRUCT,
            mek_data = mek_data
        }

        _send(struct_packet)
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
                local rplc_pkt = rplc_packet()
                if rplc_pkt.decode(s_pkt) then
                    pkt = rplc_pkt.get()
                end
            -- get as SCADA management packet
            elseif s_pkt.protocol() == PROTOCOLS.SCADA_MGMT then
                local mgmt_pkt = mgmt_packet()
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
    local handle_packet = function (packet)
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
                            -- @todo: make sure this doesn't become an MITM security risk
                            print_ts("received unsolicited link denial, unlinking\n")
                            log._debug("unsolicited rplc link request denied")
                        elseif link_ack == RPLC_LINKING.COLLISION then
                            -- @todo: make sure this doesn't become an MITM security risk
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
                        _send_ack(packet.type, self.reactor.scram())
                    elseif packet.type == RPLC_TYPES.MEK_ENABLE then
                        -- enable the reactor
                        self.scrammed = false
                        _send_ack(packet.type, self.reactor.activate())
                    elseif packet.type == RPLC_TYPES.MEK_BURN_RATE then
                        -- set the burn rate
                        local burn_rate = packet.data[1]
                        local max_burn_rate = self.reactor.getMaxBurnRate()
                        local success = false

                        if max_burn_rate ~= nil then
                            if burn_rate > 0 and burn_rate <= max_burn_rate then
                                success = self.reactor.setBurnRate(burn_rate)
                            end
                        end

                        _send_ack(packet.type, success)
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
                    log._("discarding non-link packet before linked")
                end
            elseif packet.scada_frame.protocol() == PROTOCOLS.SCADA_MGMT then
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
    local send_status = function (overridden)
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
