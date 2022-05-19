local comms = require("scada-common.comms")
local log = require("scada-common.log")
local ppm = require("scada-common.ppm")
local types = require("scada-common.types")
local util = require("scada-common.util")

local plc = {}

local rps_status_t = types.rps_status_t

local PROTOCOLS = comms.PROTOCOLS
local RPLC_TYPES = comms.RPLC_TYPES
local RPLC_LINKING = comms.RPLC_LINKING
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

--- RPS: Reactor Protection System
---
--- identifies dangerous states and SCRAMs reactor if warranted
---
--- autonomous from main SCADA supervisor/coordinator control
plc.rps_init = function (reactor)
    local state_keys = {
        dmg_crit = 1,
        high_temp = 2,
        no_coolant = 3,
        ex_waste = 4,
        ex_hcoolant = 5,
        no_fuel = 6,
        fault = 7,
        timeout = 8,
        manual = 9
    }

    local self = {
        reactor = reactor,
        state = { false, false, false, false, false, false, false, false, false },
        reactor_enabled = false,
        tripped = false,
        trip_cause = ""
    }

    ---@class rps
    local public = {}

    -- PRIVATE FUNCTIONS --

    -- set reactor access fault flag
    local _set_fault = function ()
        if self.reactor.__p_last_fault() ~= "Terminated" then
            self.state[state_keys.fault] = true
        end
    end

    -- clear reactor access fault flag
    local _clear_fault = function ()
        self.state[state_keys.fault] = false
    end

    -- check for critical damage
    local _damage_critical = function ()
        local damage_percent = self.reactor.getDamagePercent()
        if damage_percent == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log.error("RPS: failed to check reactor damage")
            _set_fault()
            self.state[state_keys.dmg_crit] = false
        else
            self.state[state_keys.dmg_crit] = damage_percent >= 100
        end
    end

    -- check if the reactor is at a critically high temperature
    local _high_temp = function ()
        -- mekanism: MAX_DAMAGE_TEMPERATURE = 1_200
        local temp = self.reactor.getTemperature()
        if temp == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log.error("RPS: failed to check reactor temperature")
            _set_fault()
            self.state[state_keys.high_temp] = false
        else
            self.state[state_keys.high_temp] = temp >= 1200
        end
    end

    -- check if there is no coolant (<2% filled)
    local _no_coolant = function ()
        local coolant_filled = self.reactor.getCoolantFilledPercentage()
        if coolant_filled == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log.error("RPS: failed to check reactor coolant level")
            _set_fault()
            self.state[state_keys.no_coolant] = false
        else
            self.state[state_keys.no_coolant] = coolant_filled < 0.02
        end
    end

    -- check for excess waste (>80% filled)
    local _excess_waste = function ()
        local w_filled = self.reactor.getWasteFilledPercentage()
        if w_filled == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log.error("RPS: failed to check reactor waste level")
            _set_fault()
            self.state[state_keys.ex_waste] = false
        else
            self.state[state_keys.ex_waste] = w_filled > 0.8
        end
    end

    -- check for heated coolant backup (>95% filled)
    local _excess_heated_coolant = function ()
        local hc_filled = self.reactor.getHeatedCoolantFilledPercentage()
        if hc_filled == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log.error("RPS: failed to check reactor heated coolant level")
            _set_fault()
            self.state[state_keys.ex_hcoolant] = false
        else
            self.state[state_keys.ex_hcoolant] = hc_filled > 0.95
        end
    end

    -- check if there is no fuel
    local _insufficient_fuel = function ()
        local fuel = self.reactor.getFuel()
        if fuel == ppm.ACCESS_FAULT then
            -- lost the peripheral or terminated, handled later
            log.error("RPS: failed to check reactor fuel")
            _set_fault()
            self.state[state_keys.no_fuel] = false
        else
            self.state[state_keys.no_fuel] = fuel == 0
        end
    end

    -- PUBLIC FUNCTIONS --

    -- re-link a reactor after a peripheral re-connect
