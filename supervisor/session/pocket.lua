local comms   = require("scada-common.comms")
local log     = require("scada-common.log")
local mqueue  = require("scada-common.mqueue")
local util    = require("scada-common.util")
local databus = require("supervisor.databus")

local pocket = {}

local PROTOCOL = comms.PROTOCOL
local MGMT_TYPE = comms.MGMT_TYPE

-- retry time constants in ms
-- local INITIAL_WAIT = 1500
-- local RETRY_PERIOD = 1000

local POCKET_S_CMDS = {
}

local POCKET_S_DATA = {
}

pocket.POCKET_S_CMDS = POCKET_S_CMDS
pocket.POCKET_S_DATA = POCKET_S_DATA

local PERIODICS = {
    KEEP_ALIVE = 2000
}

-- pocket diagnostics session
---@nodiscard
---@param id integer session ID
---@param s_addr integer device source address
---@param in_queue mqueue in message queue
---@param out_queue mqueue out message queue
---@param timeout number communications timeout
---@param facility facility facility data table
---@param fp_ok boolean if the front panel UI is running
function pocket.new_session(id, s_addr, in_queue, out_queue, timeout, facility, fp_ok)
    -- print a log message to the terminal as long as the UI isn't running
    local function println(message) if not fp_ok then util.println_ts(message) end end

    local log_header = "pdg_session(" .. id .. "): "

    local self = {
        -- connection properties
        seq_num = 0,
        r_seq_num = nil,
        connected = true,
        conn_watchdog = util.new_watchdog(timeout),
        last_rtt = 0,
        -- periodic messages
        periodics = {
            last_update = 0,
            keep_alive = 0
        },
        -- when to next retry one of these requests
        retry_times = {
        },
        -- command acknowledgements
        acks = {
        },
        -- session database
        ---@class pdg_db
        sDB = {
        }
    }

    ---@class pdg_session
    local public = {}

    -- mark this diagnostics session as closed, stop watchdog
    local function _close()
        self.conn_watchdog.cancel()
        self.connected = false
        databus.tx_pdg_disconnected(id)
    end

    -- send a SCADA management packet
    ---@param msg_type MGMT_TYPE
    ---@param msg table
    local function _send_mgmt(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(s_addr, self.seq_num, PROTOCOL.SCADA_MGMT, m_pkt.raw_sendable())

        out_queue.push_packet(s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- handle a packet
    ---@param pkt mgmt_frame
    local function _handle_packet(pkt)
        -- check sequence number
        if self.r_seq_num == nil then
            self.r_seq_num = pkt.scada_frame.seq_num()
        elseif (self.r_seq_num + 1) ~= pkt.scada_frame.seq_num() then
            log.warning(log_header .. "sequence out-of-order: last = " .. self.r_seq_num .. ", new = " .. pkt.scada_frame.seq_num())
            return
        else
            self.r_seq_num = pkt.scada_frame.seq_num()
        end

        -- feed watchdog
        self.conn_watchdog.feed()

        -- process packet
        if pkt.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
            ---@cast pkt mgmt_frame
            if pkt.type == MGMT_TYPE.KEEP_ALIVE then
                -- keep alive reply
                if pkt.length == 2 then
                    local srv_start = pkt.data[1]
                    -- local pdg_send = pkt.data[2]
                    local srv_now = util.time()
                    self.last_rtt = srv_now - srv_start

                    if self.last_rtt > 750 then
                        log.warning(log_header .. "PDG KEEP_ALIVE round trip time > 750ms (" .. self.last_rtt .. "ms)")
                    end

                    -- log.debug(log_header .. "PDG RTT = " .. self.last_rtt .. "ms")
                    -- log.debug(log_header .. "PDG TT  = " .. (srv_now - pdg_send) .. "ms")

                    databus.tx_pdg_rtt(id, self.last_rtt)
                else
                    log.debug(log_header .. "SCADA keep alive packet length mismatch")
                end
            elseif pkt.type == MGMT_TYPE.CLOSE then
                -- close the session
                _close()
            elseif pkt.type == MGMT_TYPE.DIAG_TONE_GET then
                -- get the state of alarm tones
                _send_mgmt(MGMT_TYPE.DIAG_TONE_GET, facility.get_alarm_tones())
            elseif pkt.type == MGMT_TYPE.DIAG_TONE_SET then
                local valid = false

                -- attempt to set a tone state
                if pkt.scada_frame.is_authenticated() then
                    if pkt.length == 2 then
                        if type(pkt.data[1]) == "number" and type(pkt.data[2]) == "boolean" then
                            valid = true

                            -- try to set tone states, then send back if testing is allowed
                            local allow_testing, test_tone_states = facility.diag_set_test_tone(pkt.data[1], pkt.data[2])
                            _send_mgmt(MGMT_TYPE.DIAG_TONE_SET, { allow_testing, test_tone_states })
                        else
                            log.debug(log_header .. "SCADA diag tone set packet data type mismatch")
                        end
                    else
                        log.debug(log_header .. "SCADA diag tone set packet length mismatch")
                    end
                else
                    log.debug(log_header .. "DIAG_TONE_SET is blocked without HMAC for security")
                end

                if not valid then _send_mgmt(MGMT_TYPE.DIAG_TONE_SET, { false }) end
            elseif pkt.type == MGMT_TYPE.DIAG_ALARM_SET then
                local valid = false

                -- attempt to set an alarm state
                if pkt.scada_frame.is_authenticated() then
                    if pkt.length == 2 then
                        if type(pkt.data[1]) == "number" and type(pkt.data[2]) == "boolean" then
                            valid = true

                            -- try to set alarm states, then send back if testing is allowed
                            local allow_testing, test_alarm_states = facility.diag_set_test_alarm(pkt.data[1], pkt.data[2])
                            _send_mgmt(MGMT_TYPE.DIAG_ALARM_SET, { allow_testing, test_alarm_states })
                        else
                            log.debug(log_header .. "SCADA diag alarm set packet data type mismatch")
                        end
                    else
                        log.debug(log_header .. "SCADA diag alarm set packet length mismatch")
                    end
                else
                    log.debug(log_header .. "DIAG_ALARM_SET is blocked without HMAC for security")
                end

                if not valid then _send_mgmt(MGMT_TYPE.DIAG_ALARM_SET, { false }) end
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

    -- check if a timer matches this session's watchdog
    ---@nodiscard
    function public.check_wd(timer)
        return self.conn_watchdog.is_timer(timer) and self.connected
    end

    -- close the connection
    function public.close()
        _close()
        _send_mgmt(MGMT_TYPE.CLOSE, {})
        println("connection to pocket diag session " .. id .. " closed by server")
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
                println("connection to pocket diag session " .. id .. " closed by remote host")
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
                _send_mgmt(MGMT_TYPE.KEEP_ALIVE, { util.time() })
                periodics.keep_alive = 0
            end

            self.periodics.last_update = util.time()

            ---------------------
            -- attempt retries --
            ---------------------

            -- local rtimes = self.retry_times
        end

        return self.connected
    end

    return public
end

return pocket
