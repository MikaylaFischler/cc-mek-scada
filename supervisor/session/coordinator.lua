local comms    = require("scada-common.comms")
local log      = require("scada-common.log")
local mqueue   = require("scada-common.mqueue")
local util     = require("scada-common.util")

local svqtypes = require("supervisor.session.svqtypes")

local coordinator = {}

local PROTOCOLS = comms.PROTOCOLS
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES
local SCADA_CRDN_TYPES = comms.SCADA_CRDN_TYPES
local CRDN_COMMANDS = comms.CRDN_COMMANDS

local SV_Q_CMDS = svqtypes.SV_Q_CMDS
local SV_Q_DATA = svqtypes.SV_Q_DATA

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

-- retry time constants in ms
local INITIAL_WAIT = 1500
local RETRY_PERIOD = 1000

local CRD_S_CMDS = {
    RESEND_BUILDS = 1
}

local CRD_S_DATA = {
    CMD_ACK = 1
}

coordinator.CRD_S_CMDS = CRD_S_CMDS
coordinator.CRD_S_DATA = CRD_S_DATA

local PERIODICS = {
    KEEP_ALIVE = 2000,
    STATUS = 500
}

-- coordinator supervisor session
---@param id integer
---@param in_queue mqueue
---@param out_queue mqueue
---@param facility_units table
function coordinator.new_session(id, in_queue, out_queue, facility_units)
    local log_header = "crdn_session(" .. id .. "): "

    local self = {
        id = id,
        in_q = in_queue,
        out_q = out_queue,
        units = facility_units,
        -- connection properties
        seq_num = 0,
        r_seq_num = nil,
        connected = true,
        conn_watchdog = util.new_watchdog(3),
        last_rtt = 0,
        -- periodic messages
        periodics = {
            last_update = 0,
            keep_alive = 0,
            status_packet = 0
        },
        -- when to next retry one of these messages
        retry_times = {
            builds_packet = 0
        },
        -- message acknowledgements
        acks = {
            builds = false
        }
    }

    -- mark this coordinator session as closed, stop watchdog
    local function _close()
        self.conn_watchdog.cancel()
        self.connected = false
    end

    -- send a CRDN packet
    ---@param msg_type SCADA_CRDN_TYPES
    ---@param msg table
    local function _send(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local c_pkt = comms.crdn_packet()

        c_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.SCADA_CRDN, c_pkt.raw_sendable())

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

    -- send unit builds
    local function _send_builds()
        self.acks.builds = false

        local builds = {}

        for i = 1, #self.units do
            local unit = self.units[i]  ---@type reactor_unit
            builds[unit.get_id()] = unit.get_build()
        end

        _send(SCADA_CRDN_TYPES.STRUCT_BUILDS, builds)
    end

    -- send unit statuses
    local function _send_status()
        local status = {}

        for i = 1, #self.units do
            local unit = self.units[i]  ---@type reactor_unit
            status[unit.get_id()] = { unit.get_reactor_status(), unit.get_annunciator(), unit.get_alarms(), unit.get_rtu_statuses() }
        end

        _send(SCADA_CRDN_TYPES.UNIT_STATUSES, status)
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
        if pkt.scada_frame.protocol() == PROTOCOLS.SCADA_MGMT then
            if pkt.type == SCADA_MGMT_TYPES.KEEP_ALIVE then
                -- keep alive reply
                if pkt.length == 2 then
                    local srv_start = pkt.data[1]
                    local coord_send = pkt.data[2]
                    local srv_now = util.time()
                    self.last_rtt = srv_now - srv_start

                    if self.last_rtt > 500 then
                        log.warning(log_header .. "COORD KEEP_ALIVE round trip time > 500ms (" .. self.last_rtt .. "ms)")
                    end

                    -- log.debug(log_header .. "COORD RTT = " .. self.last_rtt .. "ms")
                    -- log.debug(log_header .. "COORD TT  = " .. (srv_now - coord_send) .. "ms")
                else
                    log.debug(log_header .. "SCADA keep alive packet length mismatch")
                end
            elseif pkt.type == SCADA_MGMT_TYPES.CLOSE then
                -- close the session
                _close()
            else
                log.debug(log_header .. "handler received unsupported SCADA_MGMT packet type " .. pkt.type)
            end
        elseif pkt.scada_frame.protocol() == PROTOCOLS.SCADA_CRDN then
            if pkt.type == SCADA_CRDN_TYPES.STRUCT_BUILDS then
                -- acknowledgement to coordinator receiving builds
                self.acks.builds = true
            elseif pkt.type == SCADA_CRDN_TYPES.COMMAND_UNIT then
                if pkt.length >= 2 then
                    -- get command and unit id
                    local cmd = pkt.data[1]
                    local uid = pkt.data[2]

                    -- pkt.data[3] will be nil except for some commands
                    local data = { uid, pkt.data[3] }

                    -- continue if valid unit id
                    if util.is_int(uid) and uid > 0 and uid <= #self.units then
                        local unit = self.units[uid]    ---@type reactor_unit

                        if cmd == CRDN_COMMANDS.START then
                            self.out_q.push_data(SV_Q_DATA.START, data)
                        elseif cmd == CRDN_COMMANDS.SCRAM then
                            self.out_q.push_data(SV_Q_DATA.SCRAM, data)
                        elseif cmd == CRDN_COMMANDS.RESET_RPS then
                            self.out_q.push_data(SV_Q_DATA.RESET_RPS, data)
                        elseif cmd == CRDN_COMMANDS.SET_BURN then
                            if pkt.length == 3 then
                                self.out_q.push_data(SV_Q_DATA.SET_BURN, data)
                            else
                                log.debug(log_header .. "CRDN command unit burn rate missing option")
                            end
                        elseif cmd == CRDN_COMMANDS.SET_WASTE then
                            if pkt.length == 3 then
                                unit.set_waste(pkt.data[3])
                            else
                                log.debug(log_header .. "CRDN command unit set waste missing option")
                            end
                        elseif cmd == CRDN_COMMANDS.ACK_ALL_ALARMS then
                            unit.ack_all()
                            _send(SCADA_CRDN_TYPES.COMMAND_UNIT, { cmd, uid, true })
                        elseif cmd == CRDN_COMMANDS.ACK_ALARM then
                            if pkt.length == 3 then
                                unit.ack_alarm(pkt.data[3])
                            else
                                log.debug(log_header .. "CRDN command unit ack alarm missing id")
                            end
                        elseif cmd == CRDN_COMMANDS.RESET_ALARM then
                            if pkt.length == 3 then
                                unit.reset_alarm(pkt.data[3])
                            else
                                log.debug(log_header .. "CRDN command unit reset alarm missing id")
                            end
                        else
                            log.debug(log_header .. "CRDN command unknown")
                        end
                    else
                        log.debug(log_header .. "CRDN command unit invalid")
                    end
                else
                    log.debug(log_header .. "CRDN command unit packet length mismatch")
                end
            else
                log.debug(log_header .. "handler received unexpected SCADA_CRDN packet type " .. pkt.type)
            end
        end
    end

    ---@class coord_session
    local public = {}

    -- get the session ID
    function public.get_id() return self.id end

    -- check if a timer matches this session's watchdog
    function public.check_wd(timer)
        return self.conn_watchdog.is_timer(timer) and self.connected
    end

    -- close the connection
    function public.close()
        _close()
        _send_mgmt(SCADA_MGMT_TYPES.CLOSE, {})
        println("connection to coordinator " .. self.id .. " closed by server")
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
                        if cmd == CRD_S_CMDS.RESEND_BUILDS then
                            -- re-send builds
                            self.acks.builds = false
                            self.retry_times.builds_packet = util.time() + RETRY_PERIOD
                            _send_builds()
                        end
                    elseif message.qtype == mqueue.TYPE.DATA then
                        -- instruction with body
                        local cmd = message.message ---@type queue_data

                        if cmd.key == CRD_S_DATA.CMD_ACK then
                            local ack = cmd.val ---@type coord_ack
                            _send(SCADA_CRDN_TYPES.COMMAND_UNIT, { ack.cmd, ack.unit, ack.ack })
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
                println("connection to coordinator " .. self.id .. " closed by remote host")
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

            -- unit statuses to coordinator

            periodics.status_packet = periodics.status_packet + elapsed
            if periodics.status_packet >= PERIODICS.STATUS then
                _send_status()
                periodics.status_packet = 0
            end

            self.periodics.last_update = util.time()

            ---------------------
            -- attempt retries --
            ---------------------

            local rtimes = self.retry_times

            -- builds packet retry

            if not self.acks.builds then
                if rtimes.builds_packet - util.time() <= 0 then
                    _send_builds()
                    rtimes.builds_packet = util.time() + RETRY_PERIOD
                end
            end
        end

        return self.connected
    end

    return public
end

return coordinator
