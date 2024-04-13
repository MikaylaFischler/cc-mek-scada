local log         = require("scada-common.log")
local mqueue      = require("scada-common.mqueue")
local util        = require("scada-common.util")

local databus     = require("supervisor.databus")
local facility    = require("supervisor.facility")

local coordinator = require("supervisor.session.coordinator")
local plc         = require("supervisor.session.plc")
local pocket      = require("supervisor.session.pocket")
local rtu         = require("supervisor.session.rtu")
local svqtypes    = require("supervisor.session.svqtypes")

-- Supervisor Sessions Handler

local SV_Q_DATA = svqtypes.SV_Q_DATA

local PLC_S_CMDS = plc.PLC_S_CMDS
local PLC_S_DATA = plc.PLC_S_DATA
local CRD_S_DATA = coordinator.CRD_S_DATA

local svsessions = {}

---@enum SESSION_TYPE
local SESSION_TYPE = {
    RTU_SESSION = 0,    -- RTU gateway
    PLC_SESSION = 1,    -- reactor PLC
    CRD_SESSION = 2,    -- coordinator
    PDG_SESSION = 3     -- pocket diagnostics
}

svsessions.SESSION_TYPE = SESSION_TYPE

local self = {
    nic = nil,          ---@type nic|nil
    fp_ok = false,
    config = nil,       ---@type svr_config
    facility = nil,     ---@type facility|nil
    sessions = { rtu = {}, plc = {}, crd = {}, pdg = {} },
    next_ids = { rtu = 0, plc = 0, crd = 0, pdg = 0 }
}

---@alias sv_session_structs plc_session_struct|rtu_session_struct|crd_session_struct|pdg_session_struct

-- PRIVATE FUNCTIONS --

-- handle a session output queue
---@param session sv_session_structs
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
                self.nic.transmit(session.r_chan, self.config.SVR_Channel, msg.message)
            elseif msg.qtype == mqueue.TYPE.COMMAND then
                -- handle instruction/notification
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
                        else
                            log.debug(util.c("SVS: unknown PLC SV queue command ", cmd.key))
                        end
                    end
                else
                    local crd_s = svsessions.get_crd_session()
                    if crd_s ~= nil then
                        if cmd.key == SV_Q_DATA.CRDN_ACK then
                            -- ack to be sent to coordinator
                            crd_s.in_queue.push_data(CRD_S_DATA.CMD_ACK, cmd.val)
                        elseif cmd.key == SV_Q_DATA.PLC_BUILD_CHANGED then
                            -- a PLC build has changed
                            crd_s.in_queue.push_data(CRD_S_DATA.RESEND_PLC_BUILD, cmd.val)
                        elseif cmd.key == SV_Q_DATA.RTU_BUILD_CHANGED then
                            -- an RTU build has changed
                            crd_s.in_queue.push_data(CRD_S_DATA.RESEND_RTU_BUILD, cmd.val)
                        end
                    end
                end
            end
        end

        -- max 100ms spent processing queue
        if util.time() - handle_start > 100 then
            log.debug("SVS: supervisor out queue handler exceeded 100ms queue process limit")
            log.debug(util.c("SVS: offending session: ", session))
            break
        end
    end
end

-- iterate all the given sessions
---@param sessions table
local function _iterate(sessions)
    for i = 1, #sessions do
        local session = sessions[i] ---@type sv_session_structs

        if session.open and session.instance.iterate() then
            _sv_handle_outq(session)
        else
            session.open = false
        end
    end
end

-- cleanly close a session
---@param session sv_session_structs
local function _shutdown(session)
    session.open = false
    session.instance.close()

    -- send packets in out queue (for the close packet)
    while session.out_queue.ready() do
        local msg = session.out_queue.pop()
        if msg ~= nil and msg.qtype == mqueue.TYPE.PACKET then
            self.nic.transmit(session.r_chan, self.config.SVR_Channel, msg.message)
        end
    end

    log.debug(util.c("SVS: closed session ", session))
end

-- close connections
---@param sessions table
local function _close(sessions)
    for i = 1, #sessions do
        local session = sessions[i]  ---@type sv_session_structs
        if session.open then _shutdown(session) end
    end
end

-- check if a watchdog timer event matches that of one of the provided sessions
---@param sessions table
---@param timer_event number
local function _check_watchdogs(sessions, timer_event)
    for i = 1, #sessions do
        local session = sessions[i]  ---@type sv_session_structs
        if session.open then
            local triggered = session.instance.check_wd(timer_event)
            if triggered then
                log.debug(util.c("SVS: watchdog closing session ", session, "..."))
                _shutdown(session)
            end
        end
    end
