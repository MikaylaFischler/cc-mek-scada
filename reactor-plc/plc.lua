-- #REQUIRES comms.lua
-- #REQUIRES ppm.lua
-- #REQUIRES util.lua

local PROTOCOLS = comms.PROTOCOLS
local RPLC_TYPES = comms.RPLC_TYPES
local RPLC_LINKING = comms.RPLC_LINKING

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

-- Internal Safety System
-- identifies dangerous states and SCRAMs reactor if warranted
-- autonomous from main SCADA supervisor/coordinator control
function iss_init(reactor)
    local self = {
        reactor = reactor,
        cache = { false, false, false, false, false, false, false },
        timed_out = false,
        tripped = false,
        trip_cause = ""
    }

    -- PRIVATE FUNCTIONS --

    -- check for critical damage
    local _damage_critical = function ()
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
    local _excess_heated_coolant = function ()
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
    local _excess_waste = function ()
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
    local _high_temp = function ()
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
    local _insufficient_fuel = function ()
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
    local _no_coolant = function ()
        local coolant_filled = self.reactor.getCoolantFilledPercentage()
        if coolant_filled == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log._error("ISS: failed to check reactor coolant level")
            return false
        else
            return coolant_filled < 0.02
        end
    end

    -- PUBLIC FUNCTIONS --

    -- re-link a reactor after a peripheral re-connect
    local reconnect_reactor = function (reactor)
        self.reactor = reactor
    end

    -- report a PLC comms timeout
    local trip_timeout = function ()
        self.timed_out = true
    end

    -- check all safety conditions
    local check = function ()
        local status = "ok"
        local was_tripped = self.tripped

        -- update cache
        self.cache = {
            _damage_critical(),
            _excess_heated_coolant(),
            _excess_waste(),
            _high_temp(),
            _insufficient_fuel(),
            _no_coolant(),
            self.timed_out
        }
        
        -- check system states in order of severity
        if self.tripped then
            status = self.trip_cause
        elseif self.cache[1] then
            log._warning("ISS: damage critical!")
            status = "dmg_crit"
        elseif self.cache[4] then
            log._warning("ISS: high temperature!")
            status = "high_temp"
        elseif self.cache[2] then
            log._warning("ISS: heated coolant backup!")
            status = "heated_coolant_backup"
        elseif self.cache[6] then
            log._warning("ISS: no coolant!")
            status = "no_coolant"
        elseif self.cache[3] then
            log._warning("ISS: full waste!")
            status = "full_waste"
        elseif self.cache[5] then
            log._warning("ISS: no fuel!")
            status = "no_fuel"
        elseif self.timed_out then
            log._warning("ISS: supervisor connection timeout!")
            status = "timeout"
        else
            self.tripped = false
        end
    
        -- if a new trip occured...
        local first_trip = false
        if not was_tripped and status ~= "ok" then
            log._warning("ISS: reactor SCRAM")

            first_trip = true
            self.tripped = true
            self.trip_cause = status

            self.reactor.scram()
            if self.reactor.__p_is_faulted() then
                log._error("ISS: failed reactor SCRAM")
            end
        end
    
        return self.tripped, status, first_trip
    end

    -- get the ISS status
    local status = function () return self.cache end
    local is_tripped = function () return self.tripped end

    -- reset the ISS
    local reset = function ()
        self.timed_out = false
        self.tripped = false
        self.trip_cause = ""
    end

    return {
        reconnect_reactor = reconnect_reactor,
        trip_timeout = trip_timeout,
        check = check,
        status = status,
        is_tripped = is_tripped,
        reset = reset
    }
end

