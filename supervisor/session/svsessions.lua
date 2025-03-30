--
-- Supervisor Sessions Handler
--

local log         = require("scada-common.log")
local mqueue      = require("scada-common.mqueue")
local types       = require("scada-common.types")
local util        = require("scada-common.util")

local databus     = require("supervisor.databus")

local pgi         = require("supervisor.panel.pgi")

local coordinator = require("supervisor.session.coordinator")
local plc         = require("supervisor.session.plc")
local pocket      = require("supervisor.session.pocket")
local rtu         = require("supervisor.session.rtu")
local svqtypes    = require("supervisor.session.svqtypes")

local RTU_ID_FAIL = types.RTU_ID_FAIL
local RTU_TYPES   = types.RTU_UNIT_TYPE

local SV_Q_DATA   = svqtypes.SV_Q_DATA

local PLC_S_CMDS  = plc.PLC_S_CMDS
local PLC_S_DATA  = plc.PLC_S_DATA

local CRD_S_DATA  = coordinator.CRD_S_DATA

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
    -- references to supervisor state and other data
    nic = nil,              ---@type nic|nil
    fp_ok = false,
    config = nil,           ---@type svr_config
    facility = nil,         ---@type facility|nil
    plc_ini_reset = {},
    -- lists of connected sessions
---@diagnostic disable: missing-fields
    sessions = {
        rtu = {},           ---@type rtu_session_struct
        plc = {},           ---@type plc_session_struct
        crd = {},           ---@type crd_session_struct
        pdg = {}            ---@type pdg_session_struct
    },
---@diagnostic enable: missing-fields
    -- next session IDs
    next_ids = { rtu = 0, plc = 0, crd = 0, pdg = 0 },
    -- rtu device tracking and invalid assignment detection
    dev_dbg = {
        duplicate = {},     ---@type unit_session[]
        out_of_range = {},  ---@type unit_session[]
        connected = {}      ---@type { induction: boolean, sps: boolean, tanks: boolean[], units: unit_connections[] }
    }
}

---@alias sv_session_structs plc_session_struct|rtu_session_struct|crd_session_struct|pdg_session_struct

--#region PRIVATE FUNCTIONS

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
---@param sessions sv_session_structs[]
local function _iterate(sessions)
    for i = 1, #sessions do
        local session = sessions[i]

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
---@param sessions sv_session_structs[]
local function _close(sessions)
    for i = 1, #sessions do
        local session = sessions[i]
        if session.open then _shutdown(session) end
    end
end

-- check if a watchdog timer event matches that of one of the provided sessions
---@param sessions sv_session_structs[]
---@param timer_event number
local function _check_watchdogs(sessions, timer_event)
    for i = 1, #sessions do
        local session = sessions[i]
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
---@param sessions sv_session_structs[]
local function _free_closed(sessions)
    ---@param session sv_session_structs
    local f = function (session) return session.open end

    ---@param session sv_session_structs
    local on_delete = function (session)
        log.debug(util.c("SVS: free'ing closed session ", session))
    end

    util.filter_table(sessions, f, on_delete)
end

-- find a session by computer ID
---@nodiscard
---@param list sv_session_structs[]
---@param s_addr integer
---@return sv_session_structs|nil
local function _find_session(list, s_addr)
    for i = 1, #list do
        if list[i].s_addr == s_addr then return list[i] end
    end
    return nil
end

