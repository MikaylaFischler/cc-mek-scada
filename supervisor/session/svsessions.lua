local log = require("scada-common.log")
local mqueue = require("scada-common.mqueue")

local coordinator = require("session.coordinator")
local plc = require("session.plc")
local rtu = require("session.rtu")

-- Supervisor Sessions Handler

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
    rtu_sessions = {},
    plc_sessions = {},
    coord_sessions = {},
    next_rtu_id = 0,
    next_plc_id = 0,
    next_coord_id = 0
}

-- PRIVATE FUNCTIONS --

-- iterate all the given sessions
local function _iterate(sessions)
    for i = 1, #sessions do
        local session = sessions[i]
        if session.open then
            local ok = session.instance.iterate()
            if ok then
                -- send packets in out queue
                while session.out_queue.ready() do
                    local msg = session.out_queue.pop()
                    if msg.qtype == mqueue.TYPE.PACKET then
                        self.modem.transmit(session.r_port, session.l_port, msg.message.raw_sendable())
                    end
                end
            else
                session.open = false
            end
        end
    end
end

-- cleanly close a session
local function _shutdown(session)
    session.open = false
    session.instance.close()

    -- send packets in out queue (namely the close packet)
    while session.out_queue.ready() do
        local msg = session.out_queue.pop()
        if msg.qtype == mqueue.TYPE.PACKET then
            self.modem.transmit(session.r_port, session.l_port, msg.message.raw_sendable())
        end
    end

    log.debug("closed session " .. session.instance.get_id() .. " on remote port " .. session.r_port)
end

-- close connections
local function _close(sessions)
    for i = 1, #sessions do
        local session = sessions[i]
        if session.open then
            _shutdown(session)
        end
    end
end

-- check if a watchdog timer event matches that of one of the provided sessions
local function _check_watchdogs(sessions, timer_event)
    for i = 1, #sessions do
        local session = sessions[i]
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
local function _free_closed(sessions)
    local move_to = 1
    for i = 1, #sessions do
        local session = sessions[i]
        if session ~= nil then
            if sessions[i].open then
                if sessions[move_to] == nil then
                    sessions[move_to] = session
                    sessions[i] = nil
                end
                move_to = move_to + 1
            else
                log.debug("free'ing closed session " .. session.instance.get_id() .. " on remote port " .. session.r_port)
                sessions[i] = nil
            end
        end
    end
end

-- PUBLIC FUNCTIONS --

svsessions.link_modem = function (modem)
    self.modem = modem
end

-- find a session by the remote port
svsessions.find_session = function (remote_port)
    -- check RTU sessions
    for i = 1, #self.rtu_sessions do
        if self.rtu_sessions[i].r_port == remote_port then
            return self.rtu_sessions[i]
        end
    end

    -- check PLC sessions
    for i = 1, #self.plc_sessions do
        if self.plc_sessions[i].r_port == remote_port then
            return self.plc_sessions[i]
        end
    end

    -- check coordinator sessions
    for i = 1, #self.coord_sessions do
        if self.coord_sessions[i].r_port == remote_port then
            return self.coord_sessions[i]
        end
    end

    return nil
end

-- get a session by reactor ID
svsessions.get_reactor_session = function (reactor)
    local session = nil

    for i = 1, #self.plc_sessions do
        if self.plc_sessions[i].reactor == reactor then
            session = self.plc_sessions[i]
        end
    end

    return session
end

-- establish a new PLC session
svsessions.establish_plc_session = function (local_port, remote_port, for_reactor)
    if svsessions.get_reactor_session(for_reactor) == nil then 
        local plc_s = {
            open = true,
            reactor = for_reactor,
            l_port = local_port,
            r_port = remote_port,
            in_queue = mqueue.new(),
            out_queue = mqueue.new(),
            instance = nil
        }

        plc_s.instance = plc.new_session(self.next_plc_id, for_reactor, plc_s.in_queue, plc_s.out_queue)
        table.insert(self.plc_sessions, plc_s)

        log.debug("established new PLC session to " .. remote_port .. " with ID " .. self.next_plc_id)

        self.next_plc_id = self.next_plc_id + 1

        -- success
        return plc_s.instance.get_id()
    else
        -- reactor already assigned to a PLC
        return false
    end
end

-- attempt to identify which session's watchdog timer fired
svsessions.check_all_watchdogs = function (timer_event)
    -- check RTU session watchdogs
    _check_watchdogs(self.rtu_sessions, timer_event)

    -- check PLC session watchdogs
    _check_watchdogs(self.plc_sessions, timer_event)

    -- check coordinator session watchdogs
    _check_watchdogs(self.coord_sessions, timer_event)
end

-- iterate all sessions
svsessions.iterate_all = function ()
    -- iterate RTU sessions
    _iterate(self.rtu_sessions)

    -- iterate PLC sessions
    _iterate(self.plc_sessions)

    -- iterate coordinator sessions
    _iterate(self.coord_sessions)
end

-- delete all closed sessions
svsessions.free_all_closed = function ()
    -- free closed RTU sessions
    _free_closed(self.rtu_sessions)

    -- free closed PLC sessions
    _free_closed(self.plc_sessions)

    -- free closed coordinator sessions
    _free_closed(self.coord_sessions)
end

-- close all open connections
svsessions.close_all = function ()
    -- close sessions
    _close(self.rtu_sessions)
    _close(self.plc_sessions)
    _close(self.coord_sessions)

    -- free sessions
    svsessions.free_all_closed()
end

return svsessions
