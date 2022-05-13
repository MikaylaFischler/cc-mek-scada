local comms = require("scada-common.comms")
local log = require("scada-common.log")
local mqueue = require("scada-common.mqueue")
local util = require("scada-common.util")

-- supervisor rtu sessions (svrs)
local svrs_boiler = require("supervisor.session.rtu.boiler")
local svrs_emachine = require("supervisor.session.rtu.emachine")
local svrs_turbine = require("supervisor.session.rtu.turbine")

local rtu = {}

local PROTOCOLS = comms.PROTOCOLS
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES
local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local PERIODICS = {
    KEEP_ALIVE = 2.0
}

-- create a new RTU session
---@param id integer
---@param in_queue mqueue
---@param out_queue mqueue
---@param advertisement table
rtu.new_session = function (id, in_queue, out_queue, advertisement)
    local log_header = "rtu_session(" .. id .. "): "

    local self = {
        id = id,
        in_q = in_queue,
        out_q = out_queue,
        advert = advertisement,
        -- connection properties
        seq_num = 0,
        r_seq_num = nil,
        connected = true,
        rtu_conn_watchdog = util.new_watchdog(3),
        last_rtt = 0,
        units = {}
    }

    ---@class rtu_session
    local public = {}

    -- parse the recorded advertisement
    local _parse_advertisement = function ()
        self.units = {}
        for i = 1, #self.advert do
            local unit = nil    ---@type unit_session

            ---@type rtu_advertisement
            local unit_advert = {
                type = self.advert[i][0],
                index = self.advert[i][1],
                reactor = self.advert[i][2],
                rsio = self.advert[i][3]
            }

            local u_type = unit_advert.type

            -- create unit by type
            if u_type == RTU_UNIT_TYPES.REDSTONE then

            elseif u_type == RTU_UNIT_TYPES.BOILER then
                unit = svrs_boiler.new(self.id, unit_advert, self.out_q)
            elseif u_type == RTU_UNIT_TYPES.BOILER_VALVE then
                -- @todo Mekanism 10.1+
            elseif u_type == RTU_UNIT_TYPES.TURBINE then
                unit = svrs_turbine.new(self.id, unit_advert, self.out_q)
            elseif u_type == RTU_UNIT_TYPES.TURBINE_VALVE then
                -- @todo Mekanism 10.1+
            elseif u_type == RTU_UNIT_TYPES.EMACHINE then
                unit = svrs_emachine.new(self.id, unit_advert, self.out_q)
            elseif u_type == RTU_UNIT_TYPES.IMATRIX then
                -- @todo Mekanism 10.1+
            end

            if unit ~= nil then
                table.insert(self.units, unit)
            else
                self.units = {}
                log.error(log_header .. "bad advertisement; encountered unsupported RTU type")
                break
            end
        end
    end

    -- send a MODBUS TCP packet
    ---@param m_pkt modbus_packet
    local _send_modbus = function (m_pkt)
        local s_pkt = comms.scada_packet()
        s_pkt.make(self.seq_num, PROTOCOLS.MODBUS_TCP, m_pkt.raw_sendable())
        self.modem.transmit(self.s_port, self.l_port, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- send a SCADA management packet
    ---@param msg_type SCADA_MGMT_TYPES
    ---@param msg table
    local _send_mgmt = function (msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.SCADA_MGMT, m_pkt.raw_sendable())

        self.out_q.push_packet(s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- handle a packet
    ---@param pkt modbus_frame|mgmt_frame
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
            if self.units[pkt.unit_id] ~= nil then
                local unit = self.units[pkt.unit_id]    ---@type unit_session
                unit.handle_packet(pkt)
            end
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
                self.advert = pkt.data
                _parse_advertisement()
            else
                log.debug(log_header .. "handler received unsupported SCADA_MGMT packet type " .. pkt.type)
            end
        end
    end

    -- PUBLIC FUNCTIONS --

    -- get the session ID
    public.get_id = function () return self.id end

    -- check if a timer matches this session's watchdog
    ---@param timer number
    public.check_wd = function (timer)
        return self.rtu_conn_watchdog.is_timer(timer)
    end

    -- close the connection
    public.close = function ()
        self.rtu_conn_watchdog.cancel()
        self.connected = false
        _send_mgmt(SCADA_MGMT_TYPES.CLOSE, {})
        println(log_header .. "connection to RTU closed by server")
        log.info(log_header .. "session closed by server")
    end

    -- iterate the session
    ---@return boolean connected
    public.iterate = function ()
        if self.connected then
            ------------------
            -- update units --
            ------------------

            for i = 1, #self.units do
                self.units[i].update()
            end

            ------------------
            -- handle queue --
            ------------------

            local handle_start = util.time()

            while self.in_q.ready() and self.connected do
                -- get a new message to process
                local msg = self.in_q.pop()

                if msg ~= nil then
                    if msg.qtype == mqueue.TYPE.PACKET then
                        -- handle a packet
                        _handle_packet(msg.message)
                    elseif msg.qtype == mqueue.TYPE.COMMAND then
                        -- handle instruction
                    elseif msg.qtype == mqueue.TYPE.DATA then
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

    return public
end

return rtu