-- periodically remove disconnected RTU gateway's RTU ID warnings and update the missing device list
local function _update_dev_dbg()
    -- remove disconnected units from check failures lists

    local f = function (unit) return unit.is_connected() end

    util.filter_table(self.dev_dbg.duplicate, f, pgi.delete_chk_entry)
    util.filter_table(self.dev_dbg.out_of_range, f, pgi.delete_chk_entry)

    -- update missing list

    local conns     = self.dev_dbg.connected
    local units     = self.facility.get_units()
    local rtu_conns = self.facility.check_rtu_conns()

    local function report(disconnected, msg)
        if disconnected then pgi.create_missing_entry(msg) else pgi.delete_missing_entry(msg) end
    end

    -- look for disconnected facility RTUs

    if rtu_conns.induction ~= conns.induction then
        report(conns.induction, util.c("the facility's induction matrix"))
        conns.induction = rtu_conns.induction
    end

    if rtu_conns.sps ~= conns.sps then
        report(conns.sps, util.c("the facility's SPS"))
        conns.sps = rtu_conns.sps
    end

    for i = 1, #conns.tanks do
        if (rtu_conns.tanks[i] or false) ~= conns.tanks[i] then
            report(conns.tanks[i], util.c("the facility's #", i, " dynamic tank"))
            conns.tanks[i] = rtu_conns.tanks[i] or false
        end
    end

    -- look for disconnected unit RTUs

    for u = 1, #units do
        local u_conns = conns.units[u]

        rtu_conns = units[u].check_rtu_conns()

        for i = 1, #u_conns.boilers do
            if (rtu_conns.boilers[i] or false) ~= u_conns.boilers[i] then
                report(u_conns.boilers[i], util.c("unit ", u, "'s #", i, " boiler"))
                u_conns.boilers[i] = rtu_conns.boilers[i] or false
            end
        end

        for i = 1, #u_conns.turbines do
            if (rtu_conns.turbines[i] or false) ~= u_conns.turbines[i] then
                report(u_conns.turbines[i], util.c("unit ", u, "'s #", i, " turbine"))
                u_conns.turbines[i] = rtu_conns.turbines[i] or false
            end
        end

        for i = 1, #u_conns.tanks do
            if (rtu_conns.tanks[i] or false) ~= u_conns.tanks[i] then
                report(u_conns.tanks[i], util.c("unit ", u, "'s dynamic tank"))
                u_conns.tanks[i] = rtu_conns.tanks[i] or false
            end
        end
    end
end

--#endregion

--#region PUBLIC FUNCTIONS

-- on attempted link of an RTU to a facility or unit object, verify its ID and report a problem if it can't be accepted
---@param unit unit_session RTU session
---@param list unit_session[] table of RTU sessions
---@param max integer max of this type of RTU
---@return RTU_ID_FAIL fail_code, string fail_str
function svsessions.check_rtu_id(unit, list, max)
    local fail_code, fail_str = RTU_ID_FAIL.OK, "OK"

    if (unit.get_device_idx() < 1 and max ~= 1) or unit.get_device_idx() > max then
        -- out-of-range
        fail_code, fail_str = RTU_ID_FAIL.OUT_OF_RANGE, "index out of range"
        table.insert(self.dev_dbg.out_of_range, unit)
    else
        for _, u in ipairs(list) do
            if u.get_device_idx() == unit.get_device_idx() then
                -- duplicate
                fail_code, fail_str = RTU_ID_FAIL.DUPLICATE, "duplicate index"
                table.insert(self.dev_dbg.duplicate, unit)
                break
            end
        end
    end

    -- make sure this won't exceed the maximum allowable devices
    if fail_code == RTU_ID_FAIL.OK and #list >= max then
        fail_code, fail_str = RTU_ID_FAIL.MAX_DEVICES, "too many of this type"
    end

    -- add to the list for the user
    if fail_code ~= RTU_ID_FAIL.OK and fail_code ~= RTU_ID_FAIL.MAX_DEVICES then
        local r_id, idx, type = unit.get_reactor(), unit.get_device_idx(), unit.get_unit_type()
        local msg

        if r_id == 0 then
            msg = "the facility's "

            if type == RTU_TYPES.IMATRIX then
                msg = msg .. "induction matrix"
            elseif type == RTU_TYPES.SPS then
                msg = msg .. "SPS"
            elseif type == RTU_TYPES.DYNAMIC_VALVE then
                msg = util.c(msg, "#", idx, " dynamic tank")
            elseif type == RTU_TYPES.ENV_DETECTOR then
                msg = util.c(msg, "#", idx, " env. detector")
            else
                msg = msg .. " ? (error)"
            end
        else
            msg = util.c("unit ", r_id, "'s ")

            if type == RTU_TYPES.BOILER_VALVE then
                msg = util.c(msg, "#", idx, " boiler")
            elseif type == RTU_TYPES.TURBINE_VALVE then
                msg = util.c(msg, "#", idx, " turbine")
            elseif type == RTU_TYPES.DYNAMIC_VALVE then
                msg = msg .. "dynamic tank"
            elseif type == RTU_TYPES.ENV_DETECTOR then
                msg = util.c(msg, "#", idx, " env. detector")
            else
                msg = msg .. " ? (error)"
            end
        end

        pgi.create_chk_entry(unit, fail_code, msg)
    end

    return fail_code, fail_str
