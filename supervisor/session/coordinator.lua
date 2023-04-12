local comms    = require("scada-common.comms")
local log      = require("scada-common.log")
local mqueue   = require("scada-common.mqueue")
local types    = require("scada-common.types")
local util     = require("scada-common.util")

local svqtypes = require("supervisor.session.svqtypes")

local coordinator = {}

local PROTOCOL = comms.PROTOCOL
local SCADA_MGMT_TYPE = comms.SCADA_MGMT_TYPE
local SCADA_CRDN_TYPE = comms.SCADA_CRDN_TYPE
local UNIT_COMMAND = comms.UNIT_COMMAND
local FAC_COMMAND = comms.FAC_COMMAND

local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE

local SV_Q_DATA = svqtypes.SV_Q_DATA

local println = util.println

-- retry time constants in ms
-- local INITIAL_WAIT = 1500
local RETRY_PERIOD = 1000
local PARTIAL_RETRY_PERIOD = 2000

local CRD_S_CMDS = {
}

local CRD_S_DATA = {
    CMD_ACK = 1,
    RESEND_PLC_BUILD = 2,
    RESEND_RTU_BUILD = 3
}

coordinator.CRD_S_CMDS = CRD_S_CMDS
coordinator.CRD_S_DATA = CRD_S_DATA

local PERIODICS = {
    KEEP_ALIVE = 2000,
    STATUS = 500
}