end

-- delete any closed sessions
---@param sessions table
local function _free_closed(sessions)
    local f = function (session) return session.open end

    ---@param session sv_session_structs
    local on_delete = function (session)
        log.debug(util.c("SVS: free'ing closed session ", session))
    end

    util.filter_table(sessions, f, on_delete)
end

-- find a session by computer ID
---@nodiscard
---@param list table
---@param s_addr integer
---@return sv_session_structs|nil
local function _find_session(list, s_addr)
    for i = 1, #list do
        if list[i].s_addr == s_addr then return list[i] end
    end
    return nil
end

-- PUBLIC FUNCTIONS --

-- initialize svsessions
---@param nic nic network interface device
---@param fp_ok boolean front panel active
---@param config svr_config supervisor configuration
---@param cooling_conf sv_cooling_conf cooling configuration definition
function svsessions.init(nic, fp_ok, config, cooling_conf)
    self.nic = nic
    self.fp_ok = fp_ok
    self.config = config
    self.facility = facility.new(config, cooling_conf)
end

-- find an RTU session by the computer ID
---@nodiscard
---@param source_addr integer
---@return rtu_session_struct|nil
function svsessions.find_rtu_session(source_addr)
    -- check RTU sessions
    local session = _find_session(self.sessions.rtu, source_addr)
    ---@cast session rtu_session_struct|nil
    return session
end

-- find a PLC session by the computer ID
---@nodiscard
---@param source_addr integer
---@return plc_session_struct|nil
function svsessions.find_plc_session(source_addr)
    -- check PLC sessions
    local session = _find_session(self.sessions.plc, source_addr)
    ---@cast session plc_session_struct|nil
    return session
end

-- find a coordinator session by the computer ID
---@nodiscard
---@param source_addr integer
---@return crd_session_struct|nil
function svsessions.find_crd_session(source_addr)
    -- check coordinator sessions
    local session = _find_session(self.sessions.crd, source_addr)
    ---@cast session crd_session_struct|nil
    return session
end

-- find a pocket diagnostics session by the computer ID
---@nodiscard
---@param source_addr integer
---@return pdg_session_struct|nil
function svsessions.find_pdg_session(source_addr)
    -- check diagnostic sessions
    local session = _find_session(self.sessions.pdg, source_addr)
    ---@cast session pdg_session_struct|nil
    return session
end

-- get the a coordinator session if exists
---@nodiscard
---@return crd_session_struct|nil
function svsessions.get_crd_session()
    return self.sessions.crd[1]
end

-- get a session by reactor ID
---@nodiscard
---@param reactor integer
---@return plc_session_struct|nil session
function svsessions.get_reactor_session(reactor)
    local session = nil

    for i = 1, #self.sessions.plc do
        if self.sessions.plc[i].reactor == reactor then
            session = self.sessions.plc[i]
        end
    end

    return session
end

-- establish a new PLC session
---@nodiscard
---@param source_addr integer
---@param for_reactor integer
---@param version string
---@return integer|false session_id
function svsessions.establish_plc_session(source_addr, for_reactor, version)
    if svsessions.get_reactor_session(for_reactor) == nil and for_reactor >= 1 and for_reactor <= self.config.UnitCount then
        ---@class plc_session_struct
        local plc_s = {
            s_type = "plc",
            open = true,
            reactor = for_reactor,
            version = version,
            r_chan = self.config.PLC_Channel,
            s_addr = source_addr,
            in_queue = mqueue.new(),
            out_queue = mqueue.new(),
            instance = nil  ---@type plc_session
        }

        local id = self.next_ids.plc

        plc_s.instance = plc.new_session(id, source_addr, for_reactor, plc_s.in_queue, plc_s.out_queue, self.config.PLC_Timeout, self.fp_ok)
        table.insert(self.sessions.plc, plc_s)

        local units = self.facility.get_units()
        units[for_reactor].link_plc_session(plc_s)

        local mt = {
            ---@param s plc_session_struct
            __tostring = function (s)  return util.c("PLC [", s.instance.get_id(), "] for reactor #", s.reactor, " (@", s.s_addr, ")") end
        }

        setmetatable(plc_s, mt)

        databus.tx_plc_connected(for_reactor, version, source_addr)
        log.debug(util.c("SVS: established new session: ", plc_s))

        self.next_ids.plc = id + 1

        -- success
        return plc_s.instance.get_id()
    else
        -- reactor already assigned to a PLC or ID out of range
        return false
    end
end

