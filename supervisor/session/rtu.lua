local comms         = require("scada-common.comms")
local log           = require("scada-common.log")
local mqueue        = require("scada-common.mqueue")
local types         = require("scada-common.types")
local util          = require("scada-common.util")

local databus       = require("supervisor.databus")

local svqtypes      = require("supervisor.session.svqtypes")

-- supervisor rtu sessions (svrs)
local unit_session  = require("supervisor.session.rtu.unit_session")
local svrs_boilerv  = require("supervisor.session.rtu.boilerv")
local svrs_dynamicv = require("supervisor.session.rtu.dynamicv")
local svrs_envd     = require("supervisor.session.rtu.envd")
local svrs_imatrix  = require("supervisor.session.rtu.imatrix")
local svrs_redstone = require("supervisor.session.rtu.redstone")
local svrs_sna      = require("supervisor.session.rtu.sna")
local svrs_sps      = require("supervisor.session.rtu.sps")
local svrs_turbinev = require("supervisor.session.rtu.turbinev")

local rtu = {}

local PROTOCOL = comms.PROTOCOL
local MGMT_TYPE = comms.MGMT_TYPE
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE

local PERIODICS = {
    KEEP_ALIVE = 2000,
    ALARM_TONES = 500
}

-- create a new RTU session
---@nodiscard
---@param id integer session ID
---@param s_addr integer device source address
---@param in_queue mqueue in message queue
---@param out_queue mqueue out message queue
---@param timeout number communications timeout
---@param advertisement table RTU device advertisement
---@param facility facility facility data table
---@param fp_ok boolean if the front panel UI is running
function rtu.new_session(id, s_addr, in_queue, out_queue, timeout, advertisement, facility, fp_ok)
    -- print a log message to the terminal as long as the UI isn't running
    local function println(message) if not fp_ok then util.println_ts(message) end end

    local log_header = "rtu_session(" .. id .. "): "

    local self = {
        modbus_q = mqueue.new(),
        advert = advertisement,
        fac_units = facility.get_units(),
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
            alarm_tones = 0
        },
        units = {}
    }

    ---@class rtu_session
    local public = {}

    local function _reset_config()
        self.units = {}
    end

    -- parse the recorded advertisement and create unit sub-sessions
    local function _handle_advertisement()
        local unit_count = 0

        _reset_config()

        for i = 1, #self.fac_units do
            local unit = self.fac_units[i]    ---@type reactor_unit
            unit.purge_rtu_devices(id)
            facility.purge_rtu_devices(id)
        end

        for i = 1, #self.advert do
            local unit = nil    ---@type unit_session|nil

            ---@type rtu_advertisement
            local unit_advert = {
                type = self.advert[i][1],
                index = self.advert[i][2],
                reactor = self.advert[i][3],
                rsio = self.advert[i][4]
            }

            local u_type = unit_advert.type ---@type integer|boolean

            -- validate unit advertisement

            local advert_validator = util.new_validator()
            advert_validator.assert(util.is_int(unit_advert.index) or (unit_advert.index == false))
            advert_validator.assert_type_int(unit_advert.reactor)

            if u_type == RTU_UNIT_TYPE.REDSTONE then
                advert_validator.assert_type_table(unit_advert.rsio)
            end

            if advert_validator.valid() then
                if util.is_int(unit_advert.index) then advert_validator.assert_min(unit_advert.index, 1) end
                advert_validator.assert_min(unit_advert.reactor, 0)
                advert_validator.assert_max(unit_advert.reactor, #self.fac_units)
                if not advert_validator.valid() then u_type = false end
            else
                u_type = false
            end

            local type_string = util.strval(u_type)
            if type(u_type) == "number" then type_string = types.rtu_type_to_string(u_type) end

            -- create unit by type

            if u_type == false then
                -- validation fail
                log.debug(log_header .. "_handle_advertisement(): advertisement unit validation failure")
            else
                if unit_advert.reactor > 0 then
                    local target_unit = self.fac_units[unit_advert.reactor] ---@type reactor_unit

                    -- unit RTUs
                    if u_type == RTU_UNIT_TYPE.REDSTONE then
                        -- redstone
                        unit = svrs_redstone.new(id, i, unit_advert, self.modbus_q)
                        if type(unit) ~= "nil" then target_unit.add_redstone(unit) end
                    elseif u_type == RTU_UNIT_TYPE.BOILER_VALVE then
                        -- boiler
                        unit = svrs_boilerv.new(id, i, unit_advert, self.modbus_q)
                        if type(unit) ~= "nil" then target_unit.add_boiler(unit) end
                    elseif u_type == RTU_UNIT_TYPE.TURBINE_VALVE then
                        -- turbine
                        unit = svrs_turbinev.new(id, i, unit_advert, self.modbus_q)
                        if type(unit) ~= "nil" then target_unit.add_turbine(unit) end
                    elseif u_type == RTU_UNIT_TYPE.DYNAMIC_VALVE then
                        -- dynamic tank
                        unit = svrs_dynamicv.new(id, i, unit_advert, self.modbus_q)
                        if type(unit) ~= "nil" then target_unit.add_tank(unit) end
                    elseif u_type == RTU_UNIT_TYPE.SNA then
                        -- solar neutron activator
                        unit = svrs_sna.new(id, i, unit_advert, self.modbus_q)
                        if type(unit) ~= "nil" then target_unit.add_sna(unit) end
                    elseif u_type == RTU_UNIT_TYPE.ENV_DETECTOR then
                        -- environment detector
                        unit = svrs_envd.new(id, i, unit_advert, self.modbus_q)
                        if type(unit) ~= "nil" then target_unit.add_envd(unit) end
                    elseif u_type == RTU_UNIT_TYPE.VIRTUAL then
                        -- skip virtual units
                        log.debug(util.c(log_header, "skipping virtual RTU unit #", i))
                    else
                        log.warning(util.c(log_header, "_handle_advertisement(): encountered unsupported reactor-specific RTU type ", type_string))
                    end
                else
                    -- facility RTUs
                    if u_type == RTU_UNIT_TYPE.REDSTONE then
                        -- redstone
                        unit = svrs_redstone.new(id, i, unit_advert, self.modbus_q)
                        if type(unit) ~= "nil" then facility.add_redstone(unit) end
                    elseif u_type == RTU_UNIT_TYPE.IMATRIX then
                        -- induction matrix
                        unit = svrs_imatrix.new(id, i, unit_advert, self.modbus_q)
                        if type(unit) ~= "nil" then facility.add_imatrix(unit) end
                    elseif u_type == RTU_UNIT_TYPE.SPS then
                        -- super-critical phase shifter
                        unit = svrs_sps.new(id, i, unit_advert, self.modbus_q)
                        if type(unit) ~= "nil" then facility.add_sps(unit) end
                    elseif u_type == RTU_UNIT_TYPE.DYNAMIC_VALVE then
                        -- dynamic tank
                        unit = svrs_dynamicv.new(id, i, unit_advert, self.modbus_q)
                        if type(unit) ~= "nil" then facility.add_tank(unit) end
                    elseif u_type == RTU_UNIT_TYPE.ENV_DETECTOR then
                        -- environment detector
                        unit = svrs_envd.new(id, i, unit_advert, self.modbus_q)
                        if type(unit) ~= "nil" then facility.add_envd(unit) end
                    elseif u_type == RTU_UNIT_TYPE.VIRTUAL then
                        -- skip virtual units
                        log.debug(util.c(log_header, "skipping virtual RTU unit #", i))
                    else
                        log.warning(util.c(log_header, "_handle_advertisement(): encountered unsupported facility RTU type ", type_string))
                    end
                end
            end

            if unit ~= nil then
                self.units[i] = unit
                unit_count = unit_count + 1
            elseif u_type ~= RTU_UNIT_TYPE.VIRTUAL then
                log.warning(util.c(log_header, "_handle_advertisement(): problem occured while creating a unit (type is ", type_string, ")"))
            end
        end

        databus.tx_rtu_units(id, unit_count)
    end

    -- mark this RTU session as closed, stop watchdog
    local function _close()
        self.conn_watchdog.cancel()
        self.connected = false
        databus.tx_rtu_disconnected(id)

        -- mark all RTU unit sessions as closed so the reactor unit knows
        for _, unit in pairs(self.units) do unit.close() end
    end

    -- send a MODBUS packet
    ---@param m_pkt modbus_packet MODBUS packet
    local function _send_modbus(m_pkt)
        local s_pkt = comms.scada_packet()

        s_pkt.make(s_addr, self.seq_num, PROTOCOL.MODBUS_TCP, m_pkt.raw_sendable())

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
    ---@param pkt modbus_frame|mgmt_frame
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
        if pkt.scada_frame.protocol() == PROTOCOL.MODBUS_TCP then
            ---@cast pkt modbus_frame
            if self.units[pkt.unit_id] ~= nil then
                local unit = self.units[pkt.unit_id]    ---@type unit_session
                unit.handle_packet(pkt)
            end
        elseif pkt.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
            ---@cast pkt mgmt_frame
            -- handle management packet
            if pkt.type == MGMT_TYPE.KEEP_ALIVE then
                -- keep alive reply
                if pkt.length == 2 then
                    local srv_start = pkt.data[1]
                    -- local rtu_send = pkt.data[2]
                    local srv_now = util.time()
                    self.last_rtt = srv_now - srv_start

                    if self.last_rtt > 750 then
                        log.warning(log_header .. "RTU KEEP_ALIVE round trip time > 750ms (" .. self.last_rtt .. "ms)")
                    end

                    -- log.debug(log_header .. "RTU RTT = " .. self.last_rtt .. "ms")
                    -- log.debug(log_header .. "RTU TT  = " .. (srv_now - rtu_send) .. "ms")

                    databus.tx_rtu_rtt(id, self.last_rtt)
                else
                    log.debug(log_header .. "SCADA keep alive packet length mismatch")
                end
            elseif pkt.type == MGMT_TYPE.CLOSE then
                -- close the session
                _close()
            elseif pkt.type == MGMT_TYPE.RTU_ADVERT then
                -- RTU unit advertisement
                log.debug(log_header .. "received updated advertisement")
                self.advert = pkt.data

                -- handle advertisement; this will re-create all unit sub-sessions
                _handle_advertisement()
            elseif pkt.type == MGMT_TYPE.RTU_DEV_REMOUNT then
                if pkt.length == 1 then
                    local unit_id = pkt.data[1]
                    if self.units[unit_id] ~= nil then
                        local unit = self.units[unit_id]    ---@type unit_session
                        unit.invalidate_cache()
                    end
                else
                    log.debug(log_header .. "SCADA RTU device re-mount packet length mismatch")
                end
            else
                log.debug(log_header .. "handler received unsupported SCADA_MGMT packet type " .. pkt.type)
            end
        end
    end

    -- PUBLIC FUNCTIONS --

    -- get the session ID
    function public.get_id() return id end

    -- check if a timer matches this session's watchdog
    ---@nodiscard
    ---@param timer number
    function public.check_wd(timer)
        return self.conn_watchdog.is_timer(timer) and self.connected
    end

    -- close the connection
    function public.close()
        _close()
        _send_mgmt(MGMT_TYPE.CLOSE, {})
        println(log_header .. "connection to RTU closed by server")
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
                local msg = in_queue.pop()

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
                println("RTU connection " .. id .. " closed by remote host")
                log.info(log_header .. "session closed by remote host")
                return self.connected
            end

            ------------------
            -- update units --
            ------------------

            local time_now = util.time()

            for _, unit in pairs(self.units) do unit.update(time_now) end

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

            -- alarm tones

            periodics.alarm_tones = periodics.alarm_tones + elapsed
            if periodics.alarm_tones >= PERIODICS.ALARM_TONES then
                _send_mgmt(MGMT_TYPE.RTU_TONE_ALARM, { facility.get_alarm_tones() })
                periodics.alarm_tones = 0
            end

            self.periodics.last_update = util.time()

            --------------------------------------------
            -- process RTU session handler out queues --
            --------------------------------------------

            for _ = 1, self.modbus_q.length() do
                -- get the next message
                local msg = self.modbus_q.pop()

                if msg ~= nil then
                    if msg.qtype == mqueue.TYPE.PACKET then
                        -- handle a packet
                        _send_modbus(msg.message)
                    elseif msg.qtype == mqueue.TYPE.COMMAND then
                        -- handle instruction
                    elseif msg.qtype == mqueue.TYPE.DATA then
                        -- instruction with body
                        local cmd = msg.message ---@type queue_data
                        if cmd.key == unit_session.RTU_US_DATA.BUILD_CHANGED then
                            out_queue.push_data(svqtypes.SV_Q_DATA.RTU_BUILD_CHANGED, cmd.val)
                        end
                    end
                end
            end
        end

        return self.connected
    end

    -- handle initial advertisement
    _handle_advertisement()

    return public
end

return rtu