-- coordinator supervisor session
---@nodiscard
---@param id integer session ID
---@param in_queue mqueue in message queue
---@param out_queue mqueue out message queue
---@param timeout number communications timeout
---@param facility facility facility data table
function coordinator.new_session(id, in_queue, out_queue, timeout, facility)
    local log_header = "crdn_session(" .. id .. "): "

    local self = {
        units = facility.get_units(),
        -- connection properties
        seq_num = 0,
        r_seq_num = nil,
        connected = true,
        conn_watchdog = util.new_watchdog(timeout),
        last_rtt = 0,
        -- periodic messages
        periodics = {
            last_update = 0,
            keep_alive = 0,
            status_packet = 0
        },
        -- when to next retry one of these messages
        retry_times = {
            builds_packet = 0,
            f_builds_packet = 0,
            u_builds_packet = 0
        },
        -- message acknowledgements
        acks = {
            builds = false,
            fac_builds = false,
            unit_builds = false
        }
    }

    -- mark this coordinator session as closed, stop watchdog
    local function _close()
        self.conn_watchdog.cancel()
        self.connected = false
    end

    -- send a CRDN packet
    ---@param msg_type SCADA_CRDN_TYPE
    ---@param msg table
    local function _send(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local c_pkt = comms.crdn_packet()

        c_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOL.SCADA_CRDN, c_pkt.raw_sendable())

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

    -- send both facility and unit builds
    local function _send_all_builds()
        local unit_builds = {}

        for i = 1, #self.units do
            local unit = self.units[i]  ---@type reactor_unit
            unit_builds[unit.get_id()] = unit.get_build()
        end

        _send(SCADA_CRDN_TYPE.INITIAL_BUILDS, { facility.get_build(), unit_builds })
    end

    -- send facility builds
    local function _send_fac_builds()
        _send(SCADA_CRDN_TYPE.FAC_BUILDS, { facility.get_build() })
    end

    -- send unit builds
    local function _send_unit_builds()
        local builds = {}

        for i = 1, #self.units do
            local unit = self.units[i]  ---@type reactor_unit
            builds[unit.get_id()] = unit.get_build()
        end

        _send(SCADA_CRDN_TYPE.UNIT_BUILDS, { builds })
    end

    -- send facility status
    local function _send_fac_status()
        local status = {
            facility.get_control_status(),
            facility.get_rtu_statuses()
        }

        _send(SCADA_CRDN_TYPE.FAC_STATUS, status)
    end

    -- send unit statuses
    local function _send_unit_statuses()
        local status = {}

        for i = 1, #self.units do
            local unit = self.units[i]  ---@type reactor_unit

            status[unit.get_id()] = {
                unit.get_reactor_status(),
                unit.get_rtu_statuses(),
                unit.get_annunciator(),
                unit.get_alarms(),
                unit.get_state()
            }
        end

        _send(SCADA_CRDN_TYPE.UNIT_STATUSES, status)
    end

    -- handle a packet
    ---@param pkt crdn_frame
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

        -- feed watchdog
        self.conn_watchdog.feed()

        -- process packet
        if pkt.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
            if pkt.type == SCADA_MGMT_TYPE.KEEP_ALIVE then
                -- keep alive reply
                if pkt.length == 2 then
                    local srv_start = pkt.data[1]
                    -- local coord_send = pkt.data[2]
                    local srv_now = util.time()
                    self.last_rtt = srv_now - srv_start

                    if self.last_rtt > 750 then
                        log.warning(log_header .. "COORD KEEP_ALIVE round trip time > 750ms (" .. self.last_rtt .. "ms)")
                    end

                    -- log.debug(log_header .. "COORD RTT = " .. self.last_rtt .. "ms")
                    -- log.debug(log_header .. "COORD TT  = " .. (srv_now - coord_send) .. "ms")
                else
                    log.debug(log_header .. "SCADA keep alive packet length mismatch")
                end
            elseif pkt.type == SCADA_MGMT_TYPE.CLOSE then
                -- close the session
                _close()
            else
                log.debug(log_header .. "handler received unsupported SCADA_MGMT packet type " .. pkt.type)
            end
        elseif pkt.scada_frame.protocol() == PROTOCOL.SCADA_CRDN then
            if pkt.type == SCADA_CRDN_TYPE.INITIAL_BUILDS then
                -- acknowledgement to coordinator receiving builds
                self.acks.builds = true
            elseif pkt.type == SCADA_CRDN_TYPE.FAC_BUILDS then
                -- acknowledgement to coordinator receiving builds
                self.acks.fac_builds = true
            elseif pkt.type == SCADA_CRDN_TYPE.FAC_CMD then
                if pkt.length >= 1 then
                    local cmd = pkt.data[1]

                    if cmd == FAC_COMMAND.SCRAM_ALL then
                        facility.scram_all()
                        _send(SCADA_CRDN_TYPE.FAC_CMD, { cmd, true })
                    elseif cmd == FAC_COMMAND.STOP then
                        facility.auto_stop()
                        _send(SCADA_CRDN_TYPE.FAC_CMD, { cmd, true })
                    elseif cmd == FAC_COMMAND.START then
                        if pkt.length == 6 then
                            ---@type coord_auto_config
                            local config = {
                                mode = pkt.data[2],
                                burn_target = pkt.data[3],
                                charge_target = pkt.data[4],
                                gen_target = pkt.data[5],
                                limits = pkt.data[6]
                            }

                            _send(SCADA_CRDN_TYPE.FAC_CMD, { cmd, table.unpack(facility.auto_start(config)) })
                        else
                            log.debug(log_header .. "CRDN auto start (with configuration) packet length mismatch")
                        end
                    elseif cmd == FAC_COMMAND.ACK_ALL_ALARMS then
                        facility.ack_all()
                        _send(SCADA_CRDN_TYPE.FAC_CMD, { cmd, true })
                    else
                        log.debug(log_header .. "CRDN facility command unknown")
                    end
                else
                    log.debug(log_header .. "CRDN facility command packet length mismatch")
                end
            elseif pkt.type == SCADA_CRDN_TYPE.UNIT_BUILDS then
                -- acknowledgement to coordinator receiving builds
                self.acks.unit_builds = true
            elseif pkt.type == SCADA_CRDN_TYPE.UNIT_CMD then
                if pkt.length >= 2 then
                    -- get command and unit id
                    local cmd = pkt.data[1]
                    local uid = pkt.data[2]

                    -- pkt.data[3] will be nil except for some commands
                    local data = { uid, pkt.data[3] }

                    -- continue if valid unit id
                    if util.is_int(uid) and uid > 0 and uid <= #self.units then
                        local unit = self.units[uid]    ---@type reactor_unit

                        if cmd == UNIT_COMMAND.START then
                            out_queue.push_data(SV_Q_DATA.START, data)
                        elseif cmd == UNIT_COMMAND.SCRAM then
                            out_queue.push_data(SV_Q_DATA.SCRAM, data)
                        elseif cmd == UNIT_COMMAND.RESET_RPS then
                            out_queue.push_data(SV_Q_DATA.RESET_RPS, data)
                        elseif cmd == UNIT_COMMAND.SET_BURN then
                            if pkt.length == 3 then
                                out_queue.push_data(SV_Q_DATA.SET_BURN, data)
                            else
                                log.debug(log_header .. "CRDN unit command burn rate missing option")
                            end
                        elseif cmd == UNIT_COMMAND.SET_WASTE then
                            if (pkt.length == 3) and (type(pkt.data[3]) == "number") and (pkt.data[3] > 0) and (pkt.data[3] <= 4) then
                                unit.set_waste(pkt.data[3])
                            else
                                log.debug(log_header .. "CRDN unit command set waste missing option")
                            end
                        elseif cmd == UNIT_COMMAND.ACK_ALL_ALARMS then
                            unit.ack_all()
                            _send(SCADA_CRDN_TYPE.UNIT_CMD, { cmd, uid, true })
                        elseif cmd == UNIT_COMMAND.ACK_ALARM then
                            if pkt.length == 3 then
                                unit.ack_alarm(pkt.data[3])
                            else
                                log.debug(log_header .. "CRDN unit command ack alarm missing alarm id")
                            end
                        elseif cmd == UNIT_COMMAND.RESET_ALARM then
                            if pkt.length == 3 then
                                unit.reset_alarm(pkt.data[3])
                            else
                                log.debug(log_header .. "CRDN unit command reset alarm missing alarm id")
                            end
                        elseif cmd == UNIT_COMMAND.SET_GROUP then
                            if (pkt.length == 3) and (type(pkt.data[3]) == "number") and (pkt.data[3] >= 0) and (pkt.data[3] <= 4) then
                                facility.set_group(unit.get_id(), pkt.data[3])
                                _send(SCADA_CRDN_TYPE.UNIT_CMD, { cmd, uid, pkt.data[3] })
                            else
                                log.debug(log_header .. "CRDN unit command set group missing group id")
                            end
                        else
                            log.debug(log_header .. "CRDN unit command unknown")
                        end
                    else
                        log.debug(log_header .. "CRDN unit command invalid")
                    end
                else
                    log.debug(log_header .. "CRDN unit command packet length mismatch")
                end
            else
                log.debug(log_header .. "handler received unexpected SCADA_CRDN packet type " .. pkt.type)
            end
        end
    end

    ---@class coord_session
    local public = {}

    -- get the session ID
    ---@nodiscard
    function public.get_id() return id end

    -- check if a timer matches this session's watchdog
    ---@nodiscard
    function public.check_wd(timer)
        return self.conn_watchdog.is_timer(timer) and self.connected
    end

    -- close the connection
    function public.close()
        _close()
        _send_mgmt(SCADA_MGMT_TYPE.CLOSE, {})
        println("connection to coordinator " .. id .. " closed by server")
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
                    elseif message.qtype == mqueue.TYPE.DATA then
                        -- instruction with body
                        local cmd = message.message ---@type queue_data

                        if cmd.key == CRD_S_DATA.CMD_ACK then
                            local ack = cmd.val ---@type coord_ack
                            _send(SCADA_CRDN_TYPE.UNIT_CMD, { ack.cmd, ack.unit, ack.ack })
                        elseif cmd.key == CRD_S_DATA.RESEND_PLC_BUILD then
                            -- re-send PLC build
                            -- retry logic will be kept as-is, so as long as no retry is needed, this will be a small update
                            self.retry_times.builds_packet = util.time() + PARTIAL_RETRY_PERIOD
                            self.acks.unit_builds = false

                            local unit_id = cmd.val
                            local builds = {}

                            local unit = self.units[unit_id]    ---@type reactor_unit
                            builds[unit_id] = unit.get_build(true, false, false)

                            _send(SCADA_CRDN_TYPE.UNIT_BUILDS, { builds })
                        elseif cmd.key == CRD_S_DATA.RESEND_RTU_BUILD then
                            local unit_id = cmd.val.unit
                            if unit_id > 0 then
                                -- re-send unit RTU builds
                                -- retry logic will be kept as-is, so as long as no retry is needed, this will be a small update
                                self.retry_times.u_builds_packet = util.time() + PARTIAL_RETRY_PERIOD
                                self.acks.unit_builds = false

                                local builds = {}

                                local unit = self.units[unit_id]    ---@type reactor_unit
                                builds[unit_id] = unit.get_build(false, cmd.val.type == RTU_UNIT_TYPE.BOILER_VALVE, cmd.val.type == RTU_UNIT_TYPE.TURBINE_VALVE)

                                _send(SCADA_CRDN_TYPE.UNIT_BUILDS, { builds })
                            else
                                -- re-send facility RTU builds
                                -- retry logic will be kept as-is, so as long as no retry is needed, this will be a small update
                                self.retry_times.f_builds_packet = util.time() + PARTIAL_RETRY_PERIOD
                                self.acks.fac_builds = false

                                _send(SCADA_CRDN_TYPE.FAC_BUILDS, { facility.get_build(cmd.val.type == RTU_UNIT_TYPE.IMATRIX) })
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
                println("connection to coordinator closed by remote host")
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

            -- statuses to coordinator

            periodics.status_packet = periodics.status_packet + elapsed
            if periodics.status_packet >= PERIODICS.STATUS then
                _send_fac_status()
                _send_unit_statuses()
                periodics.status_packet = 0
            end

            self.periodics.last_update = util.time()

            ---------------------
            -- attempt retries --
            ---------------------

            local rtimes = self.retry_times

            -- builds packet retries

            if not self.acks.builds then
                if rtimes.builds_packet - util.time() <= 0 then
                    _send_all_builds()
                    rtimes.builds_packet = util.time() + RETRY_PERIOD
                end
            end

            if not self.acks.fac_builds then
                if rtimes.f_builds_packet - util.time() <= 0 then
                    _send_fac_builds()
                    rtimes.f_builds_packet = util.time() + RETRY_PERIOD
                end
            end

            if not self.acks.unit_builds then
                if rtimes.u_builds_packet - util.time() <= 0 then
                    _send_unit_builds()
                    rtimes.u_builds_packet = util.time() + RETRY_PERIOD
                end
            end
        end

        return self.connected
    end

    return public
end

return coordinator