-- reactor PLC communications
function comms_init(id, modem, local_port, server_port, reactor, iss)
    local self = {
        id = id,
        seq_num = 0,
        r_seq_num = nil,
        modem = modem,
        s_port = server_port,
        l_port = local_port,
        reactor = reactor,
        iss = iss,
        scrammed = false,
        linked = false,
        status_cache = nil,
        max_burn_rate = nil
    }

    -- open modem
    if not self.modem.isOpen(self.l_port) then
        self.modem.open(self.l_port)
    end

    -- PRIVATE FUNCTIONS --

    local _send = function (msg_type, msg)
        local s_pkt = comms.scada_packet()
        local r_pkt = comms.rplc_packet()

        r_pkt.make(self.id, msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.RPLC, r_pkt.raw_sendable())

        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- variable reactor status information, excluding heating rate
    local _reactor_status = function ()
        return {
            self.reactor.getStatus(),
            self.reactor.getBurnRate(),
            self.reactor.getActualBurnRate(),
            self.reactor.getTemperature(),
            self.reactor.getDamagePercent(),
            self.reactor.getBoilEfficiency(),
            self.reactor.getEnvironmentalLoss(),

            self.reactor.getFuel(),
            self.reactor.getFuelNeeded(),
            self.reactor.getFuelFilledPercentage(),
            self.reactor.getWaste(),
            self.reactor.getWasteNeeded(),
            self.reactor.getWasteFilledPercentage(),
            self.reactor.getCoolant()['name'],
            self.reactor.getCoolant()['amount'],
            self.reactor.getCoolantNeeded(),
            self.reactor.getCoolantFilledPercentage(),
            self.reactor.getHeatedCoolant()['name'],
            self.reactor.getHeatedCoolant()['amount'],
            self.reactor.getHeatedCoolantNeeded(),
            self.reactor.getHeatedCoolantFilledPercentage()
        }, self.reactor.__p_is_faulted()
    end

    local _update_status_cache = function ()
        local status, faulted = _reactor_status()
        local changed = false

        if self.status_cache ~= nil then
            if not faulted then
                for i = 1, #status do
                    if status[i] ~= self.status_cache[i] then
                        changed = true
                        break
                    end
                end
            end
        else
            changed = true
        end

        if changed then
            self.status_cache = status
        end

        return changed
    end

    -- keep alive ack
    local _send_keep_alive_ack = function (srv_time)
        _send(RPLC_TYPES.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- general ack
    local _send_ack = function (msg_type, succeeded)
        _send(msg_type, { succeeded })
    end

    -- send structure properties (these should not change)
    -- (server will cache these)
    local _send_struct = function ()
        local mek_data = {
            self.reactor.getHeatCapacity(),
            self.reactor.getFuelAssemblies(),
            self.reactor.getFuelSurfaceArea(),
            self.reactor.getFuelCapacity(),
            self.reactor.getWasteCapacity(),
            self.reactor.getCoolantCapacity(),
            self.reactor.getHeatedCoolantCapacity(),
            self.reactor.getMaxBurnRate()
        }

        if not self.reactor.__p_is_faulted() then
            _send(RPLC_TYPES.MEK_STRUCT, mek_data)
        else
            log._error("failed to send structure: PPM fault")
        end
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

    -- attempt to establish link with supervisor
    local send_link_req = function ()
        _send(RPLC_TYPES.LINK_REQ, { self.id })
    end

    -- send live status information
    local send_status = function (degraded)
        local mek_data = nil

        if _update_status_cache() then
            mek_data = self.status_cache
        end

        local sys_status = {
            util.time(),
            (not self.scrammed),
            iss.is_tripped(),
            degraded,
            self.reactor.getHeatingRate(),
            mek_data
        }

        _send(RPLC_TYPES.STATUS, sys_status)
    end

    local send_iss_status = function ()
        _send(RPLC_TYPES.ISS_STATUS, iss.status())
    end

    local send_iss_alarm = function (cause)
        local iss_alarm = {
            cause,
            iss.status()
        }

        _send(RPLC_TYPES.ISS_ALARM, iss_alarm)
    end

    -- parse an RPLC packet
    local parse_packet = function(side, sender, reply_to, message, distance)
        local pkt = nil
        local s_pkt = comms.scada_packet()

        -- parse packet as generic SCADA packet
        s_pkt.receive(side, sender, reply_to, message, distance)

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
            -- check sequence number
            if self.r_seq_num == nil then
                self.r_seq_num = packet.scada_frame.seq_num()
            elseif self.linked and self.r_seq_num >= packet.scada_frame.seq_num() then
                log._warning("sequence out-of-order: last = " .. self.r_seq_num .. ", new = " .. packet.scada_frame.seq_num())
                return
            else
                self.r_seq_num = packet.scada_frame.seq_num()
            end

            -- handle packet
            if packet.scada_frame.protocol() == PROTOCOLS.RPLC then
                if self.linked then
                    if packet.type == RPLC_TYPES.KEEP_ALIVE then
                        -- keep alive request received, echo back
                        local timestamp = packet.data[1]
                        local trip_time = util.time() - timestamp

                        if trip_time < 0 then
                            log._warning("PLC KEEP_ALIVE trip time less than 0 (" .. trip_time .. ")") 
                        elseif trip_time > 1000 then
                            log._warning("PLC KEEP_ALIVE trip time > 1s (" .. trip_time .. ")")
                        end

                        _send_keep_alive_ack(timestamp)
                    elseif packet.type == RPLC_TYPES.LINK_REQ then
                        -- link request confirmation
                        log._debug("received unsolicited link request response")

                        local link_ack = packet.data[1]
                        
                        if link_ack == RPLC_LINKING.ALLOW then
                            _send_struct()
                            send_status(plc_state.degraded)
                            log._debug("re-sent initial status data")
                        elseif link_ack == RPLC_LINKING.DENY then
                            -- @todo: make sure this doesn't become a MITM security risk
                            println_ts("received unsolicited link denial, unlinking")
                            log._debug("unsolicited RPLC link request denied")
                        elseif link_ack == RPLC_LINKING.COLLISION then
                            -- @todo: make sure this doesn't become a MITM security risk
                            println_ts("received unsolicited link collision, unlinking")
                            log._warning("unsolicited RPLC link request collision")
                        else
                            println_ts("invalid unsolicited link response")
                            log._error("unsolicited unknown RPLC link request response")
                        end

                        self.linked = link_ack == RPLC_LINKING.ALLOW
                    elseif packet.type == RPLC_TYPES.MEK_STRUCT then
                        -- request for physical structure
                        _send_struct()
                    elseif packet.type == RPLC_TYPES.MEK_SCRAM then
                        -- disable the reactor
                        self.scrammed = true
                        plc_state.scram = true
                        self.reactor.scram()
                        _send_ack(packet.type, self.reactor.__p_is_ok())
                    elseif packet.type == RPLC_TYPES.MEK_ENABLE then
                        -- enable the reactor
                        self.scrammed = false
                        plc_state.scram = false
                        self.reactor.activate()
                        _send_ack(packet.type, self.reactor.__p_is_ok())
                    elseif packet.type == RPLC_TYPES.MEK_BURN_RATE then
                        -- set the burn rate
                        local success = false
                        local burn_rate = packet.data[1]
                        local max_burn_rate = self.max_burn_rate

                        -- if no known max burn rate, check again
                        if max_burn_rate == nil then
                            max_burn_rate = self.reactor.getMaxBurnRate()
                            self.max_burn_rate = max_burn_rate
                        end

                        -- if we know our max burn rate, update current burn rate if in range
                        if max_burn_rate ~= ppm.ACCESS_FAULT then
                            if burn_rate > 0 and burn_rate <= max_burn_rate then
                                self.reactor.setBurnRate(burn_rate)
                                success = self.reactor.__p_is_ok()
                            end
                        end

                        _send_ack(packet.type, success)
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
                        println_ts("linked!")
                        log._debug("RPLC link request approved")

                        -- reset remote sequence number
                        self.r_seq_num = nil

                        _send_struct()
                        send_status(plc_state.degraded)

                        log._debug("sent initial status data")
                    elseif link_ack == RPLC_LINKING.DENY then
                        println_ts("link request denied, retrying...")
                        log._debug("RPLC link request denied")
                    elseif link_ack == RPLC_LINKING.COLLISION then
                        println_ts("reactor PLC ID collision (check config), retrying...")
                        log._warning("RPLC link request collision")
                    else
                        println_ts("invalid link response, bad channel? retrying...")
                        log._error("unknown RPLC link request response")
                    end

                    self.linked = link_ack == RPLC_LINKING.ALLOW
                else
                    log._debug("discarding non-link packet before linked")
                end
            elseif packet.scada_frame.protocol() == PROTOCOLS.SCADA_MGMT then
                -- @todo
            end
        end
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
        send_iss_status = send_iss_status,
        send_iss_alarm = send_iss_alarm,
        is_scrammed = is_scrammed,
        is_linked = is_linked,
        unlink = unlink
    }
end
