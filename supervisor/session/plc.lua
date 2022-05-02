-- #REQUIRES mqueue.lua
-- #REQUIRES comms.lua
-- #REQUIRES log.lua
-- #REQUIRES util.lua

local PROTOCOLS = comms.PROTOCOLS
local RPLC_TYPES = comms.RPLC_TYPES
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES

-- retry time constants in ms
local INITIAL_WAIT = 1500
local RETRY_PERIOD = 1000

PLC_S_CMDS = {
    SCRAM = 0,
    ENABLE = 1,
    BURN_RATE = 2,
    ISS_CLEAR = 3
}

local PERIODICS = {
    KEEP_ALIVE = 2.0
}

-- PLC supervisor session
function new_session(id, for_reactor, in_queue, out_queue)
    local log_header = "plc_session(" .. id .. "): "

    local self = {
        id = id,
        for_reactor = for_reactor,
        in_q = in_queue,
        out_q = out_queue,
        commanded_state = false,
        commanded_burn_rate = 0.0,
        -- connection properties
        seq_num = 0,
        r_seq_num = nil,
        connected = true,
        received_struct = false,
        plc_conn_watchdog = util.new_watchdog(3),
        last_rtt = 0,
        -- periodic messages
        periodics = {
            last_update = 0,
            keep_alive = 0
        },
        -- when to next retry one of these requests
        retry_times = {
            struct_req = (util.time() + 500),
            scram_req = 0,
            enable_req = 0,
            burn_rate_req = 0,
            iss_clear_req = 0
        },
        -- command acknowledgements
        acks = {
            scram = true,
            enable = true,
            burn_rate = true,
            iss_clear = true
        },
        -- session database
        sDB = {
            last_status_update = 0,
            control_state = false,
            overridden = false,
            degraded = false,
            iss_tripped = false,
            iss_trip_cause = "ok",
            iss_status = {
                dmg_crit = false,
                ex_hcool = false,
                ex_waste = false,
                high_temp = false,
                no_fuel = false,
                no_cool = false,
                timed_out = false
            },
            mek_status = {
                heating_rate = 0,

                status = false,
                burn_rate = 0,
                act_burn_rate = 0,
                temp = 0,
                damage = 0,
                boil_eff = 0,
                env_loss = 0,

                fuel = 0,
                fuel_need = 0,
                fuel_fill = 0,
                waste = 0,
                waste_need = 0,
                waste_fill = 0,
                cool_type = "?",
                cool_amnt = 0,
                cool_need = 0,
                cool_fill = 0,
                hcool_type = "?",
                hcool_amnt = 0,
                hcool_need = 0,
                hcool_fill = 0
            },
            mek_struct = {
                heat_cap = 0,
                fuel_asm = 0,
                fuel_sa = 0,
                fuel_cap = 0,
                waste_cap = 0,
                cool_cap = 0,
                hcool_cap = 0,
                max_burn = 0
            }
        }
    }

    local _copy_iss_status = function (iss_status)
        self.sDB.iss_status.dmg_crit  = iss_status[1]
        self.sDB.iss_status.ex_hcool  = iss_status[2]
        self.sDB.iss_status.ex_waste  = iss_status[3]
        self.sDB.iss_status.high_temp = iss_status[4]
        self.sDB.iss_status.no_fuel   = iss_status[5]
        self.sDB.iss_status.no_cool   = iss_status[6]
        self.sDB.iss_status.timed_out = iss_status[7]
    end

    local _copy_status = function (mek_data)
        -- copy status information
        self.sDB.mek_status.status        = mek_data[1]
        self.sDB.mek_status.burn_rate     = mek_data[2]
        self.sDB.mek_status.act_burn_rate = mek_data[3]
        self.sDB.mek_status.temp          = mek_data[4]
        self.sDB.mek_status.damage        = mek_data[5]
        self.sDB.mek_status.boil_eff      = mek_data[6]
        self.sDB.mek_status.env_loss      = mek_data[7]

        -- copy container information
        self.sDB.mek_status.fuel          = mek_data[8]
        self.sDB.mek_status.fuel_fill     = mek_data[9]
        self.sDB.mek_status.waste         = mek_data[10]
        self.sDB.mek_status.waste_fill    = mek_data[11]
        self.sDB.mek_status.cool_type     = mek_data[12]
        self.sDB.mek_status.cool_amnt     = mek_data[13]
        self.sDB.mek_status.cool_fill     = mek_data[14]
        self.sDB.mek_status.hcool_type    = mek_data[15]
        self.sDB.mek_status.hcool_amnt    = mek_data[16]
        self.sDB.mek_status.hcool_fill    = mek_data[17]

        -- update computable fields if we have our structure
        if self.received_struct then
            self.sDB.mek_status.fuel_need  = self.sDB.mek_struct.fuel_cap  - self.sDB.mek_status.fuel_fill
            self.sDB.mek_status.waste_need = self.sDB.mek_struct.waste_cap - self.sDB.mek_status.waste_fill
            self.sDB.mek_status.cool_need  = self.sDB.mek_struct.cool_cap  - self.sDB.mek_status.cool_fill
            self.sDB.mek_status.hcool_need = self.sDB.mek_struct.hcool_cap - self.sDB.mek_status.hcool_fill
        end
    end

    local _copy_struct = function (mek_data)
        self.sDB.mek_struct.heat_cap  = mek_data[1]
        self.sDB.mek_struct.fuel_asm  = mek_data[2]
        self.sDB.mek_struct.fuel_sa   = mek_data[3]
        self.sDB.mek_struct.fuel_cap  = mek_data[4]
        self.sDB.mek_struct.waste_cap = mek_data[5]
        self.sDB.mek_struct.cool_cap  = mek_data[6]
        self.sDB.mek_struct.hcool_cap = mek_data[7]
        self.sDB.mek_struct.max_burn  = mek_data[8]
    end

    -- send an RPLC packet
    local _send = function (msg_type, msg)
        local s_pkt = comms.scada_packet()
        local r_pkt = comms.rplc_packet()

        r_pkt.make(self.id, msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.RPLC, r_pkt.raw_sendable())

        self.out_q.push_packet(s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- send a SCADA management packet
    local _send_mgmt = function (msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.SCADA_MGMT, m_pkt.raw_sendable())

        self.out_q.push_packet(s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- get an ACK status
    local _get_ack = function (pkt)
        if pkt.length == 1 then
            return pkt.data[1]
        else
            log._warning(log_header .. "RPLC ACK length mismatch")
            return nil
        end
    end

    -- handle a packet
    local _handle_packet = function (pkt)
        -- check sequence number
        if self.r_seq_num == nil then
            self.r_seq_num = pkt.scada_frame.seq_num()
        elseif self.r_seq_num >= pkt.scada_frame.seq_num() then
            log._warning(log_header .. "sequence out-of-order: last = " .. self.r_seq_num .. ", new = " .. pkt.scada_frame.seq_num())
            return
        else
            self.r_seq_num = pkt.scada_frame.seq_num()
        end

        -- process packet
        if pkt.scada_frame.protocol() == PROTOCOLS.RPLC then
            -- check reactor ID
            if pkt.id ~= for_reactor then
                log._warning(log_header .. "RPLC packet with ID not matching reactor ID: reactor " .. self.for_reactor .. " != " .. pkt.id)
                return
            end

            -- feed watchdog
            self.plc_conn_watchdog.feed()

            -- handle packet by type
            if pkt.type == RPLC_TYPES.KEEP_ALIVE then
                -- keep alive reply
                if pkt.length == 2 then
                    local srv_start = pkt.data[1]
                    local plc_send = pkt.data[2]
                    local srv_now = util.time()
                    self.last_rtt = srv_now - srv_start

                    if self.last_rtt > 500 then
                        log._warning(log_header .. "PLC KEEP_ALIVE round trip time > 500ms (" .. self.last_rtt .. ")")
                    end

                    -- log._debug(log_header .. "RPLC RTT = ".. self.last_rtt .. "ms")
                    -- log._debug(log_header .. "RPLC TT  = ".. (srv_now - plc_send) .. "ms")
                else
                    log._debug(log_header .. "RPLC keep alive packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPES.STATUS then
                -- status packet received, update data
                if pkt.length >= 5 then
                    self.sDB.last_status_update = pkt.data[1]
                    self.sDB.control_state = pkt.data[2]
                    self.sDB.overridden = pkt.data[3]
                    self.sDB.degraded = pkt.data[4]
                    self.sDB.mek_status.heating_rate = pkt.data[5]

                    -- attempt to read mek_data table
                    if pkt.data[6] ~= nil then
                        local status = pcall(_copy_status, pkt.data[6])
                        if status then
                            -- copied in status data OK
                        else
                            -- error copying status data
                            log._error(log_header .. "failed to parse status packet data")
                        end
                    end
                else
                    log._debug(log_header .. "RPLC status packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPES.MEK_STRUCT then
                -- received reactor structure, record it
                if pkt.length == 8 then
                    local status = pcall(_copy_struct, pkt.data)
                    if status then
                        -- copied in structure data OK
                        self.received_struct = true
                    else
                        -- error copying structure data
                        log._error(log_header .. "failed to parse struct packet data")
                    end
                else
                    log._debug(log_header .. "RPLC struct packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPES.MEK_SCRAM then
                -- SCRAM acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.scram = true
                    self.sDB.control_state = false
                elseif ack == false then
                    log._debug(log_header .. "SCRAM failed!")
                end
            elseif pkt.type == RPLC_TYPES.MEK_ENABLE then
                -- enable acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.enable = true
                    self.sDB.control_state = true
                elseif ack == false then
                    log._debug(log_header .. "enable failed!")
                end
            elseif pkt.type == RPLC_TYPES.MEK_BURN_RATE then
                -- burn rate acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.burn_rate = true
                elseif ack == false then
                    log._debug(log_header .. "burn rate update failed!")
                end
            elseif pkt.type == RPLC_TYPES.ISS_STATUS then
                -- ISS status packet received, copy data
                if pkt.length == 7 then
                    local status = pcall(_copy_iss_status, pkt.data)
                    if status then
                        -- copied in ISS status data OK
                    else
                        -- error copying ISS status data
                        log._error(log_header .. "failed to parse ISS status packet data")
                    end
                else
                    log._debug(log_header .. "RPLC ISS status packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPES.ISS_ALARM then
                -- ISS alarm
                self.sDB.overridden = true
                if pkt.length == 8 then
                    self.sDB.iss_tripped = true
                    self.sDB.iss_trip_cause = pkt.data[1]
                    local status = pcall(_copy_iss_status, { table.unpack(pkt.data, 2, #pkt.length) })
                    if status then
                        -- copied in ISS status data OK
                    else
                        -- error copying ISS status data
                        log._error(log_header .. "failed to parse ISS alarm status data")
                    end
                else
                    log._debug(log_header .. "RPLC ISS alarm packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPES.ISS_CLEAR then
                -- ISS clear acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.iss_tripped = true
                    self.sDB.iss_tripped = false
                    self.sDB.iss_trip_cause = "ok"
                elseif ack == false then
                    log._debug(log_header .. "ISS clear failed")
                end
            else
                log._debug(log_header .. "handler received unsupported RPLC packet type " .. pkt.type)
            end
        elseif pkt.scada_frame.protocol() == PROTOCOLS.SCADA_MGMT then
            if pkt.type == SCADA_MGMT_TYPES.CLOSE then
                -- close the session
                self.connected = false
            else
                log._debug(log_header .. "handler received unsupported SCADA_MGMT packet type " .. pkt.type)
            end
        end
    end

    -- PUBLIC FUNCTIONS --

    -- get the session ID
    local get_id = function () return self.id end

    -- get the session database
    local get_db = function () return self.sDB end

    -- close the connection
    local close = function ()
        self.plc_conn_watchdog.cancel()
        self.connected = false
        _send_mgmt(SCADA_MGMT_TYPES.CLOSE, {})
    end

    -- check if a timer matches this session's watchdog
    local check_wd = function (timer)
        return timer == self.plc_conn_watchdog.get_timer()
    end

    -- get the reactor structure
    local get_struct = function ()
        if self.received_struct then
            return self.sDB.mek_struct
        else
            return nil
        end
    end

    -- iterate the session
    local iterate = function ()
        if self.connected then
            ------------------
            -- handle queue --
            ------------------

            local handle_start = util.time()

            while self.in_q.ready() and self.connected do
                -- get a new message to process
                local message = self.in_q.pop()

                if message.qtype == mqueue.TYPE.PACKET then
                    -- handle a packet
                    _handle_packet(message.message)
                elseif message.qtype == mqueue.TYPE.COMMAND then
                    -- handle instruction
                    local cmd = message.message
                    if cmd == PLC_S_CMDS.SCRAM then
                        -- SCRAM reactor
                        self.acks.scram = false
                        self.retry_times.scram_req = util.time() + INITIAL_WAIT
                        _send(RPLC_TYPES.MEK_SCRAM, {})
                    elseif cmd == PLC_S_CMDS.ENABLE then
                        -- enable reactor
                        self.acks.enable = false
                        self.retry_times.enable_req = util.time() + INITIAL_WAIT
                        _send(RPLC_TYPES.MEK_ENABLE, {})
                    elseif cmd == PLC_S_CMDS.ISS_CLEAR then
                        -- clear ISS
                        self.acks.iss_clear = false
                        self.retry_times.iss_clear_req = util.time() + INITIAL_WAIT
                        _send(RPLC_TYPES.ISS_CLEAR, {})
                    end
                elseif message.qtype == mqueue.TYPE.DATA then
                    -- instruction with body
                    local cmd = message.message
                    if cmd.key == PLC_S_CMDS.BURN_RATE then
                        -- update burn rate
                        self.commanded_burn_rate = cmd.val
                        self.acks.burn_rate = false
                        self.retry_times.burn_rate_req = util.time() + INITIAL_WAIT
                        _send(RPLC_TYPES.MEK_BURN_RATE, { self.commanded_burn_rate })
                    end
                end

                -- max 100ms spent processing queue
                if util.time() - handle_start > 100 then
                    log._warning(log_header .. "exceeded 100ms queue process limit")
                    break
                end
            end

            -- exit if connection was closed
            if not self.connected then
                log._info(log_header .. "session closed by remote host")
                return self.connected
            end

            ----------------------
            -- update periodics --
            ----------------------

            local elapsed = util.time() - self.periodics.last_update

            local periodics = self.periodics

            -- keep alive

            periodics.keep_alive = periodics.keep_alive + elapsed
            if periodics.keep_alive >= PERIODICS.KEEP_ALIVE then
                _send(RPLC_TYPES.KEEP_ALIVE, { util.time() })
                periodics.keep_alive = 0
            end

            self.periodics.last_update = util.time()

            ---------------------
            -- attempt retries --
            ---------------------

            local rtimes = self.retry_times

            -- struct request retry

            if not self.received_struct then
                if rtimes.struct_req - util.time() <= 0 then
                    _send(RPLC_TYPES.MEK_STRUCT, {})
                    rtimes.struct_req = util.time() + RETRY_PERIOD
                end
            end

            -- SCRAM request retry

            if not self.acks.scram then
                if rtimes.scram_req - util.time() <= 0 then
                    _send(RPLC_TYPES.MEK_SCRAM, {})
                    rtimes.scram_req = util.time() + RETRY_PERIOD
                end
            end

            -- enable request retry

            if not self.acks.enable then
                if rtimes.enable_req - util.time() <= 0 then
                    _send(RPLC_TYPES.MEK_ENABLE, {})
                    rtimes.enable_req = util.time() + RETRY_PERIOD
                end
            end

            -- burn rate request retry

            if not self.acks.burn_rate then
                if rtimes.burn_rate_req - util.time() <= 0 then
                    _send(RPLC_TYPES.MEK_BURN_RATE, { self.commanded_burn_rate })
                    rtimes.burn_rate_req = util.time() + RETRY_PERIOD
                end
            end

            -- ISS clear request retry

            if not self.acks.iss_clear then
                if rtimes.iss_clear_req - util.time() <= 0 then
                    _send(RPLC_TYPES.ISS_CLEAR, {})
                    rtimes.iss_clear_req = util.time() + RETRY_PERIOD
                end
            end
        end

        return self.connected
    end

    return {
        get_id = get_id,
        get_db = get_db,
        close = close,
        check_wd = check_wd,
        get_struct = get_struct,
        iterate = iterate
    }
end
