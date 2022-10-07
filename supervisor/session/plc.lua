local comms    = require("scada-common.comms")
local log      = require("scada-common.log")
local mqueue   = require("scada-common.mqueue")
local util     = require("scada-common.util")

local svqtypes = require("supervisor.session.svqtypes")

local plc = {}

local PROTOCOLS = comms.PROTOCOLS
local RPLC_TYPES = comms.RPLC_TYPES
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

-- retry time constants in ms
local INITIAL_WAIT = 1500
local RETRY_PERIOD = 1000

local PLC_S_CMDS = {
    SCRAM = 1,
    ENABLE = 2,
    RPS_RESET = 3
}

local PLC_S_DATA = {
    BURN_RATE = 1,
    RAMP_BURN_RATE = 2
}

plc.PLC_S_CMDS = PLC_S_CMDS
plc.PLC_S_DATA = PLC_S_DATA

local PERIODICS = {
    KEEP_ALIVE = 2000
}

-- PLC supervisor session
---@param id integer
---@param for_reactor integer
---@param in_queue mqueue
---@param out_queue mqueue
function plc.new_session(id, for_reactor, in_queue, out_queue)
    local log_header = "plc_session(" .. id .. "): "

    local self = {
        id = id,
        for_reactor = for_reactor,
        in_q = in_queue,
        out_q = out_queue,
        commanded_state = false,
        commanded_burn_rate = 0.0,
        ramping_rate = false,
        -- connection properties
        seq_num = 0,
        r_seq_num = nil,
        connected = true,
        received_struct = false,
        received_status_cache = false,
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
            status_req = (util.time() + 500),
            scram_req = 0,
            enable_req = 0,
            burn_rate_req = 0,
            rps_reset_req = 0
        },
        -- command acknowledgements
        acks = {
            scram = true,
            enable = true,
            burn_rate = true,
            rps_reset = true
        },
        -- session database
        ---@class reactor_db
        sDB = {
            last_status_update = 0,
            control_state = false,
            degraded = false,
            rps_tripped = false,
            rps_trip_cause = "ok",  ---@type rps_trip_cause
            ---@class rps_status
            rps_status = {
                dmg_crit = false,
                ex_hcool = false,
                ex_waste = false,
                high_temp = false,
                no_fuel = false,
                no_cool = false,
                fault = false,
                timeout = false,
                manual = false
            },
            ---@class mek_status
            mek_status = {
                heating_rate = 0.0,

                status = false,
                burn_rate = 0.0,
                act_burn_rate = 0.0,
                temp = 0.0,
                damage = 0.0,
                boil_eff = 0.0,
                env_loss = 0.0,

                fuel = 0,
                fuel_need = 0,
                fuel_fill = 0.0,
                waste = 0,
                waste_need = 0,
                waste_fill = 0.0,
                ccool_type = "?",
                ccool_amnt = 0,
                ccool_need = 0,
                ccool_fill = 0.0,
                hcool_type = "?",
                hcool_amnt = 0,
                hcool_need = 0,
                hcool_fill = 0.0
            },
            ---@class mek_struct
            mek_struct = {
                formed = false,
                length = 0,
                width = 0,
                height = 0,
                min_pos = { x = 0, y = 0, z = 0 },  ---@type coordinate
                max_pos = { x = 0, y = 0, z = 0 },  ---@type coordinate
                heat_cap = 0,
                fuel_asm = 0,
                fuel_sa = 0,
                fuel_cap = 0,
                waste_cap = 0,
                ccool_cap = 0,
                hcool_cap = 0,
                max_burn = 0.0
            }
        }
    }

    ---@class plc_session
    local public = {}

    -- copy in the RPS status
    ---@param rps_status table
    local function _copy_rps_status(rps_status)
        self.sDB.rps_status.dmg_crit  = rps_status[1]
        self.sDB.rps_status.ex_hcool  = rps_status[2]
        self.sDB.rps_status.ex_waste  = rps_status[3]
        self.sDB.rps_status.high_temp = rps_status[4]
        self.sDB.rps_status.no_fuel   = rps_status[5]
        self.sDB.rps_status.no_cool   = rps_status[6]
        self.sDB.rps_status.fault     = rps_status[7]
        self.sDB.rps_status.timeout   = rps_status[8]
        self.sDB.rps_status.manual    = rps_status[9]
    end

    -- copy in the reactor status
    ---@param mek_data table
    local function _copy_status(mek_data)
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
        self.sDB.mek_status.ccool_type    = mek_data[12]
        self.sDB.mek_status.ccool_amnt    = mek_data[13]
        self.sDB.mek_status.ccool_fill    = mek_data[14]
        self.sDB.mek_status.hcool_type    = mek_data[15]
        self.sDB.mek_status.hcool_amnt    = mek_data[16]
        self.sDB.mek_status.hcool_fill    = mek_data[17]

        -- update computable fields if we have our structure
        if self.received_struct then
            self.sDB.mek_status.fuel_need  = self.sDB.mek_struct.fuel_cap  - self.sDB.mek_status.fuel_fill
            self.sDB.mek_status.waste_need = self.sDB.mek_struct.waste_cap - self.sDB.mek_status.waste_fill
            self.sDB.mek_status.cool_need  = self.sDB.mek_struct.ccool_cap - self.sDB.mek_status.ccool_fill
            self.sDB.mek_status.hcool_need = self.sDB.mek_struct.hcool_cap - self.sDB.mek_status.hcool_fill
        end
    end

    -- copy in the reactor structure
    ---@param mek_data table
    local function _copy_struct(mek_data)
        self.sDB.mek_struct.formed    = mek_data[1]
        self.sDB.mek_struct.length    = mek_data[2]
        self.sDB.mek_struct.width     = mek_data[3]
        self.sDB.mek_struct.height    = mek_data[4]
        self.sDB.mek_struct.min_pos   = mek_data[5]
        self.sDB.mek_struct.max_pos   = mek_data[6]
        self.sDB.mek_struct.heat_cap  = mek_data[7]
        self.sDB.mek_struct.fuel_asm  = mek_data[8]
        self.sDB.mek_struct.fuel_sa   = mek_data[9]
        self.sDB.mek_struct.fuel_cap  = mek_data[10]
        self.sDB.mek_struct.waste_cap = mek_data[11]
        self.sDB.mek_struct.ccool_cap = mek_data[12]
        self.sDB.mek_struct.hcool_cap = mek_data[13]
        self.sDB.mek_struct.max_burn  = mek_data[14]
    end

    -- mark this PLC session as closed, stop watchdog
    local function _close()
        self.plc_conn_watchdog.cancel()
        self.connected = false
    end

    -- send an RPLC packet
    ---@param msg_type RPLC_TYPES
    ---@param msg table
    local function _send(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local r_pkt = comms.rplc_packet()

        r_pkt.make(self.id, msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.RPLC, r_pkt.raw_sendable())

        self.out_q.push_packet(s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- send a SCADA management packet
    ---@param msg_type SCADA_MGMT_TYPES
    ---@param msg table
    local function _send_mgmt(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.SCADA_MGMT, m_pkt.raw_sendable())

        self.out_q.push_packet(s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- get an ACK status
    ---@param pkt rplc_frame
    ---@return boolean|nil ack
    local function _get_ack(pkt)
        if pkt.length == 1 then
            return pkt.data[1]
        else
            log.warning(log_header .. "RPLC ACK length mismatch")
            return nil
        end
    end

    -- handle a packet
    ---@param pkt rplc_frame
    local function _handle_packet(pkt)
        -- check sequence number
        if self.r_seq_num == nil then
            self.r_seq_num = pkt.scada_frame.seq_num()
        elseif self.r_seq_num >= pkt.scada_frame.seq_num() then
            log.warning(log_header .. "sequence out-of-order: last = " .. self.r_seq_num .. ", new = " .. pkt.scada_frame.seq_num())
            return
        else
            self.r_seq_num = pkt.scada_frame.seq_num()
        end

        -- process packet
        if pkt.scada_frame.protocol() == PROTOCOLS.RPLC then
            -- check reactor ID
            if pkt.id ~= for_reactor then
                log.warning(log_header .. "RPLC packet with ID not matching reactor ID: reactor " .. self.for_reactor .. " != " .. pkt.id)
                return
            end

            -- feed watchdog
            self.plc_conn_watchdog.feed()

            -- handle packet by type
            if pkt.type == RPLC_TYPES.STATUS then
                -- status packet received, update data
                if pkt.length >= 5 then
                    self.sDB.last_status_update = pkt.data[1]
                    self.sDB.control_state = pkt.data[2]
                    self.sDB.rps_tripped = pkt.data[3]
                    self.sDB.degraded = pkt.data[4]
                    self.sDB.mek_status.heating_rate = pkt.data[5]

                    -- attempt to read mek_data table
                    if pkt.data[6] ~= nil then
                        local status = pcall(_copy_status, pkt.data[6])
                        if status then
                            -- copied in status data OK
                            self.received_status_cache = true
                        else
                            -- error copying status data
                            log.error(log_header .. "failed to parse status packet data")
                        end
                    end
                else
                    log.debug(log_header .. "RPLC status packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPES.MEK_STRUCT then
                -- received reactor structure, record it
                if pkt.length == 14 then
                    local status = pcall(_copy_struct, pkt.data)
                    if status then
                        -- copied in structure data OK
                        self.received_struct = true
                        self.out_q.push_command(svqtypes.SV_Q_CMDS.BUILD_CHANGED)
                    else
                        -- error copying structure data
                        log.error(log_header .. "failed to parse struct packet data")
                    end
                else
                    log.debug(log_header .. "RPLC struct packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPES.MEK_BURN_RATE then
                -- burn rate acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.burn_rate = true
                elseif ack == false then
                    log.debug(log_header .. "burn rate update failed!")
                end
            elseif pkt.type == RPLC_TYPES.RPS_ENABLE then
                -- enable acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.enable = true
                    self.sDB.control_state = true
                elseif ack == false then
                    log.debug(log_header .. "enable failed!")
                end
            elseif pkt.type == RPLC_TYPES.RPS_SCRAM then
                -- SCRAM acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.scram = true
                    self.sDB.control_state = false
                elseif ack == false then
                    log.debug(log_header .. "SCRAM failed!")
                end
            elseif pkt.type == RPLC_TYPES.RPS_STATUS then
                -- RPS status packet received, copy data
                if pkt.length == 9 then
                    local status = pcall(_copy_rps_status, pkt.data)
                    if status then
                        -- copied in RPS status data OK
                    else
                        -- error copying RPS status data
                        log.error(log_header .. "failed to parse RPS status packet data")
                    end
                else
                    log.debug(log_header .. "RPLC RPS status packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPES.RPS_ALARM then
                -- RPS alarm
                if pkt.length == 10 then
                    self.sDB.rps_tripped = true
                    self.sDB.rps_trip_cause = pkt.data[1]
                    local status = pcall(_copy_rps_status, { table.unpack(pkt.data, 2, pkt.length) })
                    if status then
                        -- copied in RPS status data OK
                    else
                        -- error copying RPS status data
                        log.error(log_header .. "failed to parse RPS alarm status data")
                    end
                else
                    log.debug(log_header .. "RPLC RPS alarm packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPES.RPS_RESET then
                -- RPS reset acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.rps_reset = true
                    self.sDB.rps_tripped = false
                    self.sDB.rps_trip_cause = "ok"
                elseif ack == false then
                    log.debug(log_header .. "RPS reset failed")
                end
            else
                log.debug(log_header .. "handler received unsupported RPLC packet type " .. pkt.type)
            end
        elseif pkt.scada_frame.protocol() == PROTOCOLS.SCADA_MGMT then
            if pkt.type == SCADA_MGMT_TYPES.KEEP_ALIVE then
                -- keep alive reply
                if pkt.length == 2 then
                    local srv_start = pkt.data[1]
                    local plc_send = pkt.data[2]
                    local srv_now = util.time()
                    self.last_rtt = srv_now - srv_start

                    if self.last_rtt > 500 then
                        log.warning(log_header .. "PLC KEEP_ALIVE round trip time > 500ms (" .. self.last_rtt .. "ms)")
                    end

                    -- log.debug(log_header .. "PLC RTT = " .. self.last_rtt .. "ms")
                    -- log.debug(log_header .. "PLC TT  = " .. (srv_now - plc_send) .. "ms")
                else
                    log.debug(log_header .. "SCADA keep alive packet length mismatch")
                end
            elseif pkt.type == SCADA_MGMT_TYPES.CLOSE then
                -- close the session
                _close()
            else
                log.debug(log_header .. "handler received unsupported SCADA_MGMT packet type " .. pkt.type)
            end
        end
    end

    -- PUBLIC FUNCTIONS --

    -- get the session ID
    function public.get_id() return self.id end

    -- get the session database
    function public.get_db() return self.sDB end

    -- get the reactor structure
    function public.get_struct()
        if self.received_struct then
            return self.sDB.mek_struct
        else
            return nil
        end
    end

    -- get the reactor status
    function public.get_status()
        if self.received_status_cache then
            return self.sDB.mek_status
        else
            return nil
        end
    end

    -- get the reactor RPS status
    function public.get_rps()
        return self.sDB.rps_status
    end

    -- get the general status information
    function public.get_general_status()
        return {
            self.sDB.last_status_update,
            self.sDB.control_state,
            self.sDB.rps_tripped,
            self.sDB.rps_trip_cause,
            self.sDB.degraded
        }
    end

    -- check if a timer matches this session's watchdog
    function public.check_wd(timer)
        return self.plc_conn_watchdog.is_timer(timer) and self.connected
    end

    -- close the connection
    function public.close()
        _close()
        _send_mgmt(SCADA_MGMT_TYPES.CLOSE, {})
        println("connection to reactor " .. self.for_reactor .. " PLC closed by server")
        log.info(log_header .. "session closed by server")
    end

    -- iterate the session
    ---@return boolean connected
    function public.iterate()
        if self.connected then
            ------------------
            -- handle queue --
            ------------------

            local handle_start = util.time()

            while self.in_q.ready() and self.connected do
                -- get a new message to process
                local message = self.in_q.pop()

                if message ~= nil then
                    if message.qtype == mqueue.TYPE.PACKET then
                        -- handle a packet
                        _handle_packet(message.message)
                    elseif message.qtype == mqueue.TYPE.COMMAND then
                        -- handle instruction
                        local cmd = message.message
                        if cmd == PLC_S_CMDS.ENABLE then
                            -- enable reactor
                            self.acks.enable = false
                            self.retry_times.enable_req = util.time() + INITIAL_WAIT
                            _send(RPLC_TYPES.RPS_ENABLE, {})
                        elseif cmd == PLC_S_CMDS.SCRAM then
                            -- SCRAM reactor
                            self.acks.scram = false
                            self.retry_times.scram_req = util.time() + INITIAL_WAIT
                            _send(RPLC_TYPES.RPS_SCRAM, {})
                        elseif cmd == PLC_S_CMDS.RPS_RESET then
                            -- reset RPS
                            self.acks.rps_reset = false
                            self.retry_times.rps_reset_req = util.time() + INITIAL_WAIT
                            _send(RPLC_TYPES.RPS_RESET, {})
                        end
                    elseif message.qtype == mqueue.TYPE.DATA then
                        -- instruction with body
                        local cmd = message.message ---@type queue_data
                        if cmd.key == PLC_S_DATA.BURN_RATE then
                            -- update burn rate
                            cmd.val = math.floor(cmd.val * 10) / 10 -- round to 10ths place
                            if cmd.val > 0 and cmd.val <= self.sDB.mek_struct.max_burn then
                                self.commanded_burn_rate = cmd.val
                                self.ramping_rate = false
                                self.acks.burn_rate = false
                                self.retry_times.burn_rate_req = util.time() + INITIAL_WAIT
                                _send(RPLC_TYPES.MEK_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate })
                            end
                        elseif cmd.key == PLC_S_DATA.RAMP_BURN_RATE then
                            -- ramp to burn rate
                            cmd.val = math.floor(cmd.val * 10) / 10 -- round to 10ths place
                            if cmd.val > 0 and cmd.val <= self.sDB.mek_struct.max_burn then
                                self.commanded_burn_rate = cmd.val
                                self.ramping_rate = true
                                self.acks.burn_rate = false
                                self.retry_times.burn_rate_req = util.time() + INITIAL_WAIT
                                _send(RPLC_TYPES.MEK_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate })
                            end
                        end
                    end
                end

                -- max 100ms spent processing queue
                if util.time() - handle_start > 100 then
                    log.warning(log_header .. "exceeded 100ms queue process limit")
                    break
                end
            end

            -- exit if connection was closed
            if not self.connected then
                println("connection to reactor " .. self.for_reactor .. " PLC closed by remote host")
                log.info(log_header .. "session closed by remote host")
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
                _send_mgmt(SCADA_MGMT_TYPES.KEEP_ALIVE, { util.time() })
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

            -- status cache request retry

            if not self.received_status_cache then
                if rtimes.status_req - util.time() <= 0 then
                    _send(RPLC_TYPES.MEK_STATUS, {})
                    rtimes.status_req = util.time() + RETRY_PERIOD
                end
            end

            -- SCRAM request retry

            if not self.acks.scram then
                if rtimes.scram_req - util.time() <= 0 then
                    _send(RPLC_TYPES.RPS_SCRAM, {})
                    rtimes.scram_req = util.time() + RETRY_PERIOD
                end
            end

            -- enable request retry

            if not self.acks.enable then
                if rtimes.enable_req - util.time() <= 0 then
                    _send(RPLC_TYPES.RPS_ENABLE, {})
                    rtimes.enable_req = util.time() + RETRY_PERIOD
                end
            end

            -- burn rate request retry

            if not self.acks.burn_rate then
                if rtimes.burn_rate_req - util.time() <= 0 then
                    _send(RPLC_TYPES.MEK_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate })
                    rtimes.burn_rate_req = util.time() + RETRY_PERIOD
                end
            end

            -- RPS reset request retry

            if not self.acks.rps_reset then
                if rtimes.rps_reset_req - util.time() <= 0 then
                    _send(RPLC_TYPES.RPS_RESET, {})
                    rtimes.rps_reset_req = util.time() + RETRY_PERIOD
                end
            end
        end

        return self.connected
    end

    return public
end

return plc
