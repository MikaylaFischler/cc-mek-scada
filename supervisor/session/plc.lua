local comms    = require("scada-common.comms")
local log      = require("scada-common.log")
local mqueue   = require("scada-common.mqueue")
local types    = require("scada-common.types")
local util     = require("scada-common.util")

local svqtypes = require("supervisor.session.svqtypes")

local plc = {}

local PROTOCOL = comms.PROTOCOL
local RPLC_TYPE = comms.RPLC_TYPE
local SCADA_MGMT_TYPE = comms.SCADA_MGMT_TYPE
local PLC_AUTO_ACK = comms.PLC_AUTO_ACK
local UNIT_COMMAND = comms.UNIT_COMMAND

local println = util.println

-- retry time constants in ms
local INITIAL_WAIT      = 1500
local INITIAL_AUTO_WAIT = 1000
local RETRY_PERIOD      = 1000

local PLC_S_CMDS = {
    SCRAM = 1,
    ASCRAM = 2,
    ENABLE = 3,
    RPS_RESET = 4,
    RPS_AUTO_RESET = 5
}

local PLC_S_DATA = {
    BURN_RATE = 1,
    RAMP_BURN_RATE = 2,
    AUTO_BURN_RATE = 3
}

plc.PLC_S_CMDS = PLC_S_CMDS
plc.PLC_S_DATA = PLC_S_DATA

local PERIODICS = {
    KEEP_ALIVE = 2000
}

