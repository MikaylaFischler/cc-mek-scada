-- #REQUIRES mqueue.lua
-- #REQUIRES log.lua

-- Supervisor Sessions Handler

SESSION_TYPE = {
    RTU_SESSION = 0,
    PLC_SESSION = 1,
    COORD_SESSION = 2
}

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

function link_modem(modem)
    self.modem = modem
end

-- find a session by the remote port
function find_session(remote_port)
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
function get_reactor_session(reactor)
    local session = nil

    for i = 1, #self.plc_sessions do
        if self.plc_sessions[i].reactor == reactor then
            session = self.plc_sessions[i]
        end
    end

    return session
end

-- establish a new PLC session
function establish_plc_session(local_port, remote_port, for_reactor)
    if get_reactor_session(for_reactor) == nil then 
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

        log._debug("established new PLC session to " .. remote_port .. " with ID " .. self.next_plc_id)

        self.next_plc_id = self.next_plc_id + 1

        -- success
        return plc_s.instance.get_id()
    else
        -- reactor already assigned to a PLC
        return false
    end
end

-- check if a watchdog timer event matches that of one of the provided sessions
local function _check_watchdogs(sessions, timer_event)
    for i = 1, #sessions do
        local session = sessions[i]
        if session.open then
            local triggered = session.instance.check_wd(timer_event)
            if triggered then
                log._debug("watchdog closing session " .. session.instance.get_id() .. " on remote port " .. session.r_port)
                session.open = false
                session.instance.close()
            end
        end
    end
end

-- attempt to identify which session's watchdog timer fired
function check_all_watchdogs(timer_event)
    -- check RTU session watchdogs
    _check_watchdogs(self.rtu_sessions, timer_event)

    -- check PLC session watchdogs
    _check_watchdogs(self.plc_sessions, timer_event)

    -- check coordinator session watchdogs
    _check_watchdogs(self.coord_sessions, timer_event)
end

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
                session.instance.close()
            end
        end
    end
end

-- iterate all sessions
function iterate_all()
    -- iterate RTU sessions
    _iterate(self.rtu_sessions)

    -- iterate PLC sessions
    _iterate(self.plc_sessions)

    -- iterate coordinator sessions
    _iterate(self.coord_sessions)
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
                log._debug("free'ing closed session " .. session.instance.get_id() .. " on remote port " .. session.r_port)
                sessions[i] = nil
            end
        end
    end
end

-- delete all closed sessions
function free_all_closed()
    -- free closed RTU sessions
    _free_closed(self.rtu_sessions)

    -- free closed PLC sessions
    _free_closed(self.plc_sessions)

    -- free closed coordinator sessions
    _free_closed(self.coord_sessions)
end

-- close connections
local function _close(sessions)
    for i = 1, #sessions do
        local session = sessions[i]
        if session.open then
            session.open = false
            session.instance.close()

            -- send packets in out queue (namely the close packet)
            while session.out_queue.ready() do
                local msg = session.out_queue.pop()
                if msg.qtype == mqueue.TYPE.PACKET then
                    self.modem.transmit(session.r_port, session.l_port, msg.message.raw_sendable())
                end
            end

            log._debug("closed session " .. session.instance.get_id() .. " on remote port " .. session.r_port)
        end
    end
end

-- close all open connections
function close_all()
    -- close sessions
    _close(self.rtu_sessions)
    _close(self.plc_sessions)
    _close(self.coord_sessions)

    -- free sessions
    free_all_closed()
end
