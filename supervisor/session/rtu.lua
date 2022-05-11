local comms = require("scada-common.comms")
local log = require("scada-common.log")
local mqueue = require("scada-common.mqueue")
local util = require("scada-common.util")

local rtu = {}

local PROTOCOLS = comms.PROTOCOLS
local RPLC_TYPES = comms.RPLC_TYPES
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local PERIODICS = {
    KEEP_ALIVE = 2.0
}

rtu.new_session = function (id, in_queue, out_queue)
    local log_header = "rtu_session(" .. id .. "): "

    local self = {
        id = id,
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
        rtu_conn_watchdog = util.new_watchdog(3),
        last_rtt = 0
    }

    -- send a MODBUS TCP packet
    local _send_modbus = function (m_pkt)
        local s_pkt = comms.scada_packet()
        s_pkt.make(self.seq_num, PROTOCOLS.MODBUS_TCP, m_pkt.raw_sendable())
        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
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

    -- handle a packet
    local _handle_packet = function (pkt)
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
        self.rtu_conn_watchdog.feed()

        -- process packet
        if pkt.scada_frame.protocol() == PROTOCOLS.MODBUS_TCP then
        elseif pkt.scada_frame.protocol() == PROTOCOLS.SCADA_MGMT then

            if pkt.type == SCADA_MGMT_TYPES.KEEP_ALIVE then
                -- keep alive reply
                if pkt.length == 2 then
                    local srv_start = pkt.data[1]
                    local rtu_send = pkt.data[2]
                    local srv_now = util.time()
                    self.last_rtt = srv_now - srv_start

                    if self.last_rtt > 500 then
                        log.warning(log_header .. "RTU KEEP_ALIVE round trip time > 500ms (" .. self.last_rtt .. "ms)")
                    end

                    -- log.debug(log_header .. "RTU RTT = ".. self.last_rtt .. "ms")
                    -- log.debug(log_header .. "RTU TT  = ".. (srv_now - rtu_send) .. "ms")
                else
                    log.debug(log_header .. "SCADA keep alive packet length mismatch")
                end
            elseif pkt.type == SCADA_MGMT_TYPES.CLOSE then
                -- close the session
                self.connected = false
            elseif pkt.type == SCADA_MGMT_TYPES.RTU_ADVERT then
                -- RTU unit advertisement
                for i = 1, pkt.length do
                    local unit = pkt.data[i]    ---@type rtu_advertisement
                end
            else
                log.debug(log_header .. "handler received unsupported SCADA_MGMT packet type " .. pkt.type)
            end
        end
    end

    -- PUBLIC FUNCTIONS --

    -- get the session ID
    local get_id = function () return self.id end

    -- check if a timer matches this session's watchdog
    local check_wd = function (timer)
        return self.rtu_conn_watchdog.is_timer(timer)
    end

    -- close the connection
    local close = function ()
        self.rtu_conn_watchdog.cancel()
        self.connected = false
        _send_mgmt(SCADA_MGMT_TYPES.CLOSE, {})
        println(log_header .. "connection to RTU closed by server")
        log.info(log_header .. "session closed by server")
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
                elseif message.qtype == mqueue.TYPE.DATA then
                    -- instruction with body
                    local cmd = message.message
                end

                -- max 100ms spent processing queue
                if util.time() - handle_start > 100 then
                    log.warning(log_header .. "exceeded 100ms queue process limit")
                    break
                end
            end

            -- exit if connection was closed
            if not self.connected then
                self.rtu_conn_watchdog.cancel()
                println(log_header .. "connection to RTU closed by remote host")
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
        end

        return self.connected
    end

    return {
        get_id = get_id,
        check_wd = check_wd,
        close = close,
        iterate = iterate
    }
end

return rtu
