local log         = require("scada-common.log")
local mqueue      = require("scada-common.mqueue")
local util        = require("scada-common.util")

local svqtypes    = require("supervisor.session.svqtypes")
local unit        = require("supervisor.session.unit")

local coordinator = require("supervisor.session.coordinator")
local plc         = require("supervisor.session.plc")
local rtu         = require("supervisor.session.rtu")

-- Supervisor Sessions Handler

local SV_Q_CMDS = svqtypes.SV_Q_CMDS
local SV_Q_DATA = svqtypes.SV_Q_DATA

local PLC_S_CMDS = plc.PLC_S_CMDS
local PLC_S_DATA = plc.PLC_S_DATA
local CRD_S_CMDS = coordinator.CRD_S_CMDS
local CRD_S_DATA = coordinator.CRD_S_DATA

local svsessions = {}

local SESSION_TYPE = {
    RTU_SESSION = 0,
    PLC_SESSION = 1,
    COORD_SESSION = 2
}

svsessions.SESSION_TYPE = SESSION_TYPE

local self = {
    modem = nil,
    num_reactors = 0,
    facility_units = {},
    rtu_sessions = {},
    plc_sessions = {},
    coord_sessions = {},
    next_rtu_id = 0,
    next_plc_id = 0,
    next_coord_id = 0
}

-- PRIVATE FUNCTIONS --

-- handle a session output queue
---@param session plc_session_struct|rtu_session_struct|coord_session_struct
local function _sv_handle_outq(session)
    -- record handler start time
    local handle_start = util.time()

    -- process output queue
    while session.out_queue.ready() do
        -- get a new message to process
        local msg = session.out_queue.pop()

        if msg ~= nil then
            if msg.qtype == mqueue.TYPE.PACKET then
                -- handle a packet to be sent
                self.modem.transmit(session.r_port, session.l_port, msg.message.raw_sendable())
            elseif msg.qtype == mqueue.TYPE.COMMAND then
                -- handle instruction/notification
                local cmd = msg.message
                if (cmd == SV_Q_CMDS.BUILD_CHANGED) and (svsessions.get_coord_session() ~= nil) then
                    -- notify coordinator that a build has changed
                    svsessions.get_coord_session().in_queue.push_command(CRD_S_CMDS.RESEND_BUILDS)
                end
            elseif msg.qtype == mqueue.TYPE.DATA then
                -- instruction/notification with body
                local cmd = msg.message ---@type queue_data

                if cmd.key < SV_Q_DATA.__END_PLC_CMDS__ then
                    -- PLC commands from coordinator
                    local plc_s = svsessions.get_reactor_session(cmd.val[1])

                    if plc_s ~= nil then
                        if cmd.key == SV_Q_DATA.START then
                            plc_s.in_queue.push_command(PLC_S_CMDS.ENABLE)
                        elseif cmd.key == SV_Q_DATA.SCRAM then
                            plc_s.in_queue.push_command(PLC_S_CMDS.SCRAM)
                        elseif cmd.key == SV_Q_DATA.RESET_RPS then
                            plc_s.in_queue.push_command(PLC_S_CMDS.RPS_RESET)
                        elseif cmd.key == SV_Q_DATA.SET_BURN and type(cmd.val) == "table" and #cmd.val == 2 then
                            plc_s.in_queue.push_data(PLC_S_DATA.BURN_RATE, cmd.val[2])
                        elseif cmd.key == SV_Q_DATA.SET_WASTE and type(cmd.val) == "table" and #cmd.val == 2 then
                            ---@todo set waste
                        else
                            log.debug(util.c("unknown PLC SV queue command ", cmd.key))
                        end
                    end
                else
                    if cmd.key == SV_Q_DATA.CRDN_ACK then
                        -- ack to be sent to coordinator
                        local crd_s = svsessions.get_coord_session()
                        if crd_s ~= nil then
                            crd_s.in_queue.push_data(CRD_S_DATA.CMD_ACK, cmd.val)
                        end
                    end
                end
            end
        end

        -- max 100ms spent processing queue
        if util.time() - handle_start > 100 then
            log.warning("supervisor out queue handler exceeded 100ms queue process limit")
            log.warning(util.c("offending session: port ", session.r_port, " type '", session.s_type, "'"))
            break
        end
    end
end

-- iterate all the given sessions
---@param sessions table
local function _iterate(sessions)
    for i = 1, #sessions do
        local session = sessions[i] ---@type plc_session_struct|rtu_session_struct|coord_session_struct

        if session.open and session.instance.iterate() then
            _sv_handle_outq(session)
        else
            session.open = false
        end
    end