---@diagnostic disable-next-line: redefined-local
    public.reconnect_reactor = function (reactor)
        self.reactor = reactor
    end

    -- trip for lost peripheral
    public.trip_fault = function ()
        _set_fault()
    end

    -- trip for a PLC comms timeout
    public.trip_timeout = function ()
        self.state[state_keys.timed_out] = true
    end

    -- manually SCRAM the reactor
    public.trip_manual = function ()
        self.state[state_keys.manual]  = true
    end

    -- SCRAM the reactor now
    ---@return boolean success
    public.scram = function ()
        log.info("RPS: reactor SCRAM")

        self.reactor.scram()
        if self.reactor.__p_is_faulted() then
            log.error("RPS: failed reactor SCRAM")
            return false
        else
            self.reactor_enabled = false
            return true
        end
    end

    -- start the reactor
    ---@return boolean success
    public.activate = function ()
        if not self.tripped then
            log.info("RPS: reactor start")

            self.reactor.activate()
            if self.reactor.__p_is_faulted() then
                log.error("RPS: failed reactor start")
            else
                self.reactor_enabled = true
                return true
            end
        end

        return false
    end

    -- check all safety conditions
    ---@return boolean tripped, rps_status_t trip_status, boolean first_trip
    public.check = function ()
        local status = rps_status_t.ok
        local was_tripped = self.tripped
        local first_trip = false

        -- update state
        parallel.waitForAll(
            _damage_critical,
            _high_temp,
            _no_coolant,
            _excess_waste,
            _excess_heated_coolant,
            _insufficient_fuel
        )

        -- check system states in order of severity
        if self.tripped then
            status = self.trip_cause
        elseif self.state[state_keys.dmg_crit] then
            log.warning("RPS: damage critical")
            status = rps_status_t.dmg_crit
        elseif self.state[state_keys.high_temp] then
            log.warning("RPS: high temperature")
            status = rps_status_t.high_temp
        elseif self.state[state_keys.no_coolant] then
            log.warning("RPS: no coolant")
            status = rps_status_t.no_coolant
        elseif self.state[state_keys.ex_waste] then
            log.warning("RPS: full waste")
            status = rps_status_t.ex_waste
        elseif self.state[state_keys.ex_hcoolant] then
            log.warning("RPS: heated coolant backup")
            status = rps_status_t.ex_hcoolant
        elseif self.state[state_keys.no_fuel] then
            log.warning("RPS: no fuel")
            status = rps_status_t.no_fuel
        elseif self.state[state_keys.fault] then
            log.warning("RPS: reactor access fault")
            status = rps_status_t.fault
        elseif self.state[state_keys.timeout] then
            log.warning("RPS: supervisor connection timeout")
            status = rps_status_t.timeout
        elseif self.state[state_keys.manual] then
            log.warning("RPS: manual SCRAM requested")
            status = rps_status_t.manual
        else
            self.tripped = false
        end

        -- if a new trip occured...
        if (not was_tripped) and (status ~= rps_status_t.ok) then
            first_trip = true
            self.tripped = true
            self.trip_cause = status

            public.scram()
        end

        return self.tripped, status, first_trip
    end

    public.status = function () return self.state end
    public.is_tripped = function () return self.tripped end
    public.is_active = function () return self.reactor_enabled end

    -- reset the RPS
    public.reset = function ()
        self.tripped = false
        self.trip_cause = rps_status_t.ok

        for i = 1, #self.state do
            self.state[i] = false
        end
    end

    return public
end

