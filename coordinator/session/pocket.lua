local comms     = require("scada-common.comms")
local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local types     = require("scada-common.types")
local util      = require("scada-common.util")

local iocontrol = require("coordinator.iocontrol")
local process   = require("coordinator.process")

local pocket = {}

local PROTOCOL = comms.PROTOCOL
local CRDN_TYPE = comms.CRDN_TYPE
local MGMT_TYPE = comms.MGMT_TYPE
local FAC_COMMAND = comms.FAC_COMMAND
local UNIT_COMMAND = comms.UNIT_COMMAND

local AUTO_GROUP = types.AUTO_GROUP
local WASTE_MODE = types.WASTE_MODE

-- retry time constants in ms
-- local INITIAL_WAIT = 1500
-- local RETRY_PERIOD = 1000

local API_S_CMDS = {
}

local API_S_DATA = {
}

pocket.API_S_CMDS = API_S_CMDS
pocket.API_S_DATA = API_S_DATA

local PERIODICS = {
    KEEP_ALIVE = 2000
}

-- pocket API session
---@nodiscard
---@param id integer session ID
---@param s_addr integer device source address
---@param i_seq_num integer initial sequence number
---@param in_queue mqueue in message queue
---@param out_queue mqueue out message queue
---@param timeout number communications timeout
function pocket.new_session(id, s_addr, i_seq_num, in_queue, out_queue, timeout)
    local log_tag = "pkt_session(" .. id .. "): "

    local self = {
        -- connection properties
        seq_num = i_seq_num + 2, -- next after the establish approval was sent
        r_seq_num = i_seq_num + 1,
        connected = true,
        conn_watchdog = util.new_watchdog(timeout),
        last_rtt = 0,
        -- process accessor handle
        proc_handle = process.create_handle(),
        -- periodic messages
        periodics = {
            last_update = 0,
            keep_alive = 0
        },
        -- when to next retry one of these requests
        retry_times = {
        },
        -- command acknowledgements
        acks = {
        },
        -- session database
        ---@class api_db
        sDB = {
        }
    }

    ---@class pkt_session
    local public = {}

    -- mark this pocket session as closed, stop watchdog
    local function _close()
        self.conn_watchdog.cancel()
        self.connected = false
        iocontrol.fp_pkt_disconnected(id)
    end

    -- send a CRDN packet
    ---@param msg_type CRDN_TYPE
    ---@param msg table
    local function _send(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local c_pkt = comms.crdn_packet()

        c_pkt.make(msg_type, msg)
        s_pkt.make(s_addr, self.seq_num, PROTOCOL.SCADA_CRDN, c_pkt.raw_sendable())

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

    -- link callback transmissions

    local f_ack = self.proc_handle.fac_ack

    f_ack.on_scram = function (success) _send(CRDN_TYPE.FAC_CMD, { FAC_COMMAND.SCRAM_ALL, success }) end
    f_ack.on_ack_alarms = function (success) _send(CRDN_TYPE.FAC_CMD, { FAC_COMMAND.ACK_ALL_ALARMS, success }) end

    f_ack.on_start = function (success) _send(CRDN_TYPE.FAC_CMD, { FAC_COMMAND.START, success }) end
    f_ack.on_stop = function (success) _send(CRDN_TYPE.FAC_CMD, { FAC_COMMAND.STOP, success }) end

    for u = 1, iocontrol.get_db().facility.num_units do
        local u_ack = self.proc_handle.unit_ack[u]
        u_ack.on_start = function (success) _send(CRDN_TYPE.UNIT_CMD, { UNIT_COMMAND.START, u, success }) end
        u_ack.on_scram = function (success) _send(CRDN_TYPE.UNIT_CMD, { UNIT_COMMAND.SCRAM, u, success }) end
        u_ack.on_rps_reset = function (success) _send(CRDN_TYPE.UNIT_CMD, { UNIT_COMMAND.RESET_RPS, u, success }) end
        u_ack.on_ack_alarms = function (success) _send(CRDN_TYPE.UNIT_CMD, { UNIT_COMMAND.ACK_ALL_ALARMS, u, success }) end
    end

    -- handle a packet
    ---@param pkt mgmt_frame|crdn_frame
    local function _handle_packet(pkt)
        -- check sequence number
        if self.r_seq_num ~= pkt.scada_frame.seq_num() then
            log.warning(log_tag .. "sequence out-of-order: next = " .. self.r_seq_num .. ", new = " .. pkt.scada_frame.seq_num())
            return
        else
            self.r_seq_num = pkt.scada_frame.seq_num() + 1
        end

        -- feed watchdog
        self.conn_watchdog.feed()

        -- process packet
        if pkt.scada_frame.protocol() == PROTOCOL.SCADA_CRDN then
            ---@cast pkt crdn_frame

            local db = iocontrol.get_db()

            -- handle packet by type
            if pkt.type == CRDN_TYPE.FAC_CMD then
                if pkt.length >= 1 then
                    local cmd = pkt.data[1]

                    if cmd == FAC_COMMAND.SCRAM_ALL then
                        log.info(log_tag .. "FAC SCRAM ALL")
                        self.proc_handle.fac_scram()
                    elseif cmd == FAC_COMMAND.STOP then
                        log.info(log_tag .. "STOP PROCESS CTRL")
                        self.proc_handle.process_stop()
                    elseif cmd == FAC_COMMAND.START then
                        if pkt.length == 6 then
                            log.info(log_tag .. "START PROCESS CTRL")
                            self.proc_handle.process_start_remote(pkt.data[2], pkt.data[3], pkt.data[4], pkt.data[5], pkt.data[6])
                        else
                            log.debug(log_tag .. "CRDN auto start (with configuration) packet length mismatch")
                        end
                    elseif cmd == FAC_COMMAND.ACK_ALL_ALARMS then
                        log.info(log_tag .. "FAC ACK ALL ALARMS")
                        self.proc_handle.fac_ack_alarms()
                    elseif cmd == FAC_COMMAND.SET_WASTE_MODE then
                        if pkt.length == 2 then
                            log.info(util.c(log_tag, " SET WASTE ", pkt.data[2]))
                            process.set_process_waste(pkt.data[2])
                        else
                            log.debug(log_tag .. "CRDN set waste mode packet length mismatch")
                        end
                    elseif cmd == FAC_COMMAND.SET_PU_FB then
                        if pkt.length == 2 then
                            log.info(util.c(log_tag, " SET PU FALLBACK ", pkt.data[2]))
                            process.set_pu_fallback(pkt.data[2] == true)
                        else
                            log.debug(log_tag .. "CRDN set pu fallback packet length mismatch")
                        end
                    elseif cmd == FAC_COMMAND.SET_SPS_LP then
                        if pkt.length == 2 then
                            log.info(util.c(log_tag, " SET SPS LOW POWER ", pkt.data[2]))
                            process.set_sps_low_power(pkt.data[2] == true)
                        else
                            log.debug(log_tag .. "CRDN set sps low power packet length mismatch")
                        end
                    else
                        log.debug(log_tag .. "CRDN facility command unknown")
                    end
                else
                    log.debug(log_tag .. "CRDN facility command packet length mismatch")
                end
            elseif pkt.type == CRDN_TYPE.UNIT_CMD then
                if pkt.length >= 2 then
                    -- get command and unit id
                    local cmd = pkt.data[1]
                    local uid = pkt.data[2]

                    -- continue if valid unit id
                    if util.is_int(uid) and uid > 0 and uid <= #db.units then
                        if cmd == UNIT_COMMAND.SCRAM then
                            log.info(util.c(log_tag, "UNIT[", uid, "] SCRAM"))
                            self.proc_handle.scram(uid)
                        elseif cmd == UNIT_COMMAND.START then
                            log.info(util.c(log_tag, "UNIT[", uid, "] START"))
                            self.proc_handle.start(uid)
                        elseif cmd == UNIT_COMMAND.RESET_RPS then
                            log.info(util.c(log_tag, "UNIT[", uid, "] RESET RPS"))
                            self.proc_handle.reset_rps(uid)
                        elseif cmd == UNIT_COMMAND.SET_BURN then
                            if (pkt.length == 3) and (type(pkt.data[3]) == "number") then
                                log.info(util.c(log_tag, "UNIT[", uid, "] SET BURN ", pkt.data[3]))
                                process.set_rate(uid, pkt.data[3])
                            else
                                log.debug(log_tag .. "CRDN unit command burn rate missing option")
                            end
                        elseif cmd == UNIT_COMMAND.SET_WASTE then
                            if (pkt.length == 3) and (type(pkt.data[3]) == "number") and
                               (pkt.data[3] >= WASTE_MODE.AUTO) and (pkt.data[3] <= WASTE_MODE.MANUAL_ANTI_MATTER) then
                                log.info(util.c(log_tag, "UNIT[", id, "] SET WASTE ", pkt.data[3]))
                                process.set_unit_waste(uid, pkt.data[3])
                            else
                                log.debug(log_tag .. "CRDN unit command set waste missing/invalid option")
                            end
                        elseif cmd == UNIT_COMMAND.ACK_ALL_ALARMS then
                            log.info(util.c(log_tag, "UNIT[", uid, "] ACK ALL ALARMS"))
                            self.proc_handle.ack_all_alarms(uid)
                        elseif cmd == UNIT_COMMAND.ACK_ALARM then
                        elseif cmd == UNIT_COMMAND.RESET_ALARM then
                        elseif cmd == UNIT_COMMAND.SET_GROUP then
                            if (pkt.length == 3) and (type(pkt.data[3]) == "number") and
                               (pkt.data[3] >= AUTO_GROUP.MANUAL) and (pkt.data[3] <= AUTO_GROUP.BACKUP) then
                                log.info(util.c(log_tag, "UNIT[", uid, "] SET GROUP ", pkt.data[3]))
                                process.set_group(uid, pkt.data[3])
                            else
                                log.debug(log_tag .. "CRDN unit set group missing option")
                            end
                        else
                            log.debug(log_tag .. "CRDN unit command unknown")
                        end
                    else
                        log.debug(log_tag .. "CRDN unit command invalid")
                    end
                else
                    log.debug(log_tag .. "CRDN unit command packet length mismatch")
                end
            elseif pkt.type == CRDN_TYPE.API_GET_FAC then
                local fac = db.facility

                local data = {
                    fac.all_sys_ok,
                    fac.rtu_count,
                    fac.radiation,
                    { fac.auto_ready, fac.auto_active, fac.auto_ramping, fac.auto_saturated },
                    { fac.auto_current_waste_product, fac.auto_pu_fallback_active },
                    util.table_len(fac.tank_data_tbl),
                    fac.induction_data_tbl[1] ~= nil,   ---@fixme this means nothing
                    fac.sps_data_tbl[1] ~= nil          ---@fixme this means nothing
                }

                _send(CRDN_TYPE.API_GET_FAC, data)
            elseif pkt.type == CRDN_TYPE.API_GET_FAC_DTL then
                local fac = db.facility
                local mtx_sps = fac.induction_ps_tbl[1]

                local units = {}
                local tank_statuses = {}

                for i = 1, #db.units do
                    local u = db.units[i]
                    units[i] = { u.connected, u.annunciator, u.reactor_data, u.tank_data_tbl }
                    for t = 1, #u.tank_ps_tbl do table.insert(tank_statuses, u.tank_ps_tbl[t].get("computed_status")) end
                end

                for i = 1, #fac.tank_ps_tbl do table.insert(tank_statuses, fac.tank_ps_tbl[i].get("computed_status")) end

                local matrix_data = {
                    mtx_sps.get("eta_string"),
                    mtx_sps.get("avg_charge"),
                    mtx_sps.get("avg_inflow"),
                    mtx_sps.get("avg_outflow"),
                    mtx_sps.get("is_charging"),
                    mtx_sps.get("is_discharging"),
                    mtx_sps.get("at_max_io")
                }

                local data = {
                    fac.all_sys_ok,
                    fac.rtu_count,
                    fac.auto_scram,
                    fac.ascram_status,
                    tank_statuses,
                    fac.tank_data_tbl,
                    fac.induction_ps_tbl[1].get("computed_status") or types.IMATRIX_STATE.OFFLINE,
                    fac.induction_data_tbl[1],
                    matrix_data,
                    fac.sps_ps_tbl[1].get("computed_status") or types.SPS_STATE.OFFLINE,
                    fac.sps_data_tbl[1],
                    units
                }

                _send(CRDN_TYPE.API_GET_FAC_DTL, data)
            elseif pkt.type == CRDN_TYPE.API_GET_UNIT then
                if pkt.length == 1 and type(pkt.data[1]) == "number" then
                    local u = db.units[pkt.data[1]]

                    local statuses = { u.unit_ps.get("computed_status") }

                    for i = 1, #u.boiler_ps_tbl do table.insert(statuses, u.boiler_ps_tbl[i].get("computed_status")) end
                    for i = 1, #u.turbine_ps_tbl do table.insert(statuses, u.turbine_ps_tbl[i].get("computed_status")) end
                    for i = 1, #u.tank_ps_tbl do table.insert(statuses, u.tank_ps_tbl[i].get("computed_status")) end

                    if u then
                        local data = {
                            u.unit_id,
                            u.connected,
                            statuses,
                            u.a_group,
                            u.alarms,
                            u.annunciator,
                            u.reactor_data,
                            u.boiler_data_tbl,
                            u.turbine_data_tbl,
                            u.tank_data_tbl,
                            u.last_rate_change_ms,
                            u.turbine_flow_stable
                        }

                        _send(CRDN_TYPE.API_GET_UNIT, data)
                    end
                end
            elseif pkt.type == CRDN_TYPE.API_GET_CTRL then
                local data = {}

                for i = 1, #db.units do
                    local u = db.units[i]

                    data[i] = {
                        u.connected,
                        u.reactor_data.rps_tripped,
                        u.reactor_data.mek_status.status,
                        u.reactor_data.mek_status.temp,
                        u.reactor_data.mek_status.burn_rate,
                        u.reactor_data.mek_status.act_burn_rate,
                        u.reactor_data.mek_struct.max_burn,
                        u.annunciator.AutoControl,
                        u.a_group
                    }
                end

                _send(CRDN_TYPE.API_GET_CTRL, data)
            elseif pkt.type == CRDN_TYPE.API_GET_PROC then
                local data = {}

                local fac = db.facility
                local proc = process.get_control_states().process

                -- unit data
                for i = 1, #db.units do
                    local u = db.units[i]

                    data[i] = {
                        u.reactor_data.mek_status.status,
                        u.reactor_data.mek_struct.max_burn,
                        proc.limits[i],
                        u.auto_ready,
                        u.auto_degraded,
                        u.annunciator.AutoControl,
                        u.a_group
                    }
                end

                -- facility data
                data[#db.units + 1] = {
                    fac.status_lines,
                    { fac.auto_ready, fac.auto_active, fac.auto_ramping, fac.auto_saturated },
                    fac.auto_scram,
                    fac.ascram_status,
                    { proc.mode, proc.burn_target, proc.charge_target, proc.gen_target }
                }

                _send(CRDN_TYPE.API_GET_PROC, data)
            elseif pkt.type == CRDN_TYPE.API_GET_WASTE then
                local data = {}

                local fac = db.facility
                local proc = process.get_control_states().process

                -- unit data
                for i = 1, #db.units do
                    local u = db.units[i]

                    data[i] = {
                        u.waste_mode,
                        u.waste_product,
                        u.num_snas,
                        u.sna_peak_rate,
                        u.sna_max_rate,
                        u.sna_out_rate,
                        u.waste_stats
                    }
                end

                local process_rate = 0

                if fac.sps_data_tbl[1].state then
                    process_rate = fac.sps_data_tbl[1].state.process_rate
                end

                -- facility data
                data[#db.units + 1] = {
                    fac.auto_current_waste_product,
                    fac.auto_pu_fallback_active,
                    fac.auto_sps_disabled,
                    proc.waste_product,
                    proc.pu_fallback,
                    proc.sps_low_power,
                    fac.waste_stats,
                    fac.sps_ps_tbl[1].get("computed_status") or types.SPS_STATE.OFFLINE,
                    process_rate
                }

                _send(CRDN_TYPE.API_GET_WASTE, data)
            elseif pkt.type == CRDN_TYPE.API_GET_RAD then
                local data = {}

                for i = 1, #db.units do data[i] = db.units[i].rad_monitors end
                data[#db.units + 1] = db.facility.rad_monitors

                _send(CRDN_TYPE.API_GET_RAD, data)
            else
                log.debug(log_tag .. "handler received unsupported CRDN packet type " .. pkt.type)
            end
        elseif pkt.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
            ---@cast pkt mgmt_frame
            if pkt.type == MGMT_TYPE.KEEP_ALIVE then
                -- keep alive reply
                if pkt.length == 2 then
                    local srv_start = pkt.data[1]
                    -- local api_send = pkt.data[2]
                    local srv_now = util.time()
                    self.last_rtt = srv_now - srv_start

                    if self.last_rtt > 750 then
                        log.warning(log_tag .. "PKT KEEP_ALIVE round trip time > 750ms (" .. self.last_rtt .. "ms)")
                    end

                    -- log.debug(log_header .. "PKT RTT = " .. self.last_rtt .. "ms")
                    -- log.debug(log_header .. "PKT TT  = " .. (srv_now - api_send) .. "ms")

                    iocontrol.fp_pkt_rtt(id, self.last_rtt)
                else
                    log.debug(log_tag .. "SCADA keep alive packet length mismatch")
                end
            elseif pkt.type == MGMT_TYPE.CLOSE then
                -- close the session
                _close()
            elseif pkt.type == MGMT_TYPE.ESTABLISH then
                -- something is wrong, kill the session
                _close()
                log.warning(log_tag .. "terminated session due to an unexpected ESTABLISH packet")
            else
                log.debug(log_tag .. "handler received unsupported SCADA_MGMT packet type " .. pkt.type)
            end
        end
    end

    -- PUBLIC FUNCTIONS --

    -- get the session ID
    ---@nodiscard
    function public.get_id() return id end

    -- get the session database
    ---@nodiscard
    function public.get_db() return self.sDB end

    -- check if a timer matches this session's watchdog
    ---@nodiscard
    function public.check_wd(timer)
        return self.conn_watchdog.is_timer(timer) and self.connected
    end

    -- close the connection
    function public.close()
        _close()
        _send_mgmt(MGMT_TYPE.CLOSE, {})
        log.info(log_tag .. "session closed by server")
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
                local message = in_queue.pop()

                if message ~= nil then
                    if message.qtype == mqueue.TYPE.PACKET then
                        -- handle a packet
                        _handle_packet(message.message)
                    elseif message.qtype == mqueue.TYPE.COMMAND then
                        -- handle instruction
                    elseif message.qtype == mqueue.TYPE.DATA then
                        -- instruction with body
                    end
                end

                -- max 100ms spent processing queue
                if util.time() - handle_start > 100 then
                    log.warning(log_tag .. "exceeded 100ms queue process limit")
                    break
                end
            end

            -- exit if connection was closed
            if not self.connected then
                log.info(log_tag .. "session closed by remote host")
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
                _send_mgmt(MGMT_TYPE.KEEP_ALIVE, { util.time() })
                periodics.keep_alive = 0
            end

            self.periodics.last_update = util.time()

            ---------------------
            -- attempt retries --
            ---------------------

            -- local rtimes = self.retry_times
        end

        return self.connected
    end

    return public
end

return pocket