end

-- cleanly close a session
---@param session plc_session_struct|rtu_session_struct
local function _shutdown(session)
    session.open = false
    session.instance.close()

    -- send packets in out queue (namely the close packet)
    while session.out_queue.ready() do
        local msg = session.out_queue.pop()
        if msg ~= nil and msg.qtype == mqueue.TYPE.PACKET then
            self.modem.transmit(session.r_port, session.l_port, msg.message.raw_sendable())
        end
    end

    log.debug("closed session " .. session.instance.get_id() .. " on remote port " .. session.r_port)
end

-- close connections
---@param sessions table
local function _close(sessions)
    for i = 1, #sessions do
        local session = sessions[i]  ---@type plc_session_struct
        if session.open then
            _shutdown(session)
        end
    end
end

-- check if a watchdog timer event matches that of one of the provided sessions
---@param sessions table
---@param timer_event number
local function _check_watchdogs(sessions, timer_event)
    for i = 1, #sessions do
        local session = sessions[i]  ---@type plc_session_struct
        if session.open then
            local triggered = session.instance.check_wd(timer_event)
            if triggered then
                log.debug("watchdog closing session " .. session.instance.get_id() .. " on remote port " .. session.r_port .. "...")
                _shutdown(session)
            end
        end
    end
end

-- delete any closed sessions
---@param sessions table
local function _free_closed(sessions)
    local f = function (session) return session.open end

    local on_delete = function (session)
        log.debug("free'ing closed session " .. session.instance.get_id() .. " on remote port " .. session.r_port)
    end

    util.filter_table(sessions, f, on_delete)
end

-- find a session by remote port
---@param list table
---@param port integer
---@return plc_session_struct|rtu_session_struct|nil
local function _find_session(list, port)
    for i = 1, #list do
        if list[i].r_port == port then return list[i] end
    end
    return nil
end

-- PUBLIC FUNCTIONS --

-- initialize svsessions
---@param modem table
---@param num_reactors integer
---@param cooling_conf table
function svsessions.init(modem, num_reactors, cooling_conf)
    self.modem = modem
    self.num_reactors = num_reactors
    self.facility_units = {}

    for i = 1, self.num_reactors do
        table.insert(self.facility_units, unit.new(i, cooling_conf[i].BOILERS, cooling_conf[i].TURBINES))
    end
end

-- re-link the modem
---@param modem table
function svsessions.relink_modem(modem)
    self.modem = modem
end

-- find an RTU session by the remote port
---@param remote_port integer
---@return rtu_session_struct|nil
function svsessions.find_rtu_session(remote_port)
    -- check RTU sessions
---@diagnostic disable-next-line: return-type-mismatch
    return _find_session(self.rtu_sessions, remote_port)
end

-- find a PLC session by the remote port
---@param remote_port integer
---@return plc_session_struct|nil
function svsessions.find_plc_session(remote_port)
    -- check PLC sessions
---@diagnostic disable-next-line: return-type-mismatch
    return _find_session(self.plc_sessions, remote_port)
end

-- find a PLC/RTU session by the remote port
---@param remote_port integer
---@return plc_session_struct|rtu_session_struct|nil
function svsessions.find_device_session(remote_port)
    -- check RTU sessions
    local s = _find_session(self.rtu_sessions, remote_port)

    -- check PLC sessions
    if s == nil then s = _find_session(self.plc_sessions, remote_port) end

    return s
end

-- find a coordinator session by the remote port
--
-- only one coordinator is allowed, but this is kept to be consistent with all other session tables
---@param remote_port integer
---@return nil
function svsessions.find_coord_session(remote_port)
    -- check coordinator sessions
---@diagnostic disable-next-line: return-type-mismatch
    return _find_session(self.coord_sessions, remote_port)
end

-- get the a coordinator session if exists
---@return coord_session_struct|nil
function svsessions.get_coord_session()
    return self.coord_sessions[1]
end

-- get a session by reactor ID
---@param reactor integer
---@return plc_session_struct|nil session
function svsessions.get_reactor_session(reactor)
    local session = nil

    for i = 1, #self.plc_sessions do
        if self.plc_sessions[i].reactor == reactor then
            session = self.plc_sessions[i]
        end
    end

    return session
end

