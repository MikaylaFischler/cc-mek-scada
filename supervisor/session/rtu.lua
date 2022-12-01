local comms         = require("scada-common.comms")
local log           = require("scada-common.log")
local mqueue        = require("scada-common.mqueue")
local rsio          = require("scada-common.rsio")
local util          = require("scada-common.util")

local svqtypes      = require("supervisor.session.svqtypes")

-- supervisor rtu sessions (svrs)
local unit_session  = require("supervisor.session.rtu.unit_session")
local svrs_boilerv  = require("supervisor.session.rtu.boilerv")
local svrs_envd     = require("supervisor.session.rtu.envd")
local svrs_imatrix  = require("supervisor.session.rtu.imatrix")
local svrs_redstone = require("supervisor.session.rtu.redstone")
local svrs_sna      = require("supervisor.session.rtu.sna")
local svrs_sps      = require("supervisor.session.rtu.sps")
local svrs_turbinev = require("supervisor.session.rtu.turbinev")

local rtu = {}

local PROTOCOLS = comms.PROTOCOLS
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES
local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local PERIODICS = {
    KEEP_ALIVE = 2000
}

-- create a new RTU session
---@param id integer
---@param in_queue mqueue
---@param out_queue mqueue
---@param advertisement table
---@param facility_units table
function rtu.new_session(id, in_queue, out_queue, advertisement, facility_units)
    local log_header = "rtu_session(" .. id .. "): "

    local self = {
        id = id,
        in_q = in_queue,
        out_q = out_queue,
        modbus_q = mqueue.new(),
        f_units = facility_units,
        advert = advertisement,
        -- connection properties
        seq_num = 0,
        r_seq_num = nil,
        connected = true,
        rtu_conn_watchdog = util.new_watchdog(3),
        last_rtt = 0,
        -- periodic messages
        periodics = {
            last_update = 0,
            keep_alive = 0
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
        _reset_config()

        for i = 1, #self.f_units do
            local unit = self.f_units[i]    ---@type reactor_unit
            unit.purge_rtu_devices(self.id)
        end

        for i = 1, #self.advert do
            local unit     = nil ---@type unit_session|nil
            local rs_in_q  = nil ---@type mqueue|nil
            local tbv_in_q = nil ---@type mqueue|nil

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
            advert_validator.assert_type_int(unit_advert.index)
            advert_validator.assert_type_int(unit_advert.reactor)

            if u_type == RTU_UNIT_TYPES.REDSTONE then
                advert_validator.assert_type_table(unit_advert.rsio)
            end

            if advert_validator.valid() then
                advert_validator.assert_min(unit_advert.index, 1)
                advert_validator.assert_min(unit_advert.reactor, 1)
                advert_validator.assert_max(unit_advert.reactor, #self.f_units)
                if not advert_validator.valid() then u_type = false end
            else
                u_type = false
            end

            -- create unit by type

            if u_type == false then
                -- validation fail
                log.debug(log_header .. "advertisement unit validation failure")
            else
                local target_unit = self.f_units[unit_advert.reactor]   ---@type reactor_unit

                if u_type == RTU_UNIT_TYPES.REDSTONE then
                    -- redstone
                    unit = svrs_redstone.new(self.id, i, unit_advert, self.modbus_q)
                    if type(unit) ~= "nil" then target_unit.add_redstone(unit) end
                elseif u_type == RTU_UNIT_TYPES.BOILER_VALVE then
                    -- boiler (Mekanism 10.1+)
                    unit = svrs_boilerv.new(self.id, i, unit_advert, self.modbus_q)
                    if type(unit) ~= "nil" then target_unit.add_boiler(unit) end
                elseif u_type == RTU_UNIT_TYPES.TURBINE_VALVE then
                    -- turbine (Mekanism 10.1+)
                    unit = svrs_turbinev.new(self.id, i, unit_advert, self.modbus_q)
                    if type(unit) ~= "nil" then target_unit.add_turbine(unit) end
                elseif u_type == RTU_UNIT_TYPES.IMATRIX then
                    -- induction matrix
                    unit = svrs_imatrix.new(self.id, i, unit_advert, self.modbus_q)
                elseif u_type == RTU_UNIT_TYPES.SPS then
                    -- super-critical phase shifter
                    unit = svrs_sps.new(self.id, i, unit_advert, self.modbus_q)
                elseif u_type == RTU_UNIT_TYPES.SNA then
                    -- solar neutron activator
                    unit = svrs_sna.new(self.id, i, unit_advert, self.modbus_q)
                elseif u_type == RTU_UNIT_TYPES.ENV_DETECTOR then
                    -- environment detector
                    unit = svrs_envd.new(self.id, i, unit_advert, self.modbus_q)
                else
                    log.error(log_header .. "bad advertisement: encountered unsupported RTU type")
                end
            end

            if unit ~= nil then
                table.insert(self.units, unit)
            else
                _reset_config()
                if type(u_type) == "number" then
                    local type_string = util.strval(comms.advert_type_to_rtu_t(u_type))
                    log.error(log_header .. "bad advertisement: error occured while creating a unit (type is " .. type_string .. ")")
                end
                break
            end
        end
    end

    -- mark this RTU session as closed, stop watchdog
    local function _close()
        self.rtu_conn_watchdog.cancel()
        self.connected = false

        -- mark all RTU unit sessions as closed so the reactor unit knows
        for i = 1, #self.units do
            self.units[i].close()
        end
    end

    -- send a MODBUS packet
    ---@param m_pkt modbus_packet MODBUS packet
    local function _send_modbus(m_pkt)
        local s_pkt = comms.scada_packet()

        s_pkt.make(self.seq_num, PROTOCOLS.MODBUS_TCP, m_pkt.raw_sendable())

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
    ---@param pkt modbus_frame|mgmt_frame
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
        self.rtu_conn_watchdog.feed()

        -- process packet
        if pkt.scada_frame.protocol() == PROTOCOLS.MODBUS_TCP then
            if self.units[pkt.unit_id] ~= nil then
                local unit = self.units[pkt.unit_id]    ---@type unit_session
---@diagnostic disable-next-line: param-type-mismatch
                unit.handle_packet(pkt)
            end
        elseif pkt.scada_frame.protocol() == PROTOCOLS.SCADA_MGMT then
            -- handle management packet
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

                    -- log.debug(log_header .. "RTU RTT = " .. self.last_rtt .. "ms")
                    -- log.debug(log_header .. "RTU TT  = " .. (srv_now - rtu_send) .. "ms")
                else
                    log.debug(log_header .. "SCADA keep alive packet length mismatch")
                end
            elseif pkt.type == SCADA_MGMT_TYPES.CLOSE then
                -- close the session
                _close()
            elseif pkt.type == SCADA_MGMT_TYPES.RTU_ADVERT then
                -- RTU unit advertisement
                log.debug(log_header .. "received updated advertisement")

                -- copy advertisement and remove version tag
                self.advert = pkt.data
                table.remove(self.advert, 1)

                -- handle advertisement; this will re-create all unit sub-sessions
                _handle_advertisement()
            elseif pkt.type == SCADA_MGMT_TYPES.RTU_DEV_REMOUNT then
                if pkt.length == 1 then
                    local unit_id = pkt[1]
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
    function public.get_id() return self.id end

    -- check if a timer matches this session's watchdog
    ---@param timer number
    function public.check_wd(timer)
        return self.rtu_conn_watchdog.is_timer(timer) and self.connected
    end

    -- close the connection
    function public.close()
        _close()
        _send_mgmt(SCADA_MGMT_TYPES.CLOSE, {})
        println(log_header .. "connection to RTU closed by server")
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
                println(log_header .. "connection to RTU closed by remote host")
                log.info(log_header .. "session closed by remote host")
                return self.connected
            end

            ------------------
            -- update units --
            ------------------

            local time_now = util.time()

            for i = 1, #self.units do
                self.units[i].update(time_now)
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
                        local cmd = msg.message
                        if cmd == unit_session.RTU_US_CMDS.BUILD_CHANGED then
                            self.out_q.push_command(svqtypes.SV_Q_CMDS.BUILD_CHANGED)
                        end
                    elseif msg.qtype == mqueue.TYPE.DATA then
                        -- instruction with body
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