-- establish a new RTU session
---@nodiscard
---@param source_addr integer
---@param advertisement table
---@param version string
---@return integer session_id
function svsessions.establish_rtu_session(source_addr, advertisement, version)
    ---@class rtu_session_struct
    local rtu_s = {
        s_type = "rtu",
        open = true,
        version = version,
        r_chan = self.config.RTU_Channel,
        s_addr = source_addr,
        in_queue = mqueue.new(),
        out_queue = mqueue.new(),
        instance = nil  ---@type rtu_session
    }

    local id = self.next_ids.rtu

    rtu_s.instance = rtu.new_session(id, source_addr, rtu_s.in_queue, rtu_s.out_queue, self.config.RTU_Timeout, advertisement, self.facility, self.fp_ok)
    table.insert(self.sessions.rtu, rtu_s)

    local mt = {
        ---@param s rtu_session_struct
        __tostring = function (s)  return util.c("RTU [", s.instance.get_id(), "] (@", s.s_addr, ")") end
    }

    setmetatable(rtu_s, mt)

    databus.tx_rtu_connected(id, version, source_addr)
    log.debug(util.c("SVS: established new session: ", rtu_s))

    self.next_ids.rtu = id + 1

    -- success
    return id
end

-- establish a new coordinator session
---@nodiscard
---@param source_addr integer
---@param version string
---@return integer|false session_id
function svsessions.establish_crd_session(source_addr, version)
    if svsessions.get_crd_session() == nil then
        ---@class crd_session_struct
        local crd_s = {
            s_type = "crd",
            open = true,
            version = version,
            r_chan = self.config.CRD_Channel,
            s_addr = source_addr,
            in_queue = mqueue.new(),
            out_queue = mqueue.new(),
            instance = nil  ---@type crd_session
        }

        local id = self.next_ids.crd

        crd_s.instance = coordinator.new_session(id, source_addr, crd_s.in_queue, crd_s.out_queue, self.config.CRD_Timeout, self.facility, self.fp_ok)
        table.insert(self.sessions.crd, crd_s)

        local mt = {
            ---@param s crd_session_struct
            __tostring = function (s)  return util.c("CRD [", s.instance.get_id(), "] (@", s.s_addr, ")") end
        }

        setmetatable(crd_s, mt)

        databus.tx_crd_connected(version, source_addr)
        log.debug(util.c("SVS: established new session: ", crd_s))

        self.next_ids.crd = id + 1

        -- success
        return id
    else
        -- we already have a coordinator linked
        return false
    end
end

-- establish a new pocket diagnostics session
---@nodiscard
---@param source_addr integer
---@param version string
---@return integer|false session_id
function svsessions.establish_pdg_session(source_addr, version)
    ---@class pdg_session_struct
    local pdg_s = {
        s_type = "pkt",
        open = true,
        version = version,
        r_chan = self.config.PKT_Channel,
        s_addr = source_addr,
        in_queue = mqueue.new(),
        out_queue = mqueue.new(),
        instance = nil  ---@type pdg_session
    }

    local id = self.next_ids.pdg

    pdg_s.instance = pocket.new_session(id, source_addr, pdg_s.in_queue, pdg_s.out_queue, self.config.PKT_Timeout, self.facility, self.fp_ok)
    table.insert(self.sessions.pdg, pdg_s)

    local mt = {
        ---@param s pdg_session_struct
        __tostring = function (s)  return util.c("PDG [", s.instance.get_id(), "] (@", s.s_addr, ")") end
    }

    setmetatable(pdg_s, mt)

    databus.tx_pdg_connected(id, version, source_addr)
    log.debug(util.c("SVS: established new session: ", pdg_s))

    self.next_ids.pdg = id + 1

    -- success
    return id
end

-- attempt to identify which session's watchdog timer fired
---@param timer_event number
function svsessions.check_all_watchdogs(timer_event)
    for _, list in pairs(self.sessions) do _check_watchdogs(list, timer_event) end
end

-- iterate all sessions, and update facility/unit data & process control logic
function svsessions.iterate_all()
    -- iterate sessions
    for _, list in pairs(self.sessions) do _iterate(list) end

    -- report RTU sessions to facility
    self.facility.report_rtus(self.sessions.rtu)

    -- iterate facility
    self.facility.update()

    -- iterate units
    self.facility.update_units()
end

-- delete all closed sessions
function svsessions.free_all_closed()
    for _, list in pairs(self.sessions) do _free_closed(list) end
end

-- close all open connections
function svsessions.close_all()
    -- close sessions
    for _, list in pairs(self.sessions) do _close(list) end

    -- free sessions
    svsessions.free_all_closed()
end

return svsessions