-- establish a new PLC session
---@param local_port integer
---@param remote_port integer
---@param for_reactor integer
---@param version string
---@return integer|false session_id
function svsessions.establish_plc_session(local_port, remote_port, for_reactor, version)
    if svsessions.get_reactor_session(for_reactor) == nil and for_reactor >= 1 and for_reactor <= self.num_reactors then
        ---@class plc_session_struct
        local plc_s = {
            s_type = "plc",
            open = true,
            reactor = for_reactor,
            version = version,
            l_port = local_port,
            r_port = remote_port,
            in_queue = mqueue.new(),
            out_queue = mqueue.new(),
            instance = nil  ---@type plc_session
        }

        plc_s.instance = plc.new_session(self.next_plc_id, for_reactor, plc_s.in_queue, plc_s.out_queue)
        table.insert(self.plc_sessions, plc_s)

        self.facility_units[for_reactor].link_plc_session(plc_s)

        log.debug("established new PLC session to " .. remote_port .. " with ID " .. self.next_plc_id)

        self.next_plc_id = self.next_plc_id + 1

        -- success
        return plc_s.instance.get_id()
    else
        -- reactor already assigned to a PLC or ID out of range
        return false
    end
end

-- establish a new RTU session
---@param local_port integer
---@param remote_port integer
---@param advertisement table
---@param version string
---@return integer session_id
function svsessions.establish_rtu_session(local_port, remote_port, advertisement, version)
    ---@class rtu_session_struct
    local rtu_s = {
        s_type = "rtu",
        open = true,
        version = version,
        l_port = local_port,
        r_port = remote_port,
        in_queue = mqueue.new(),
        out_queue = mqueue.new(),
        instance = nil  ---@type rtu_session
    }

    rtu_s.instance = rtu.new_session(self.next_rtu_id, rtu_s.in_queue, rtu_s.out_queue, advertisement, self.facility_units)
    table.insert(self.rtu_sessions, rtu_s)

    log.debug("established new RTU session to " .. remote_port .. " with ID " .. self.next_rtu_id)

    self.next_rtu_id = self.next_rtu_id + 1

    -- success
    return rtu_s.instance.get_id()
end

-- establish a new coordinator session
---@param local_port integer
---@param remote_port integer
---@param version string
---@return integer|false session_id
function svsessions.establish_coord_session(local_port, remote_port, version)
    if svsessions.get_coord_session() == nil then
        ---@class coord_session_struct
        local coord_s = {
            s_type = "crd",
            open = true,
            version = version,
            l_port = local_port,
            r_port = remote_port,
            in_queue = mqueue.new(),
            out_queue = mqueue.new(),
            instance = nil  ---@type coord_session
        }

        coord_s.instance = coordinator.new_session(self.next_coord_id, coord_s.in_queue, coord_s.out_queue, self.facility_units)
        table.insert(self.coord_sessions, coord_s)

        log.debug("established new coordinator session to " .. remote_port .. " with ID " .. self.next_coord_id)

        self.next_coord_id = self.next_coord_id + 1

        -- success
        return coord_s.instance.get_id()
    else
        -- we already have a coordinator linked
        return false
    end
end

-- attempt to identify which session's watchdog timer fired
---@param timer_event number
function svsessions.check_all_watchdogs(timer_event)
    -- check RTU session watchdogs
    _check_watchdogs(self.rtu_sessions, timer_event)

    -- check PLC session watchdogs
    _check_watchdogs(self.plc_sessions, timer_event)

    -- check coordinator session watchdogs
    _check_watchdogs(self.coord_sessions, timer_event)
end

-- iterate all sessions
function svsessions.iterate_all()
    -- iterate RTU sessions
    _iterate(self.rtu_sessions)

    -- iterate PLC sessions
    _iterate(self.plc_sessions)

    -- iterate coordinator sessions
    _iterate(self.coord_sessions)

    -- iterate units
    for i = 1, #self.facility_units do
        local u = self.facility_units[i]    ---@type reactor_unit
        u.update()
    end
end

-- delete all closed sessions
function svsessions.free_all_closed()
    -- free closed RTU sessions
    _free_closed(self.rtu_sessions)

    -- free closed PLC sessions
    _free_closed(self.plc_sessions)

    -- free closed coordinator sessions
    _free_closed(self.coord_sessions)
end

-- close all open connections
function svsessions.close_all()
    -- close sessions
    _close(self.rtu_sessions)
    _close(self.plc_sessions)
    _close(self.coord_sessions)

    -- free sessions
    svsessions.free_all_closed()
end

return svsessions
