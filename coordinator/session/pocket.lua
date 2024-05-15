local comms     = require("scada-common.comms")
local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local util      = require("scada-common.util")

local iocontrol = require("coordinator.iocontrol")

local pocket = {}

local PROTOCOL = comms.PROTOCOL
local CRDN_TYPE = comms.CRDN_TYPE
local MGMT_TYPE = comms.MGMT_TYPE

-- retry time constants in ms
-- local INITIAL_WAIT = 1500
-- local RETRY_PERIOD = 1000

local API_S_CMDS = {
}

local API_S_DATA = {
}

pocket.API_S_CMDS = API_S_CMDS
pocket.API_S_DATA = API_S_DATA

local PERIODICS = {
    KEEP_ALIVE = 2000
}

-- pocket API session
---@nodiscard
---@param id integer session ID
---@param s_addr integer device source address
---@param in_queue mqueue in message queue
---@param out_queue mqueue out message queue
---@param timeout number communications timeout
function pocket.new_session(id, s_addr, in_queue, out_queue, timeout)
    local log_header = "pkt_session(" .. id .. "): "

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
        ---@class api_db
        sDB = {
        }
    }

    ---@class pkt_session
    local public = {}

    -- mark this pocket session as closed, stop watchdog
    local function _close()
        self.conn_watchdog.cancel()
        self.connected = false
        iocontrol.fp_pkt_disconnected(id)
    end

    -- send a CRDN packet
    ---@param msg_type CRDN_TYPE
    ---@param msg table
    local function _send(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local c_pkt = comms.crdn_packet()

        c_pkt.make(msg_type, msg)
        s_pkt.make(s_addr, self.seq_num, PROTOCOL.SCADA_CRDN, c_pkt.raw_sendable())

        out_queue.push_packet(s_pkt)
        self.seq_num = self.seq_num + 1
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
    ---@param pkt mgmt_frame|crdn_frame
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
        if pkt.scada_frame.protocol() == PROTOCOL.SCADA_CRDN then
            ---@cast pkt crdn_frame

            local db = iocontrol.get_db()

            -- handle packet by type
            if pkt.type == CRDN_TYPE.API_GET_FAC then
                local fac = db.facility

                local data = {
                    fac.all_sys_ok,
                    fac.rtu_count,
                    fac.radiation,
                    { fac.auto_ready, fac.auto_active, fac.auto_ramping, fac.auto_saturated },
                    { fac.auto_current_waste_product, fac.auto_pu_fallback_active },
                    util.table_len(fac.tank_data_tbl),
                    fac.induction_data_tbl[1] ~= nil,
                    fac.sps_data_tbl[1] ~= nil,
                }

                _send(CRDN_TYPE.API_GET_FAC, data)
            elseif pkt.type == CRDN_TYPE.API_GET_UNIT then
                if pkt.length == 1 and type(pkt.data[1]) == "number" then
                    local u = db.units[pkt.data[1]]   ---@type ioctl_unit

                    if u then
                        local data = {
                            u.unit_id,
                            u.connected,
                            u.rtu_hw,
                            u.alarms,
                            u.annunciator,
                            u.reactor_data,
                            u.boiler_data_tbl,
                            u.turbine_data_tbl,
                            u.tank_data_tbl
                        }

                        _send(CRDN_TYPE.API_GET_UNIT, data)
                    end
                end
            else
                log.debug(log_header .. "handler received unsupported CRDN packet type " .. pkt.type)
            end
        elseif pkt.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
            ---@cast pkt mgmt_frame
            if pkt.type == MGMT_TYPE.KEEP_ALIVE then
                -- keep alive reply
                if pkt.length == 2 then
                    local srv_start = pkt.data[1]
                    -- local api_send = pkt.data[2]
                    local srv_now = util.time()
                    self.last_rtt = srv_now - srv_start

                    if self.last_rtt > 750 then
                        log.warning(log_header .. "PKT KEEP_ALIVE round trip time > 750ms (" .. self.last_rtt .. "ms)")
                    end

                    -- log.debug(log_header .. "PKT RTT = " .. self.last_rtt .. "ms")
                    -- log.debug(log_header .. "PKT TT  = " .. (srv_now - api_send) .. "ms")

                    iocontrol.fp_pkt_rtt(id, self.last_rtt)
                else
                    log.debug(log_header .. "SCADA keep alive packet length mismatch")
                end
            elseif pkt.type == MGMT_TYPE.CLOSE then
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

    -- check if a timer matches this session's watchdog
    ---@nodiscard
    function public.check_wd(timer)
        return self.conn_watchdog.is_timer(timer) and self.connected
    end

    -- close the connection
    function public.close()
        _close()
        _send_mgmt(MGMT_TYPE.CLOSE, {})
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