-- Reactor PLC Communications
---@param id integer
---@param version string
---@param modem table
---@param local_port integer
---@param server_port integer
---@param reactor table
---@param rps rps
---@param conn_watchdog watchdog
plc.comms = function (id, version, modem, local_port, server_port, reactor, rps, conn_watchdog)
    local self = {
        id = id,
        version = version,
        seq_num = 0,
        r_seq_num = nil,
        modem = modem,
        s_port = server_port,
        l_port = local_port,
        reactor = reactor,
        rps = rps,
        conn_watchdog = conn_watchdog,
        scrammed = false,
        linked = false,
        status_cache = nil,
        max_burn_rate = nil
    }

    ---@class plc_comms
    local public = {}

    -- open modem
    if not self.modem.isOpen(self.l_port) then
        self.modem.open(self.l_port)
    end

    -- PRIVATE FUNCTIONS --

    -- send an RPLC packet
    ---@param msg_type RPLC_TYPES
    ---@param msg string
    local _send = function (msg_type, msg)
        local s_pkt = comms.scada_packet()
        local r_pkt = comms.rplc_packet()

        r_pkt.make(self.id, msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.RPLC, r_pkt.raw_sendable())

        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- send a SCADA management packet
    ---@param msg_type SCADA_MGMT_TYPES
    ---@param msg string
    local _send_mgmt = function (msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.SCADA_MGMT, m_pkt.raw_sendable())

        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- variable reactor status information, excluding heating rate
    ---@return table data_table, boolean faulted
    local _reactor_status = function ()
        local coolant = nil
        local hcoolant = nil

        local data_table = {
            false, -- getStatus
            0,     -- getBurnRate
            0,     -- getActualBurnRate
            0,     -- getTemperature
            0,     -- getDamagePercent
            0,     -- getBoilEfficiency
            0,     -- getEnvironmentalLoss
            0,     -- getFuel
            0,     -- getFuelFilledPercentage
            0,     -- getWaste
            0,     -- getWasteFilledPercentage
            "",    -- coolant_name
            0,     -- coolant_amnt
            0,     -- getCoolantFilledPercentage
            "",    -- hcoolant_name
            0,     -- hcoolant_amnt
            0      -- getHeatedCoolantFilledPercentage
        }

        local tasks = {
            function () data_table[1]  = self.reactor.getStatus() end,
            function () data_table[2]  = self.reactor.getBurnRate() end,
            function () data_table[3]  = self.reactor.getActualBurnRate() end,
            function () data_table[4]  = self.reactor.getTemperature() end,
            function () data_table[5]  = self.reactor.getDamagePercent() end,
            function () data_table[6]  = self.reactor.getBoilEfficiency() end,
            function () data_table[7]  = self.reactor.getEnvironmentalLoss() end,
            function () data_table[8]  = self.reactor.getFuel() end,
            function () data_table[9]  = self.reactor.getFuelFilledPercentage() end,
            function () data_table[10] = self.reactor.getWaste() end,
            function () data_table[11] = self.reactor.getWasteFilledPercentage() end,
            function () coolant        = self.reactor.getCoolant() end,
            function () data_table[14] = self.reactor.getCoolantFilledPercentage() end,
            function () hcoolant       = self.reactor.getHeatedCoolant() end,
            function () data_table[17] = self.reactor.getHeatedCoolantFilledPercentage() end
        }

        parallel.waitForAll(table.unpack(tasks))

        if coolant ~= nil then
            data_table[12] = coolant.name
            data_table[13] = coolant.amount
        end

        if hcoolant ~= nil then
            data_table[15] = hcoolant.name
            data_table[16] = hcoolant.amount
        end

        return data_table, self.reactor.__p_is_faulted()
    end

    -- update the status cache if changed
    ---@return boolean changed
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

        if changed and not faulted then
            self.status_cache = status
        end

        return changed
    end

    -- keep alive ack
    ---@param srv_time integer
    local _send_keep_alive_ack = function (srv_time)
        _send(SCADA_MGMT_TYPES.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- general ack
    ---@param msg_type RPLC_TYPES
    ---@param succeeded boolean
    local _send_ack = function (msg_type, succeeded)
        _send(msg_type, { succeeded })
    end

    -- send structure properties (these should not change, server will cache these)
    local _send_struct = function ()
        local mek_data = { 0, 0, 0, 0, 0, 0, 0, 0 }

        local tasks = {
            function () mek_data[1] = self.reactor.getHeatCapacity() end,
            function () mek_data[2] = self.reactor.getFuelAssemblies() end,
            function () mek_data[3] = self.reactor.getFuelSurfaceArea() end,
            function () mek_data[4] = self.reactor.getFuelCapacity() end,
            function () mek_data[5] = self.reactor.getWasteCapacity() end,
            function () mek_data[6] = self.reactor.getCoolantCapacity() end,
            function () mek_data[7] = self.reactor.getHeatedCoolantCapacity() end,
            function () mek_data[8] = self.reactor.getMaxBurnRate() end
        }

        parallel.waitForAll(table.unpack(tasks))

        if not self.reactor.__p_is_faulted() then
            _send(RPLC_TYPES.MEK_STRUCT, mek_data)
        else
            log.error("failed to send structure: PPM fault")
        end
    end

    -- PUBLIC FUNCTIONS --

    -- reconnect a newly connected modem
    ---@param modem table
---@diagnostic disable-next-line: redefined-local
    public.reconnect_modem = function (modem)
        self.modem = modem

        -- open modem
        if not self.modem.isOpen(self.l_port) then
            self.modem.open(self.l_port)
        end
    end

    -- reconnect a newly connected reactor
    ---@param reactor table
---@diagnostic disable-next-line: redefined-local
    public.reconnect_reactor = function (reactor)
        self.reactor = reactor
        self.status_cache = nil
    end

    -- unlink from the server
    public.unlink = function ()
        self.linked = false
        self.r_seq_num = nil
        self.status_cache = nil
    end

    -- close the connection to the server
    public.close = function ()
        self.conn_watchdog.cancel()
        public.unlink()
        _send_mgmt(SCADA_MGMT_TYPES.CLOSE, {})
    end

    -- attempt to establish link with supervisor
    public.send_link_req = function ()
        _send(RPLC_TYPES.LINK_REQ, { self.id, self.version })
    end

    -- send live status information
    ---@param degraded boolean
    public.send_status = function (degraded)
        if self.linked then
            local mek_data = nil

            if _update_status_cache() then
                mek_data = self.status_cache
            end

            local sys_status = {
                util.time(),                    -- timestamp
                (not self.scrammed),            -- requested control state
                rps.is_tripped(),               -- overridden
                degraded,                       -- degraded
                self.reactor.getHeatingRate(),  -- heating rate
                mek_data                        -- mekanism status data
            }

            if not self.reactor.__p_is_faulted() then
                _send(RPLC_TYPES.STATUS, sys_status)
            else
                log.error("failed to send status: PPM fault")
            end
        end
    end

    -- send reactor protection system status
    public.send_rps_status = function ()
        if self.linked then
            _send(RPLC_TYPES.RPS_STATUS, rps.status())
        end
    end

    -- send reactor protection system alarm
    ---@param cause rps_status_t
    public.send_rps_alarm = function (cause)
        if self.linked then
            local rps_alarm = {
                cause,
                table.unpack(rps.status())
            }

            _send(RPLC_TYPES.RPS_ALARM, rps_alarm)
        end
    end

    -- parse an RPLC packet
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return rplc_frame|mgmt_frame|nil packet
    public.parse_packet = function(side, sender, reply_to, message, distance)
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
                    pkt = mgmt_pkt.get()
                end
            else
                log.error("illegal packet type " .. s_pkt.protocol(), true)
            end
        end

        return pkt
    end

    -- handle an RPLC packet
    ---@param packet rplc_frame|mgmt_frame
    ---@param plc_state plc_state
    ---@param setpoints setpoints
    public.handle_packet = function (packet, plc_state, setpoints)
        if packet ~= nil then
            -- check sequence number
            if self.r_seq_num == nil then
                self.r_seq_num = packet.scada_frame.seq_num()
            elseif self.linked and self.r_seq_num >= packet.scada_frame.seq_num() then
                log.warning("sequence out-of-order: last = " .. self.r_seq_num .. ", new = " .. packet.scada_frame.seq_num())
                return
            else
                self.r_seq_num = packet.scada_frame.seq_num()
            end

            -- feed the watchdog first so it doesn't uhh...eat our packets :)
            self.conn_watchdog.feed()

            local protocol = packet.scada_frame.protocol()

            -- handle packet
            if protocol == PROTOCOLS.RPLC then
                if self.linked then
                    if packet.type == RPLC_TYPES.LINK_REQ then
                        -- link request confirmation
                        if packet.length == 1 then
                            log.debug("received unsolicited link request response")

                            local link_ack = packet.data[1]

                            if link_ack == RPLC_LINKING.ALLOW then
                                self.status_cache = nil
                                _send_struct()
                                public.send_status(plc_state.degraded)
                                log.debug("re-sent initial status data")
                            elseif link_ack == RPLC_LINKING.DENY then
                                println_ts("received unsolicited link denial, unlinking")
                                log.debug("unsolicited RPLC link request denied")
                            elseif link_ack == RPLC_LINKING.COLLISION then
                                println_ts("received unsolicited link collision, unlinking")
                                log.warning("unsolicited RPLC link request collision")
                            else
                                println_ts("invalid unsolicited link response")
                                log.error("unsolicited unknown RPLC link request response")
                            end

                            self.linked = link_ack == RPLC_LINKING.ALLOW
                        else
                            log.debug("RPLC link req packet length mismatch")
                        end
                    elseif packet.type == RPLC_TYPES.STATUS then
                        -- request of full status, clear cache first
                        self.status_cache = nil
                        public.send_status(plc_state.degraded)
                        log.debug("sent out status cache again, did supervisor miss it?")
                    elseif packet.type == RPLC_TYPES.MEK_STRUCT then
                        -- request for physical structure
                        _send_struct()
                        log.debug("sent out structure again, did supervisor miss it?")
                    elseif packet.type == RPLC_TYPES.MEK_BURN_RATE then
                        -- set the burn rate
                        if packet.length == 2 then
                            local success = false
                            local burn_rate = packet.data[1]
                            local ramp = packet.data[2]

                            -- if no known max burn rate, check again
                            if self.max_burn_rate == nil then
                                self.max_burn_rate = self.reactor.getMaxBurnRate()
                            end

                            -- if we know our max burn rate, update current burn rate setpoint if in range
                            if self.max_burn_rate ~= ppm.ACCESS_FAULT then
                                if burn_rate > 0 and burn_rate <= self.max_burn_rate then
                                    if ramp then
                                        setpoints.burn_rate_en = true
                                        setpoints.burn_rate = burn_rate
                                        success = true
                                    else
                                        self.reactor.setBurnRate(burn_rate)
                                        success = not self.reactor.__p_is_faulted()
                                    end
                                end
                            end

                            _send_ack(packet.type, success)
                        else
                            log.debug("RPLC set burn rate packet length mismatch")
                        end
                    elseif packet.type == RPLC_TYPES.RPS_ENABLE then
                        -- enable the reactor
                        self.scrammed = false
                        _send_ack(packet.type, self.rps.activate())
                    elseif packet.type == RPLC_TYPES.RPS_SCRAM then
                        -- disable the reactor
                        self.scrammed = true
                        self.rps.trip_manual()
                        _send_ack(packet.type, true)
                    elseif packet.type == RPLC_TYPES.RPS_RESET then
                        -- reset the RPS status
                        rps.reset()
                        _send_ack(packet.type, true)
                    else
                        log.warning("received unknown RPLC packet type " .. packet.type)
                    end
                elseif packet.type == RPLC_TYPES.LINK_REQ then
                    -- link request confirmation
                    if packet.length == 1 then
                        local link_ack = packet.data[1]

                        if link_ack == RPLC_LINKING.ALLOW then
                            println_ts("linked!")
                            log.debug("RPLC link request approved")

                            -- reset remote sequence number and cache
                            self.r_seq_num = nil
                            self.status_cache = nil

                            _send_struct()
                            public.send_status(plc_state.degraded)

                            log.debug("sent initial status data")
                        elseif link_ack == RPLC_LINKING.DENY then
                            println_ts("link request denied, retrying...")
                            log.debug("RPLC link request denied")
                        elseif link_ack == RPLC_LINKING.COLLISION then
                            println_ts("reactor PLC ID collision (check config), retrying...")
                            log.warning("RPLC link request collision")
                        else
                            println_ts("invalid link response, bad channel? retrying...")
                            log.error("unknown RPLC link request response")
                        end

                        self.linked = link_ack == RPLC_LINKING.ALLOW
                    else
                        log.debug("RPLC link req packet length mismatch")
                    end
                else
                    log.debug("discarding non-link packet before linked")
                end
            elseif protocol == PROTOCOLS.SCADA_MGMT then
                if packet.type == SCADA_MGMT_TYPES.KEEP_ALIVE then
                    -- keep alive request received, echo back
                    if packet.length == 1 then
                        local timestamp = packet.data[1]
                        local trip_time = util.time() - timestamp

                        if trip_time > 500 then
                            log.warning("PLC KEEP_ALIVE trip time > 500ms (" .. trip_time .. "ms)")
                        end

                        -- log.debug("RPLC RTT = ".. trip_time .. "ms")

                        _send_keep_alive_ack(timestamp)
                    else
                        log.debug("SCADA keep alive packet length mismatch")
                    end
                elseif packet.type == SCADA_MGMT_TYPES.CLOSE then
                    -- handle session close
                    self.conn_watchdog.cancel()
                    public.unlink()
                    println_ts("server connection closed by remote host")
                    log.warning("server connection closed by remote host")
                else
                    log.warning("received unknown SCADA_MGMT packet type " .. packet.type)
                end
            else
                -- should be unreachable assuming packet is from parse_packet()
                log.error("illegal packet type " .. protocol, true)
            end
        end
    end

    public.is_scrammed = function () return self.scrammed end
    public.is_linked = function () return self.linked end

    return public
end

return plc