end

-- initialize svsessions
---@param nic nic network interface device
---@param fp_ok boolean front panel active
---@param config svr_config supervisor configuration
---@param facility facility
function svsessions.init(nic, fp_ok, config, facility)
    self.nic = nic
    self.fp_ok = fp_ok
    self.config = config
    self.facility = facility

    -- initialize connection tracking table by setting all expected devices to true
    -- if connections are missing, missing entries will then be created on the next update

    self.dev_dbg.connected = { induction = true, sps = true, tanks = {}, units = {} }

    local cool_conf = facility.get_cooling_conf()

    for i = 1, #cool_conf.fac_tank_list do
        if cool_conf.fac_tank_list[i] == 2 then
            table.insert(self.dev_dbg.connected.tanks, true)
        end
    end

    for i = 1, config.UnitCount do
        local r_cool = cool_conf.r_cool[i]
        local conns = { boilers = {}, turbines = {}, tanks = {} }   ---@type unit_connections

        for b = 1, r_cool.BoilerCount do conns.boilers[b] = true end
        for t = 1, r_cool.TurbineCount do conns.turbines[t] = true end

        if r_cool.TankConnection and cool_conf.fac_tank_defs[i] == 1 then
            conns.tanks[1] = true
        end

        self.plc_ini_reset[i] = true
        self.dev_dbg.connected.units[i] = conns
    end
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
---@param source_addr integer PLC computer ID
---@param i_seq_num integer initial (most recent) sequence number
---@param for_reactor integer unit ID
---@param version string PLC version
---@return integer|false session_id
function svsessions.establish_plc_session(source_addr, i_seq_num, for_reactor, version)
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

        plc_s.instance = plc.new_session(id, source_addr, i_seq_num, for_reactor, plc_s.in_queue, plc_s.out_queue, self.config.PLC_Timeout, self.plc_ini_reset, self.fp_ok)
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

-- establish a new RTU gateway session
---@nodiscard
---@param source_addr integer RTU gateway computer ID
---@param i_seq_num integer initial (most recent) sequence number
---@param advertisement table RTU capability advertisement
---@param version string RTU gateway version
---@return integer session_id
function svsessions.establish_rtu_session(source_addr, i_seq_num, advertisement, version)
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

    rtu_s.instance = rtu.new_session(id, source_addr, i_seq_num, rtu_s.in_queue, rtu_s.out_queue, self.config.RTU_Timeout, advertisement, self.facility, self.fp_ok)
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
---@param source_addr integer coordinator computer ID
---@param i_seq_num integer initial (most recent) sequence number
---@param version string coordinator version
---@return integer|false session_id
function svsessions.establish_crd_session(source_addr, i_seq_num, version)
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

        crd_s.instance = coordinator.new_session(id, source_addr, i_seq_num, crd_s.in_queue, crd_s.out_queue, self.config.CRD_Timeout, self.facility, self.fp_ok)
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
---@param source_addr integer pocket computer ID
---@param i_seq_num integer initial (most recent) sequence number
---@param version string pocket version
---@return integer|false session_id
function svsessions.establish_pdg_session(source_addr, i_seq_num, version)
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

    pdg_s.instance = pocket.new_session(id, source_addr, i_seq_num, pdg_s.in_queue, pdg_s.out_queue, self.config.PKT_Timeout, self.facility, self.fp_ok)
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

    -- report RTU gateway sessions to facility
    self.facility.report_rtu_gateways(self.sessions.rtu)

    -- iterate facility
    self.facility.update()

    -- iterate units
    self.facility.update_units()

    -- update tracking of bad RTU IDs and missing devices
    _update_dev_dbg()
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

--#endregion

return svsessions
