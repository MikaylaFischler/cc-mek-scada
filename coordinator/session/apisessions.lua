
local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local util      = require("scada-common.util")

local iocontrol = require("coordinator.iocontrol")

local pocket    = require("coordinator.session.pocket")

local apisessions = {}

local self = {
    nic = nil,    ---@type nic
    config = nil, ---@type crd_config
    next_id = 0,
    sessions = {}
}

-- PRIVATE FUNCTIONS --

-- handle a session output queue
---@param session pkt_session_struct
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
                self.nic.transmit(self.config.PKT_Channel, self.config.CRD_Channel, msg.message)
            elseif msg.qtype == mqueue.TYPE.COMMAND then
                -- handle instruction/notification
            elseif msg.qtype == mqueue.TYPE.DATA then
                -- instruction/notification with body
            end
        end

        -- max 100ms spent processing queue
        if util.time() - handle_start > 100 then
            log.warning("API: out queue handler exceeded 100ms queue process limit")
            log.warning(util.c("API: offending session: ", session))
            break
        end
    end
end

-- cleanly close a session
---@param session pkt_session_struct
local function _shutdown(session)
    session.open = false
    session.instance.close()

    -- send packets in out queue (namely the close packet)
    while session.out_queue.ready() do
        local msg = session.out_queue.pop()
        if msg ~= nil and msg.qtype == mqueue.TYPE.PACKET then
            self.nic.transmit(self.config.PKT_Channel, self.config.CRD_Channel, msg.message)
        end
    end

    log.debug(util.c("API: closed session ", session))
end

-- PUBLIC FUNCTIONS --

-- initialize apisessions
---@param nic nic network interface
---@param config crd_config coordinator config
function apisessions.init(nic, config)
    self.nic = nic
    self.config = config
end

-- find a session by remote port
---@nodiscard
---@param source_addr integer
---@return pkt_session_struct|nil
function apisessions.find_session(source_addr)
    for i = 1, #self.sessions do
        if self.sessions[i].s_addr == source_addr then return self.sessions[i] end
    end
    return nil
end

-- establish a new API session
---@nodiscard
---@param source_addr integer
---@param version string
---@return integer session_id
function apisessions.establish_session(source_addr, version)
    ---@class pkt_session_struct
    local pkt_s = {
        open = true,
        version = version,
        s_addr = source_addr,
        in_queue = mqueue.new(),
        out_queue = mqueue.new(),
        instance = nil  ---@type pkt_session
    }

    local id = self.next_id

    pkt_s.instance = pocket.new_session(id, source_addr, pkt_s.in_queue, pkt_s.out_queue, self.config.API_Timeout)
    table.insert(self.sessions, pkt_s)

    local mt = {
        ---@param s pkt_session_struct
        __tostring = function (s)  return util.c("PKT [", id, "] (@", s.s_addr, ")") end
    }

    setmetatable(pkt_s, mt)

    iocontrol.fp_pkt_connected(id, version, source_addr)
    log.debug(util.c("API: established new session: ", pkt_s))

    self.next_id = id + 1

    -- success
    return pkt_s.instance.get_id()
end

-- attempt to identify which session's watchdog timer fired
---@param timer_event number
function apisessions.check_all_watchdogs(timer_event)
    for i = 1, #self.sessions do
        local session = self.sessions[i]  ---@type pkt_session_struct
        if session.open then
            local triggered = session.instance.check_wd(timer_event)
            if triggered then
                log.debug(util.c("API: watchdog closing session ", session, "..."))
                _shutdown(session)
            end
        end
    end
end

-- iterate all the API sessions
function apisessions.iterate_all()
    for i = 1, #self.sessions do
        local session = self.sessions[i]    ---@type pkt_session_struct

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

    ---@param session pkt_session_struct
    local on_delete = function (session)
        log.debug(util.c("API: free'ing closed session ", session))
    end

    util.filter_table(self.sessions, f, on_delete)
end

-- close all open connections
function apisessions.close_all()
    for i = 1, #self.sessions do
        local session = self.sessions[i]  ---@type pkt_session_struct
        if session.open then _shutdown(session) end
    end

    apisessions.free_all_closed()
end

return apisessions
