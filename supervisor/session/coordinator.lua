local comms  = require("scada-common.comms")
local log    = require("scada-common.log")
local mqueue = require("scada-common.mqueue")
local util   = require("scada-common.util")

local coordinator = {}

local PROTOCOLS = comms.PROTOCOLS
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES
local SCADA_CRDN_TYPES = comms.SCADA_CRDN_TYPES

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local PERIODICS = {
    KEEP_ALIVE = 2.0
}

-- coordinator supervisor session
---@param id integer
---@param in_queue mqueue
---@param out_queue mqueue
function coordinator.new_session(id, in_queue, out_queue)
    local log_header = "crdn_session(" .. id .. "): "

    local self = {
        id = id,
        in_q = in_queue,
        out_q = out_queue,
        -- connection properties
        seq_num = 0,
        r_seq_num = nil,
        connected = true,
        conn_watchdog = util.new_watchdog(3),
        last_rtt = 0,
        -- periodic messages
        periodics = {
            last_update = 0,
            keep_alive = 0
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
            if pkt.type == SCADA_MGMT_TYPES.KEEP_ALIVE then
            else
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
        println("connection to coordinator #" .. self.id .. " closed by server")
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
                    elseif message.qtype == mqueue.TYPE.DATA then
                        -- instruction with body
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

            self.periodics.last_update = util.time()
        end

        return self.connected
    end

    return public
end

return coordinator
