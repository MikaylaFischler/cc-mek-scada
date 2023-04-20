
local log    = require("scada-common.log")
local mqueue = require("scada-common.mqueue")
local util   = require("scada-common.util")

local config = require("coordinator.config")

local api    = require("coordinator.session.api")

local apisessions = {}

local self = {
    modem = nil,
    next_id = 0,
    sessions = {}
}

-- PRIVATE FUNCTIONS --

-- handle a session output queue
---@param session api_session_struct
local function _api_handle_outq(session)
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
            elseif msg.qtype == mqueue.TYPE.DATA then
                -- instruction/notification with body
            end
        end

        -- max 100ms spent processing queue
        if util.time() - handle_start > 100 then
            log.warning("API out queue handler exceeded 100ms queue process limit")
            log.warning(util.c("offending session: port ", session.r_port))
            break
        end
    end
end

-- cleanly close a session
---@param session api_session_struct
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

    log.debug(util.c("closed API session ", session.instance.get_id(), " on remote port ", session.r_port))
end

-- PUBLIC FUNCTIONS --

-- initialize apisessions
---@param modem table
function apisessions.init(modem)
    self.modem = modem
end

-- re-link the modem
---@param modem table
function apisessions.relink_modem(modem)
    self.modem = modem
end

-- find a session by remote port
---@nodiscard
---@param port integer
---@return api_session_struct|nil
function apisessions.find_session(port)
    for i = 1, #self.sessions do
        if self.sessions[i].r_port == port then return self.sessions[i] end
    end
    return nil
end

-- establish a new API session
---@nodiscard
---@param local_port integer
---@param remote_port integer
---@param version string
---@return integer session_id
function apisessions.establish_session(local_port, remote_port, version)
    ---@class api_session_struct
    local api_s = {
        open = true,
        version = version,
        l_port = local_port,
        r_port = remote_port,
        in_queue = mqueue.new(),
        out_queue = mqueue.new(),
        instance = nil  ---@type api_session
    }

    api_s.instance = api.new_session(self.next_id, api_s.in_queue, api_s.out_queue, config.API_TIMEOUT)
    table.insert(self.sessions, api_s)

    log.debug(util.c("established new API session to ", remote_port, " with ID ", self.next_id))

    self.next_id = self.next_id + 1

    -- success
    return api_s.instance.get_id()
end

-- attempt to identify which session's watchdog timer fired
---@param timer_event number
function apisessions.check_all_watchdogs(timer_event)
    for i = 1, #self.sessions do
        local session = self.sessions[i]  ---@type api_session_struct
        if session.open then
            local triggered = session.instance.check_wd(timer_event)
            if triggered then
                log.debug(util.c("watchdog closing API session ", session.instance.get_id(),
                    " on remote port ", session.r_port, "..."))
                _shutdown(session)
            end
        end
    end
end

-- iterate all the API sessions
function apisessions.iterate_all()
    for i = 1, #self.sessions do
        local session = self.sessions[i]    ---@type api_session_struct

        if session.open and session.instance.iterate() then
            _api_handle_outq(session)
        else
            session.open = false
        end
    end
end

-- delete all closed sessions
function apisessions.free_all_closed()
    local f = function (session) return session.open end

    ---@param session api_session_struct
    local on_delete = function (session)
        log.debug(util.c("free'ing closed API session ", session.instance.get_id(),
            " on remote port ", session.r_port))
    end

    util.filter_table(self.sessions, f, on_delete)
end

-- close all open connections
function apisessions.close_all()
    for i = 1, #self.sessions do
        local session = self.sessions[i]  ---@type api_session_struct
        if session.open then _shutdown(session) end
    end

    apisessions.free_all_closed()
end

return apisessions