-- PLC supervisor session
---@nodiscard
---@param id integer session ID
---@param reactor_id integer reactor ID
---@param in_queue mqueue in message queue
---@param out_queue mqueue out message queue
---@param timeout number communications timeout
function plc.new_session(id, reactor_id, in_queue, out_queue, timeout)
    local log_header = "plc_session(" .. id .. "): "

    local self = {
        commanded_state = false,
        commanded_burn_rate = 0.0,
        auto_cmd_token = 0,
        ramping_rate = false,
        auto_lock = false,
        -- connection properties
        seq_num = 0,
        r_seq_num = nil,
        connected = true,
        received_struct = false,
        received_status_cache = false,
        plc_conn_watchdog = util.new_watchdog(timeout),
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
            ascram_req = 0,
            burn_rate_req = 0,
            rps_reset_req = 0
        },
        -- command acknowledgements
        acks = {
            scram = true,
            ascram = true,
            burn_rate = true,
            rps_reset = true
        },
        -- session database
        ---@class reactor_db
        sDB = {
            auto_ack_token = 0,
            last_status_update = 0,
            control_state = false,
            no_reactor = false,
            formed = false,
            rps_tripped = false,
            rps_trip_cause = "ok",  ---@type rps_trip_cause
            ---@class rps_status
            rps_status = {
                high_dmg = false,
                high_temp = false,
                low_cool = false,
                ex_waste = false,
                ex_hcool = false,
                no_fuel = false,
                fault = false,
                timeout = false,
                manual = false,
                automatic = false,
                sys_fail = false,
                force_dis = false
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
                length = 0,
                width = 0,
                height = 0,
                min_pos = types.new_zero_coordinate(),
                max_pos = types.new_zero_coordinate(),
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
        self.sDB.rps_tripped          = rps_status[1]
        self.sDB.rps_trip_cause       = rps_status[2]
        self.sDB.rps_status.high_dmg  = rps_status[3]
        self.sDB.rps_status.high_temp = rps_status[4]
        self.sDB.rps_status.low_cool  = rps_status[5]
        self.sDB.rps_status.ex_waste  = rps_status[6]
        self.sDB.rps_status.ex_hcool  = rps_status[7]
        self.sDB.rps_status.no_fuel   = rps_status[8]
        self.sDB.rps_status.fault     = rps_status[9]
        self.sDB.rps_status.timeout   = rps_status[10]
        self.sDB.rps_status.manual    = rps_status[11]
        self.sDB.rps_status.automatic = rps_status[12]
        self.sDB.rps_status.sys_fail  = rps_status[13]
        self.sDB.rps_status.force_dis = rps_status[14]
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
        self.sDB.mek_struct.length    = mek_data[1]
        self.sDB.mek_struct.width     = mek_data[2]
        self.sDB.mek_struct.height    = mek_data[3]
        self.sDB.mek_struct.min_pos   = mek_data[4]
        self.sDB.mek_struct.max_pos   = mek_data[5]
        self.sDB.mek_struct.heat_cap  = mek_data[6]
        self.sDB.mek_struct.fuel_asm  = mek_data[7]
        self.sDB.mek_struct.fuel_sa   = mek_data[8]
        self.sDB.mek_struct.fuel_cap  = mek_data[9]
        self.sDB.mek_struct.waste_cap = mek_data[10]
        self.sDB.mek_struct.ccool_cap = mek_data[11]
        self.sDB.mek_struct.hcool_cap = mek_data[12]
        self.sDB.mek_struct.max_burn  = mek_data[13]
    end

    -- mark this PLC session as closed, stop watchdog
    local function _close()
        self.plc_conn_watchdog.cancel()
        self.connected = false
    end

    -- send an RPLC packet
    ---@param msg_type RPLC_TYPE
    ---@param msg table
    local function _send(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local r_pkt = comms.rplc_packet()

        r_pkt.make(reactor_id, msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOL.RPLC, r_pkt.raw_sendable())

        out_queue.push_packet(s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- send a SCADA management packet
    ---@param msg_type SCADA_MGMT_TYPE
    ---@param msg table
    local function _send_mgmt(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOL.SCADA_MGMT, m_pkt.raw_sendable())

        out_queue.push_packet(s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- get an ACK status
    ---@nodiscard
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
        if pkt.scada_frame.protocol() == PROTOCOL.RPLC then
            -- check reactor ID
            if pkt.id ~= reactor_id then
                log.warning(log_header .. "RPLC packet with ID not matching reactor ID: reactor " .. reactor_id .. " != " .. pkt.id)
                return
            end

            -- feed watchdog
            self.plc_conn_watchdog.feed()

            -- handle packet by type
            if pkt.type == RPLC_TYPE.STATUS then
                -- status packet received, update data
                if pkt.length >= 5 then
                    self.sDB.last_status_update = pkt.data[1]
                    self.sDB.control_state = pkt.data[2]
                    self.sDB.no_reactor = pkt.data[3]
                    self.sDB.formed = pkt.data[4]
                    self.sDB.auto_ack_token = pkt.data[5]

                    if not self.sDB.no_reactor and self.sDB.formed then
                        self.sDB.mek_status.heating_rate = pkt.data[6] or 0.0

                        -- attempt to read mek_data table
                        if pkt.data[7] ~= nil then
                            local status = pcall(_copy_status, pkt.data[7])
                            if status then
                                -- copied in status data OK
                                self.received_status_cache = true
                            else
                                -- error copying status data
                                log.error(log_header .. "failed to parse status packet data")
                            end
                        end
                    end
                else
                    log.debug(log_header .. "RPLC status packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPE.MEK_STRUCT then
                -- received reactor structure, record it
                if pkt.length == 14 then
                    local status = pcall(_copy_struct, pkt.data)
                    if status then
                        -- copied in structure data OK
                        self.received_struct = true
                        out_queue.push_data(svqtypes.SV_Q_DATA.PLC_BUILD_CHANGED, reactor_id)
                    else
                        -- error copying structure data
                        log.error(log_header .. "failed to parse struct packet data")
                    end
                else
                    log.debug(log_header .. "RPLC struct packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPE.MEK_BURN_RATE then
                -- burn rate acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.burn_rate = true
                elseif ack == false then
                    log.debug(log_header .. "burn rate update failed!")
                end

                -- send acknowledgement to coordinator
                out_queue.push_data(svqtypes.SV_Q_DATA.CRDN_ACK, {
                    unit = reactor_id,
                    cmd = UNIT_COMMAND.SET_BURN,
                    ack = ack
                })
            elseif pkt.type == RPLC_TYPE.RPS_ENABLE then
                -- enable acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.sDB.control_state = true
                elseif ack == false then
                    log.debug(log_header .. "enable failed!")
                end

                -- send acknowledgement to coordinator
                out_queue.push_data(svqtypes.SV_Q_DATA.CRDN_ACK, {
                    unit = reactor_id,
                    cmd = UNIT_COMMAND.START,
                    ack = ack
                })
            elseif pkt.type == RPLC_TYPE.RPS_SCRAM then
                -- manual SCRAM acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.scram = true
                    self.sDB.control_state = false
                elseif ack == false then
                    log.debug(log_header .. "manual SCRAM failed!")
                end

                -- send acknowledgement to coordinator
                out_queue.push_data(svqtypes.SV_Q_DATA.CRDN_ACK, {
                    unit = reactor_id,
                    cmd = UNIT_COMMAND.SCRAM,
                    ack = ack
                })
            elseif pkt.type == RPLC_TYPE.RPS_ASCRAM then
                -- automatic SCRAM acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.ascram = true
                    self.sDB.control_state = false
                elseif ack == false then
                    log.debug(log_header .. " automatic SCRAM failed!")
                end
            elseif pkt.type == RPLC_TYPE.RPS_STATUS then
                -- RPS status packet received, copy data
                if pkt.length == 14 then
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
            elseif pkt.type == RPLC_TYPE.RPS_ALARM then
                -- RPS alarm
                if pkt.length == 13 then
                    local status = pcall(_copy_rps_status, { true, table.unpack(pkt.data) })
                    if status then
                        -- copied in RPS status data OK
                    else
                        -- error copying RPS status data
                        log.error(log_header .. "failed to parse RPS alarm status data")
                    end
                else
                    log.debug(log_header .. "RPLC RPS alarm packet length mismatch")
                end
            elseif pkt.type == RPLC_TYPE.RPS_RESET then
                -- RPS reset acknowledgement
                local ack = _get_ack(pkt)
                if ack then
                    self.acks.rps_reset = true
                    self.sDB.rps_tripped = false
                    self.sDB.rps_trip_cause = "ok"
                elseif ack == false then
                    log.debug(log_header .. "RPS reset failed")
                end

                -- send acknowledgement to coordinator
                out_queue.push_data(svqtypes.SV_Q_DATA.CRDN_ACK, {
                    unit = reactor_id,
                    cmd = UNIT_COMMAND.RESET_RPS,
                    ack = ack
                })
            elseif pkt.type == RPLC_TYPE.RPS_AUTO_RESET then
                -- RPS auto control reset acknowledgement
                local ack = _get_ack(pkt)
                if not ack then
                    log.debug(log_header .. "RPS auto reset failed")
                end
            elseif pkt.type == RPLC_TYPE.AUTO_BURN_RATE then
                if pkt.length == 1 then
                    local ack = pkt.data[1]

                    if ack == PLC_AUTO_ACK.FAIL then
                        self.acks.burn_rate = false
                        log.debug(log_header .. "RPLC automatic burn rate set fail")
                    elseif ack == PLC_AUTO_ACK.DIRECT_SET_OK or ack == PLC_AUTO_ACK.RAMP_SET_OK or ack == PLC_AUTO_ACK.ZERO_DIS_OK then
                        self.acks.burn_rate = true
                    else
                        self.acks.burn_rate = false
                        log.debug(log_header .. "RPLC automatic burn rate ack unknown")
                    end
                else
                    log.debug(log_header .. "RPLC automatic burn rate ack packet length mismatch")
                end
            else
                log.debug(log_header .. "handler received unsupported RPLC packet type " .. pkt.type)
            end
        elseif pkt.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
            if pkt.type == SCADA_MGMT_TYPE.KEEP_ALIVE then
                -- keep alive reply
                if pkt.length == 2 then
                    local srv_start = pkt.data[1]
                    -- local plc_send = pkt.data[2]
                    local srv_now = util.time()
                    self.last_rtt = srv_now - srv_start

                    if self.last_rtt > 750 then
                        log.warning(log_header .. "PLC KEEP_ALIVE round trip time > 750ms (" .. self.last_rtt .. "ms)")
                    end

                    -- log.debug(log_header .. "PLC RTT = " .. self.last_rtt .. "ms")
                    -- log.debug(log_header .. "PLC TT  = " .. (srv_now - plc_send) .. "ms")
                else
                    log.debug(log_header .. "SCADA keep alive packet length mismatch")
                end
            elseif pkt.type == SCADA_MGMT_TYPE.CLOSE then
                -- close the session
                _close()
            else
                log.debug(log_header .. "handler received unsupported SCADA_MGMT packet type " .. pkt.type)
            end
        end
    end

    -- PUBLIC FUNCTIONS --

    -- get the session ID
    ---@nodiscard
    function public.get_id() return id end

    -- get the session database
    ---@nodiscard
    function public.get_db() return self.sDB end

    -- check if ramping is completed by first verifying auto command token ack
    ---@nodiscard
    function public.is_ramp_complete()
        return (self.sDB.auto_ack_token == self.auto_cmd_token) and (self.commanded_burn_rate == self.sDB.mek_status.act_burn_rate)
    end

    -- get the reactor structure
    ---@nodiscard
    ---@return mek_struct|table struct struct or empty table
    function public.get_struct()
        if self.received_struct then
            return self.sDB.mek_struct
        else
            return {}
        end
    end

    -- get the reactor status
    ---@nodiscard
    ---@return mek_status|table struct status or empty table
    function public.get_status()
        if self.received_status_cache then
            return self.sDB.mek_status
        else
            return {}
        end
    end

    -- get the reactor RPS status
    ---@nodiscard
    function public.get_rps()
        return self.sDB.rps_status
    end

    -- get the general status information
    ---@nodiscard
    function public.get_general_status()
        return {
            self.sDB.last_status_update,
            self.sDB.control_state,
            self.sDB.rps_tripped,
            self.sDB.rps_trip_cause,
            self.sDB.no_reactor,
            self.sDB.formed
        }
    end

    -- lock out some manual operator actions during automatic control
    ---@param engage boolean true to engage the lockout
    function public.auto_lock(engage)
        self.auto_lock = engage

        -- stop retrying a burn rate command
        if engage then
            self.acks.burn_rate = true
        end
    end

    -- set the burn rate on behalf of automatic control
    ---@param rate number burn rate
    ---@param ramp boolean true to ramp, false to not
    function public.auto_set_burn(rate, ramp)
        self.ramping_rate = ramp
        in_queue.push_data(PLC_S_DATA.AUTO_BURN_RATE, rate)
    end

    -- check if a timer matches this session's watchdog
    ---@nodiscard
    function public.check_wd(timer)
        return self.plc_conn_watchdog.is_timer(timer) and self.connected
    end

    -- close the connection
    function public.close()
        _close()
        _send_mgmt(SCADA_MGMT_TYPE.CLOSE, {})
        println("connection to reactor " .. reactor_id .. " PLC closed by server")
        log.info(log_header .. "session closed by server")
    end

    -- iterate the session
    ---@nodiscard
    ---@return boolean connected
    function public.iterate()
        if self.connected then
            ------------------
            -- handle queue --
            ------------------

            local handle_start = util.time()

            while in_queue.ready() and self.connected do
                -- get a new message to process
                local message = in_queue.pop()

                if message ~= nil then
                    if message.qtype == mqueue.TYPE.PACKET then
                        -- handle a packet
                        _handle_packet(message.message)
                    elseif message.qtype == mqueue.TYPE.COMMAND then
                        -- handle instruction
                        local cmd = message.message
                        if cmd == PLC_S_CMDS.ENABLE then
                            -- enable reactor
                            if not self.auto_lock then
                                _send(RPLC_TYPE.RPS_ENABLE, {})
                            end
                        elseif cmd == PLC_S_CMDS.SCRAM then
                            -- SCRAM reactor
                            self.acks.scram = false
                            self.retry_times.scram_req = util.time() + INITIAL_WAIT
                            _send(RPLC_TYPE.RPS_SCRAM, {})
                        elseif cmd == PLC_S_CMDS.ASCRAM then
                            -- SCRAM reactor
                            self.acks.ascram = false
                            self.retry_times.ascram_req = util.time() + INITIAL_WAIT
                            _send(RPLC_TYPE.RPS_ASCRAM, {})
                        elseif cmd == PLC_S_CMDS.RPS_RESET then
                            -- reset RPS
                            self.acks.ascram = true
                            self.acks.rps_reset = false
                            self.retry_times.rps_reset_req = util.time() + INITIAL_WAIT
                            _send(RPLC_TYPE.RPS_RESET, {})
                        elseif cmd == PLC_S_CMDS.RPS_AUTO_RESET then
                            if self.sDB.rps_status.automatic or self.sDB.rps_status.timeout then
                                _send(RPLC_TYPE.RPS_AUTO_RESET, {})
                            end
                        else
                            log.warning(log_header .. "unsupported command received in in_queue (this is a bug)")
                        end
                    elseif message.qtype == mqueue.TYPE.DATA then
                        -- instruction with body
                        local cmd = message.message ---@type queue_data
                        if cmd.key == PLC_S_DATA.BURN_RATE then
                            -- update burn rate
                            if not self.auto_lock then
                                cmd.val = math.floor(cmd.val * 10) / 10 -- round to 10ths place
                                if cmd.val > 0 and cmd.val <= self.sDB.mek_struct.max_burn then
                                    self.commanded_burn_rate = cmd.val
                                    self.auto_cmd_token = 0
                                    self.ramping_rate = false
                                    self.acks.burn_rate = false
                                    self.retry_times.burn_rate_req = util.time() + INITIAL_WAIT
                                    _send(RPLC_TYPE.MEK_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate })
                                end
                            end
                        elseif cmd.key == PLC_S_DATA.RAMP_BURN_RATE then
                            -- ramp to burn rate
                            if not self.auto_lock then
                                cmd.val = math.floor(cmd.val * 10) / 10 -- round to 10ths place
                                if cmd.val > 0 and cmd.val <= self.sDB.mek_struct.max_burn then
                                    self.commanded_burn_rate = cmd.val
                                    self.auto_cmd_token = 0
                                    self.ramping_rate = true
                                    self.acks.burn_rate = false
                                    self.retry_times.burn_rate_req = util.time() + INITIAL_WAIT
                                    _send(RPLC_TYPE.MEK_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate })
                                end
                            end
                        elseif cmd.key == PLC_S_DATA.AUTO_BURN_RATE then
                            -- set automatic burn rate
                            if self.auto_lock then
                                cmd.val = math.floor(cmd.val * 100) / 100   -- round to 100ths place
                                if cmd.val >= 0 and cmd.val <= self.sDB.mek_struct.max_burn then
                                    self.auto_cmd_token = util.time_ms()
                                    self.commanded_burn_rate = cmd.val

                                    -- this is only for manual control, only retry auto ramps
                                    self.acks.burn_rate = not self.ramping_rate
                                    self.retry_times.burn_rate_req = util.time() + INITIAL_AUTO_WAIT

                                    _send(RPLC_TYPE.AUTO_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate, self.auto_cmd_token })
                                end
                            end
                        else
                            log.warning(log_header .. "unsupported data command received in in_queue (this is a bug)")
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
                println("connection to reactor " .. reactor_id .. " PLC closed by remote host")
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
                _send_mgmt(SCADA_MGMT_TYPE.KEEP_ALIVE, { util.time() })
                periodics.keep_alive = 0
            end

            self.periodics.last_update = util.time()

            ---------------------
            -- attempt retries --
            ---------------------

            local rtimes = self.retry_times

            if (not self.sDB.no_reactor) and self.sDB.formed then
                -- struct request retry

                if not self.received_struct then
                    if rtimes.struct_req - util.time() <= 0 then
                        _send(RPLC_TYPE.MEK_STRUCT, {})
                        rtimes.struct_req = util.time() + RETRY_PERIOD
                    end
                end

                -- status cache request retry

                if not self.received_status_cache then
                    if rtimes.status_req - util.time() <= 0 then
                        _send(RPLC_TYPE.MEK_STATUS, {})
                        rtimes.status_req = util.time() + RETRY_PERIOD
                    end
                end

                -- burn rate request retry

                if not self.acks.burn_rate then
                    if rtimes.burn_rate_req - util.time() <= 0 then
                        if self.auto_cmd_token > 0 then
                            if self.auto_lock then
                                _send(RPLC_TYPE.AUTO_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate, self.auto_cmd_token })
                            else
                                -- would have been an auto command, but disengaged, so stop retrying
                                self.acks.burn_rate = true
                            end
                        elseif not self.auto_lock then
                            _send(RPLC_TYPE.MEK_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate })
                        else
                            -- shouldn't be in this state, just pretend it was acknowledged
                            self.acks.burn_rate = true
                        end

                        rtimes.burn_rate_req = util.time() + RETRY_PERIOD
                    end
                end
            end

            -- SCRAM request retry

            if not self.acks.scram then
            if rtimes.scram_req - util.time() <= 0 then
                    _send(RPLC_TYPE.RPS_SCRAM, {})
                    rtimes.scram_req = util.time() + RETRY_PERIOD
                end
            end

            -- automatic SCRAM request retry

            if not self.acks.ascram then
                if rtimes.ascram_req - util.time() <= 0 then
                    _send(RPLC_TYPE.RPS_ASCRAM, {})
                    rtimes.ascram_req = util.time() + RETRY_PERIOD
                end
            end

            -- RPS reset request retry

            if not self.acks.rps_reset then
                if rtimes.rps_reset_req - util.time() <= 0 then
                    _send(RPLC_TYPE.RPS_RESET, {})
                    rtimes.rps_reset_req = util.time() + RETRY_PERIOD
                end
            end
        end

        return self.connected
    end

    return public
end

return plc
