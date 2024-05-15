--
-- I/O Control for Supervisor/Coordinator Integration
--

local log     = require("scada-common.log")
local psil    = require("scada-common.psil")
local types   = require("scada-common.types")
local util    = require("scada-common.util")

local process = require("coordinator.process")
local sounder = require("coordinator.sounder")

local pgi     = require("coordinator.ui.pgi")

local ALARM_STATE = types.ALARM_STATE
local PROCESS = types.PROCESS

-- nominal RTT is ping (0ms to 10ms usually) + 500ms for CRD main loop tick
local WARN_RTT = 1000   -- 2x as long as expected w/ 0 ping
local HIGH_RTT = 1500   -- 3.33x as long as expected w/ 0 ping

local iocontrol = {}

---@class ioctl
local io = {}

-- luacheck: no unused args

-- placeholder acknowledge function for type hinting
---@param success boolean
---@diagnostic disable-next-line: unused-local
local function __generic_ack(success) end

-- luacheck: unused args

-- initialize front panel PSIL
---@param firmware_v string coordinator version
---@param comms_v string comms version
function iocontrol.init_fp(firmware_v, comms_v)
    ---@class ioctl_front_panel
    io.fp = { ps = psil.create() }

    io.fp.ps.publish("version", firmware_v)
    io.fp.ps.publish("comms_version", comms_v)
end

-- initialize the coordinator IO controller
---@param conf facility_conf configuration
---@param comms coord_comms comms reference
---@param temp_scale integer temperature unit (1 = K, 2 = C, 3 = F, 4 = R)
function iocontrol.init(conf, comms, temp_scale)
    -- temperature unit label and conversion function (from Kelvin)
    if temp_scale == 2 then
        io.temp_label = "\xb0C"
        io.temp_convert = function (t) return t - 273.15 end
    elseif temp_scale == 3 then
        io.temp_label = "\xb0F"
        io.temp_convert = function (t) return (1.8 * (t - 273.15)) + 32 end
    elseif temp_scale == 4 then
        io.temp_label = "\xb0R"
        io.temp_convert = function (t) return 1.8 * t end
    else
        io.temp_label = "K"
        io.temp_convert = function (t) return t end
    end

    -- facility data structure
    ---@class ioctl_facility
    io.facility = {
        conf = conf,
        num_units = conf.num_units,
        tank_mode = conf.cooling.fac_tank_mode,
        tank_defs = conf.cooling.fac_tank_defs,
        all_sys_ok = false,
        rtu_count = 0,

        auto_ready = false,
        auto_active = false,
        auto_ramping = false,
        auto_saturated = false,

        auto_scram = false,
        ---@type ascram_status
        ascram_status = {
            matrix_dc = false,
            matrix_fill = false,
            crit_alarm = false,
            radiation = false,
            gen_fault = false
        },

        ---@type WASTE_PRODUCT
        auto_current_waste_product = types.WASTE_PRODUCT.PLUTONIUM,
        auto_pu_fallback_active = false,
        auto_sps_disabled = false,

        radiation = types.new_zero_radiation_reading(),

        save_cfg_ack = __generic_ack,
        start_ack = __generic_ack,
        stop_ack = __generic_ack,
        scram_ack = __generic_ack,
        ack_alarms_ack = __generic_ack,

        alarm_tones = { false, false, false, false, false, false, false, false },

        ps = psil.create(),

        induction_ps_tbl = {},
        induction_data_tbl = {},

        sps_ps_tbl = {},
        sps_data_tbl = {},

        tank_ps_tbl = {},
        tank_data_tbl = {},

        env_d_ps = psil.create(),
        env_d_data = {}
    }

    -- create induction and SPS tables (currently only 1 of each is supported)
    table.insert(io.facility.induction_ps_tbl, psil.create())
    table.insert(io.facility.induction_data_tbl, {})
    table.insert(io.facility.sps_ps_tbl, psil.create())
    table.insert(io.facility.sps_data_tbl, {})

    -- determine tank information
    if io.facility.tank_mode == 0 then
        io.facility.tank_defs = {}
        -- on facility tank mode 0, setup tank defs to match unit tank option
        for i = 1, conf.num_units do
            io.facility.tank_defs[i] = util.trinary(conf.cooling.r_cool[i].TankConnection, 1, 0)
        end

        io.facility.tank_list = { table.unpack(io.facility.tank_defs) }
    else
        -- decode the layout of tanks from the connections definitions
        local tank_mode = io.facility.tank_mode
        local tank_defs = io.facility.tank_defs
        local tank_list = { table.unpack(tank_defs) }

        local function calc_fdef(start_idx, end_idx)
            local first = 4
            for i = start_idx, end_idx do
                if io.facility.tank_defs[i] == 2 then
                    if i < first then first = i end
                end
            end
            return first
        end

        if tank_mode == 1 then
            -- (1) 1 total facility tank (A A A A)
            local first_fdef = calc_fdef(1, #tank_defs)
            for i = 1, #tank_defs do
                if i > first_fdef and tank_defs[i] == 2 then
                    tank_list[i] = 0
                end
            end
        elseif tank_mode == 2 then
            -- (2) 2 total facility tanks (A A A B)
            local first_fdef = calc_fdef(1, math.min(3, #tank_defs))
            for i = 1, #tank_defs do
                if (i ~= 4) and (i > first_fdef) and (tank_defs[i] == 2) then
                    tank_list[i] = 0
                end
            end
        elseif tank_mode == 3 then
            -- (3) 2 total facility tanks (A A B B)
            for _, a in pairs({ 1, 3 }) do
                local b = a + 1
                if (tank_defs[a] == 2) and (tank_defs[b] == 2) then
                    tank_list[b] = 0
                end
            end
        elseif tank_mode == 4 then
            -- (4) 2 total facility tanks (A B B B)
            local first_fdef = calc_fdef(2, #tank_defs)
            for i = 1, #tank_defs do
                if (i ~= 1) and (i > first_fdef) and (tank_defs[i] == 2) then
                    tank_list[i] = 0
                end
            end
        elseif tank_mode == 5 then
            -- (5) 3 total facility tanks (A A B C)
            local first_fdef = calc_fdef(1, math.min(2, #tank_defs))
            for i = 1, #tank_defs do
                if (not (i == 3 or i == 4)) and (i > first_fdef) and (tank_defs[i] == 2) then
                    tank_list[i] = 0
                end
            end
        elseif tank_mode == 6 then
            -- (6) 3 total facility tanks (A B B C)
            local first_fdef = calc_fdef(2, math.min(3, #tank_defs))
            for i = 1, #tank_defs do
                if (not (i == 1 or i == 4)) and (i > first_fdef) and (tank_defs[i] == 2) then
                    tank_list[i] = 0
                end
            end
        elseif tank_mode == 7 then
            -- (7) 3 total facility tanks (A B C C)
            local first_fdef = calc_fdef(3, #tank_defs)
            for i = 1, #tank_defs do
                if (not (i == 1 or i == 2)) and (i > first_fdef) and (tank_defs[i] == 2) then
                    tank_list[i] = 0
                end
            end
        end

        io.facility.tank_list = tank_list
    end

    -- create facility tank tables
    for i = 1, #io.facility.tank_list do
        if io.facility.tank_list[i] == 2 then
            table.insert(io.facility.tank_ps_tbl, psil.create())
            table.insert(io.facility.tank_data_tbl, {})
        end
    end

    -- create unit data structures
    io.units = {}
    for i = 1, conf.num_units do
        local function ack(alarm) process.ack_alarm(i, alarm) end
        local function reset(alarm) process.reset_alarm(i, alarm) end

        ---@class ioctl_unit
        local entry = {
            unit_id = i,
            connected = false,
            rtu_hw = { boilers = {}, turbines = {} },

            num_boilers = 0,
            num_turbines = 0,
            num_snas = 0,
            has_tank = conf.cooling.r_cool[i].TankConnection,

            control_state = false,
            burn_rate_cmd = 0.0,
            radiation = types.new_zero_radiation_reading(),

            sna_peak_rate = 0.0,
            sna_max_rate = 0.0,
            sna_out_rate = 0.0,

            waste_mode = types.WASTE_MODE.MANUAL_PLUTONIUM,
            waste_product = types.WASTE_PRODUCT.PLUTONIUM,

            -- auto control group
            a_group = 0,

            start = function () process.start(i) end,
            scram = function () process.scram(i) end,
            reset_rps = function () process.reset_rps(i) end,
            ack_alarms = function () process.ack_all_alarms(i) end,
            set_burn = function (rate) process.set_rate(i, rate) end,        ---@param rate number burn rate
            set_waste = function (mode) process.set_unit_waste(i, mode) end, ---@param mode WASTE_MODE waste processing mode

            set_group = function (grp) process.set_group(i, grp) end,        ---@param grp integer|0 group ID or 0 for manual

            start_ack = __generic_ack,
            scram_ack = __generic_ack,
            reset_rps_ack = __generic_ack,
            ack_alarms_ack = __generic_ack,
            set_burn_ack = __generic_ack,
            set_waste_ack = __generic_ack,

            alarm_callbacks = {
                c_breach   = { ack = function () ack(1)  end, reset = function () reset(1)  end },
                radiation  = { ack = function () ack(2)  end, reset = function () reset(2)  end },
                r_lost     = { ack = function () ack(3)  end, reset = function () reset(3)  end },
                dmg_crit   = { ack = function () ack(4)  end, reset = function () reset(4)  end },
                damage     = { ack = function () ack(5)  end, reset = function () reset(5)  end },
                over_temp  = { ack = function () ack(6)  end, reset = function () reset(6)  end },
                high_temp  = { ack = function () ack(7)  end, reset = function () reset(7)  end },
                waste_leak = { ack = function () ack(8)  end, reset = function () reset(8)  end },
                waste_high = { ack = function () ack(9)  end, reset = function () reset(9)  end },
                rps_trans  = { ack = function () ack(10) end, reset = function () reset(10) end },
                rcs_trans  = { ack = function () ack(11) end, reset = function () reset(11) end },
                t_trip     = { ack = function () ack(12) end, reset = function () reset(12) end }
            },

            ---@type alarms
            alarms = {
                ALARM_STATE.INACTIVE, -- containment breach
                ALARM_STATE.INACTIVE, -- containment radiation
                ALARM_STATE.INACTIVE, -- reactor lost
                ALARM_STATE.INACTIVE, -- damage critical
                ALARM_STATE.INACTIVE, -- reactor taking damage
                ALARM_STATE.INACTIVE, -- reactor over temperature
                ALARM_STATE.INACTIVE, -- reactor high temperature
                ALARM_STATE.INACTIVE, -- waste leak
                ALARM_STATE.INACTIVE, -- waste level high
                ALARM_STATE.INACTIVE, -- RPS transient
                ALARM_STATE.INACTIVE, -- RCS transient
                ALARM_STATE.INACTIVE  -- turbine trip
            },

            annunciator = {},   ---@type annunciator

            unit_ps = psil.create(),
            reactor_data = {},  ---@type reactor_db

            boiler_ps_tbl = {},
            boiler_data_tbl = {},

            turbine_ps_tbl = {},
            turbine_data_tbl = {},

            tank_ps_tbl = {},
            tank_data_tbl = {}
        }

        -- on other facility modes, overwrite unit TANK option with facility tank defs
        if io.facility.tank_mode ~= 0 then
            entry.has_tank = conf.cooling.fac_tank_defs[i] > 0
        end

        -- create boiler tables
        for _ = 1, conf.cooling.r_cool[i].BoilerCount do
            table.insert(entry.boiler_ps_tbl, psil.create())
            table.insert(entry.boiler_data_tbl, {})
            table.insert(entry.rtu_hw.boilers, { connected = false, faulted = false })
        end

        -- create turbine tables
        for _ = 1, conf.cooling.r_cool[i].TurbineCount do
            table.insert(entry.turbine_ps_tbl, psil.create())
            table.insert(entry.turbine_data_tbl, {})
            table.insert(entry.rtu_hw.turbines, { connected = false, faulted = false })
        end

        -- create tank tables
        if io.facility.tank_defs[i] == 1 then
            table.insert(entry.tank_ps_tbl, psil.create())
            table.insert(entry.tank_data_tbl, {})
        end

        entry.num_boilers = #entry.boiler_data_tbl
        entry.num_turbines = #entry.turbine_data_tbl

        table.insert(io.units, entry)
    end

    -- pass IO control here since it can't be require'd due to a require loop
    process.init(io, comms)
end

--#region Front Panel PSIL

-- toggle heartbeat indicator
function iocontrol.heartbeat() io.fp.ps.toggle("heartbeat") end

-- report presence of the wireless modem
---@param has_modem boolean
function iocontrol.fp_has_modem(has_modem) io.fp.ps.publish("has_modem", has_modem) end

-- report presence of the speaker
---@param has_speaker boolean
function iocontrol.fp_has_speaker(has_speaker) io.fp.ps.publish("has_speaker", has_speaker) end

-- report supervisor link state
---@param state integer
function iocontrol.fp_link_state(state) io.fp.ps.publish("link_state", state) end

-- report monitor connection state
---@param id string|integer unit ID for unit monitor, "main" for main monitor, or "flow" for flow monitor
function iocontrol.fp_monitor_state(id, connected)
    local name = nil

    if id == "main" then
        name = "main_monitor"
    elseif id == "flow" then
        name = "flow_monitor"
    elseif type(id) == "number" then
        name = "unit_monitor_" .. id
    end

    if name ~= nil then
        io.fp.ps.publish(name, connected)
    end
end

-- report thread (routine) statuses
---@param thread string thread name
---@param ok boolean thread state
function iocontrol.fp_rt_status(thread, ok)
    io.fp.ps.publish(util.c("routine__", thread), ok)
end

-- report PKT firmware version and PKT session connection state
---@param session_id integer PKT session
---@param fw string firmware version
---@param s_addr integer PKT computer ID
function iocontrol.fp_pkt_connected(session_id, fw, s_addr)
    io.fp.ps.publish("pkt_" .. session_id .. "_fw", fw)
    io.fp.ps.publish("pkt_" .. session_id .. "_addr", util.sprintf("@ C% 3d", s_addr))
    pgi.create_pkt_entry(session_id)
end

-- report PKT session disconnected
---@param session_id integer PKT session
function iocontrol.fp_pkt_disconnected(session_id)
    pgi.delete_pkt_entry(session_id)
end

-- transmit PKT session RTT
---@param session_id integer PKT session
---@param rtt integer round trip time
function iocontrol.fp_pkt_rtt(session_id, rtt)
    io.fp.ps.publish("pkt_" .. session_id .. "_rtt", rtt)

    if rtt > HIGH_RTT then
        io.fp.ps.publish("pkt_" .. session_id .. "_rtt_color", colors.red)
    elseif rtt > WARN_RTT then
        io.fp.ps.publish("pkt_" .. session_id .. "_rtt_color", colors.yellow_hc)
    else
        io.fp.ps.publish("pkt_" .. session_id .. "_rtt_color", colors.green_hc)
    end
end

--#endregion

--#region Builds

-- record and publish multiblock RTU build data
---@param id integer
---@param entry table
---@param data_tbl table
---@param ps_tbl table
---@param create boolean? true to create an entry if non exists, false to fail on missing
---@return boolean ok true if data saved, false if invalid ID
local function _record_multiblock_build(id, entry, data_tbl, ps_tbl, create)
    local exists = type(data_tbl[id]) == "table"
    if exists or create then
        if not exists then
            ps_tbl[id] = psil.create()
            data_tbl[id] = {}
        end

        data_tbl[id].formed = entry[1]  ---@type boolean
        data_tbl[id].build  = entry[2]  ---@type table

        ps_tbl[id].publish("formed", entry[1])

        for key, val in pairs(data_tbl[id].build) do ps_tbl[id].publish(key, val) end
    end

    return exists or (create == true)
end

-- populate facility structure builds
---@param build table
---@return boolean valid
function iocontrol.record_facility_builds(build)
    local valid = true

    if type(build) == "table" then
        local fac = io.facility

        -- induction matricies
        if type(build.induction) == "table" then
            for id, matrix in pairs(build.induction) do
                if not _record_multiblock_build(id, matrix, fac.induction_data_tbl, fac.induction_ps_tbl) then
                    log.debug(util.c("iocontrol.record_facility_builds: invalid induction matrix id ", id))
                    valid = false
                end
            end
        end

        -- SPS
        if type(build.sps) == "table" then
            for id, sps in pairs(build.sps) do
                if not _record_multiblock_build(id, sps, fac.sps_data_tbl, fac.sps_ps_tbl) then
                    log.debug(util.c("iocontrol.record_facility_builds: invalid SPS id ", id))
                    valid = false
                end
            end
        end

        -- dynamic tanks
        if type(build.tanks) == "table" then
            for id, tank in pairs(build.tanks) do
                _record_multiblock_build(id, tank, fac.tank_data_tbl, fac.tank_ps_tbl, true)
            end
        end
    else
        log.debug("facility builds not a table")
        valid = false
    end

    return valid
end

-- populate unit structure builds
---@param builds table
---@return boolean valid
function iocontrol.record_unit_builds(builds)
    local valid = true

    -- note: if not all units and RTUs are connected, some will be nil
    for id, build in pairs(builds) do
        local unit = io.units[id] ---@type ioctl_unit

        local log_header = util.c("iocontrol.record_unit_builds[UNIT ", id, "]: ")

        if type(build) ~= "table" then
            log.debug(log_header .. "build not a table")
            valid = false
        elseif type(unit) ~= "table" then
            log.debug(log_header .. "invalid unit id")
            valid = false
        else
            -- reactor build
            if type(build.reactor) == "table" then
                unit.reactor_data.mek_struct = build.reactor    ---@type mek_struct
                for key, val in pairs(unit.reactor_data.mek_struct) do
                    unit.unit_ps.publish(key, val)
                end

                if (type(unit.reactor_data.mek_struct.length) == "number") and (unit.reactor_data.mek_struct.length ~= 0) and
                    (type(unit.reactor_data.mek_struct.width) == "number") and (unit.reactor_data.mek_struct.width ~= 0) then
                    unit.unit_ps.publish("size", { unit.reactor_data.mek_struct.length, unit.reactor_data.mek_struct.width })
                end
            end

            -- boiler builds
            if type(build.boilers) == "table" then
                for b_id, boiler in pairs(build.boilers) do
                    if not _record_multiblock_build(b_id, boiler, unit.boiler_data_tbl, unit.boiler_ps_tbl) then
                        log.debug(util.c(log_header, "invalid boiler id ", b_id))
                        valid = false
                    end
                end
            end

            -- turbine builds
            if type(build.turbines) == "table" then
                for t_id, turbine in pairs(build.turbines) do
                    if not _record_multiblock_build(t_id, turbine, unit.turbine_data_tbl, unit.turbine_ps_tbl) then
                        log.debug(util.c(log_header, "invalid turbine id ", t_id))
                        valid = false
                    end
                end
            end

            -- dynamic tank builds
            if type(build.tanks) == "table" then
                for d_id, d_tank in pairs(build.tanks) do
                    _record_multiblock_build(d_id, d_tank, unit.tank_data_tbl, unit.tank_ps_tbl, true)
                end
            end
        end
    end

    return valid
end

--#endregion

--#region Statuses

-- record and publish multiblock status data
---@param entry any
---@param data imatrix_session_db|sps_session_db|dynamicv_session_db|turbinev_session_db|boilerv_session_db
---@param ps psil
---@return boolean is_faulted
local function _record_multiblock_status(entry, data, ps)
    local is_faulted = entry[1] ---@type boolean
    data.formed      = entry[2] ---@type boolean
    data.state       = entry[3] ---@type table
    data.tanks       = entry[4] ---@type table

    ps.publish("formed", data.formed)
    ps.publish("faulted", is_faulted)

    for key, val in pairs(data.state) do ps.publish(key, val) end
    for key, val in pairs(data.tanks) do ps.publish(key, val) end

    return is_faulted
end

-- update facility status
---@param status table
---@return boolean valid
function iocontrol.update_facility_status(status)
    local valid = true
    local log_header = util.c("iocontrol.update_facility_status: ")

    if type(status) ~= "table" then
        log.debug(util.c(log_header, "status not a table"))
        valid = false
    else
        local fac = io.facility

        -- auto control status information

        local ctl_status = status[1]

        if type(ctl_status) == "table" and #ctl_status == 17 then
            fac.all_sys_ok = ctl_status[1]
            fac.auto_ready = ctl_status[2]

            if type(ctl_status[3]) == "number" then
                fac.auto_active = ctl_status[3] > PROCESS.INACTIVE
            else
                fac.auto_active = false
                valid = false
            end

            fac.auto_ramping = ctl_status[4]
            fac.auto_saturated = ctl_status[5]

            fac.auto_scram = ctl_status[6]
            fac.ascram_status.matrix_dc = ctl_status[7]
            fac.ascram_status.matrix_fill = ctl_status[8]
            fac.ascram_status.crit_alarm = ctl_status[9]
            fac.ascram_status.radiation = ctl_status[10]
            fac.ascram_status.gen_fault = ctl_status[11]

            fac.status_line_1 = ctl_status[12]
            fac.status_line_2 = ctl_status[13]

            fac.ps.publish("all_sys_ok", fac.all_sys_ok)
            fac.ps.publish("auto_ready", fac.auto_ready)
            fac.ps.publish("auto_active", fac.auto_active)
            fac.ps.publish("auto_ramping", fac.auto_ramping)
            fac.ps.publish("auto_saturated", fac.auto_saturated)
            fac.ps.publish("auto_scram", fac.auto_scram)
            fac.ps.publish("as_matrix_dc", fac.ascram_status.matrix_dc)
            fac.ps.publish("as_matrix_fill", fac.ascram_status.matrix_fill)
            fac.ps.publish("as_crit_alarm", fac.ascram_status.crit_alarm)
            fac.ps.publish("as_radiation", fac.ascram_status.radiation)
            fac.ps.publish("as_gen_fault", fac.ascram_status.gen_fault)
            fac.ps.publish("status_line_1", fac.status_line_1)
            fac.ps.publish("status_line_2", fac.status_line_2)

            local group_map = ctl_status[14]

            if (type(group_map) == "table") and (#group_map == fac.num_units) then
                local names = { "Manual", "Primary", "Secondary", "Tertiary", "Backup" }
                for i = 1, #group_map do
                    io.units[i].a_group = group_map[i]
                    io.units[i].unit_ps.publish("auto_group_id", group_map[i])
                    io.units[i].unit_ps.publish("auto_group", names[group_map[i] + 1])
                end
            end

            fac.auto_current_waste_product = ctl_status[15]
            fac.auto_pu_fallback_active = ctl_status[16]
            fac.auto_sps_disabled = ctl_status[17]

            fac.ps.publish("current_waste_product", fac.auto_current_waste_product)
            fac.ps.publish("pu_fallback_active", fac.auto_pu_fallback_active)
            fac.ps.publish("sps_disabled_low_power", fac.auto_sps_disabled)
        else
            log.debug(log_header .. "control status not a table or length mismatch")
            valid = false
        end

        -- RTU statuses

        local rtu_statuses = status[2]

        fac.rtu_count = 0

        if type(rtu_statuses) == "table" then
            -- connected RTU count
            fac.rtu_count = rtu_statuses.count

            -- power statistics
            if type(rtu_statuses.power) == "table" and #rtu_statuses.power == 4 then
                local data = fac.induction_data_tbl[1] ---@type imatrix_session_db
                local ps   = fac.induction_ps_tbl[1]   ---@type psil

                local chg   = tonumber(rtu_statuses.power[1])
                local in_f  = tonumber(rtu_statuses.power[2])
                local out_f = tonumber(rtu_statuses.power[3])
                local eta   = tonumber(rtu_statuses.power[4])

                ps.publish("avg_charge", chg)
                ps.publish("avg_inflow", in_f)
                ps.publish("avg_outflow", out_f)
                ps.publish("eta_ms", eta)

                ps.publish("is_charging", in_f > out_f)
                ps.publish("is_discharging", out_f > in_f)

                if data and data.build then
                    local cap = util.joules_to_fe(data.build.transfer_cap)
                    ps.publish("at_max_io", in_f >= cap or out_f >= cap)
                end
            else
                log.debug(log_header .. "power statistics list not a table")
                valid = false
            end

            -- induction matricies statuses
            if type(rtu_statuses.induction) == "table" then
                for id = 1, #fac.induction_ps_tbl do
                    if rtu_statuses.induction[id] == nil then
                        -- disconnected
                        fac.induction_ps_tbl[id].publish("computed_status", 1)
                    end
                end

                for id, matrix in pairs(rtu_statuses.induction) do
                    if type(fac.induction_data_tbl[id]) == "table" then
                        local data = fac.induction_data_tbl[id] ---@type imatrix_session_db
                        local ps   = fac.induction_ps_tbl[id]   ---@type psil

                        local rtu_faulted = _record_multiblock_status(matrix, data, ps)

                        if rtu_faulted then
                            ps.publish("computed_status", 3)    -- faulted
                        elseif data.formed then
                            if data.tanks.energy_fill >= 0.99 then
                                ps.publish("computed_status", 6)    -- full
                            elseif data.tanks.energy_fill <= 0.01 then
                                ps.publish("computed_status", 5)    -- empty
                            else
                                ps.publish("computed_status", 4)    -- on-line
                            end
                        else
                            ps.publish("computed_status", 2)        -- not formed
                        end
                    else
                        log.debug(util.c(log_header, "invalid induction matrix id ", id))
                    end
                end
            else
                log.debug(log_header .. "induction matrix list not a table")
                valid = false
            end

            -- SPS statuses
            if type(rtu_statuses.sps) == "table" then
                for id = 1, #fac.sps_ps_tbl do
                    if rtu_statuses.sps[id] == nil then
                        -- disconnected
                        fac.sps_ps_tbl[id].publish("computed_status", 1)
                    end
                end

                for id, sps in pairs(rtu_statuses.sps) do
                    if type(fac.sps_data_tbl[id]) == "table" then
                        local data = fac.sps_data_tbl[id] ---@type sps_session_db
                        local ps   = fac.sps_ps_tbl[id]   ---@type psil

                        local rtu_faulted = _record_multiblock_status(sps, data, ps)

                        if rtu_faulted then
                            ps.publish("computed_status", 3)        -- faulted
                        elseif data.formed then
                            if data.state.process_rate > 0 then
                                ps.publish("computed_status", 5)    -- active
                            else
                                ps.publish("computed_status", 4)    -- idle
                            end
                        else
                            ps.publish("computed_status", 2)        -- not formed
                        end

                        io.facility.ps.publish("am_rate", data.state.process_rate * 1000)
                    else
                        log.debug(util.c(log_header, "invalid sps id ", id))
                    end
                end
            else
                log.debug(log_header .. "sps list not a table")
                valid = false
            end

            -- dynamic tank statuses
            if type(rtu_statuses.tanks) == "table" then
                for id = 1, #fac.tank_ps_tbl do
                    if rtu_statuses.tanks[id] == nil then
                        -- disconnected
                        fac.tank_ps_tbl[id].publish("computed_status", 1)
                    end
                end

                for id, tank in pairs(rtu_statuses.tanks) do
                    if type(fac.tank_data_tbl[id]) == "table" then
                        local data = fac.tank_data_tbl[id] ---@type dynamicv_session_db
                        local ps   = fac.tank_ps_tbl[id]   ---@type psil

                        local rtu_faulted = _record_multiblock_status(tank, data, ps)

                        if rtu_faulted then
                            ps.publish("computed_status", 3)        -- faulted
                        elseif data.formed then
                            if data.tanks.fill >= 0.99 then
                                ps.publish("computed_status", 6)    -- full
                            elseif data.tanks.fill < 0.20 then
                                ps.publish("computed_status", 5)    -- low
                            else
                                ps.publish("computed_status", 4)    -- on-line
                            end
                        else
                            ps.publish("computed_status", 2)        -- not formed
                        end
                    else
                        log.debug(util.c(log_header, "invalid dynamic tank id ", id))
                    end
                end
            else
                log.debug(log_header .. "dyanmic tank list not a table")
                valid = false
            end

            -- environment detector status
            if type(rtu_statuses.envds) == "table" then
                local max_rad, max_reading, any_conn, any_faulted = 0, types.new_zero_radiation_reading(), false, false

                for _, envd in pairs(rtu_statuses.envds) do
                    local rtu_faulted = envd[1] ---@type boolean
                    local radiation   = envd[2] ---@type radiation_reading
                    local rad_raw     = envd[3] ---@type number

                    any_conn = true
                    any_faulted = any_faulted or rtu_faulted

                    if rad_raw > max_rad then
                        max_rad = rad_raw
                        max_reading = radiation
                    end
                end

                if any_conn then
                    fac.radiation = max_reading
                    fac.ps.publish("rad_computed_status", util.trinary(any_faulted, 2, 3))
                else
                    fac.radiation = types.new_zero_radiation_reading()
                    fac.ps.publish("rad_computed_status", 1)
                end

                fac.ps.publish("radiation", fac.radiation)
            else
                log.debug(log_header .. "environment detector list not a table")
                valid = false
            end
        else
            log.debug(log_header .. "rtu statuses not a table")
            valid = false
        end

        fac.ps.publish("rtu_count", fac.rtu_count)

        -- alarm tone commands

        if (type(status[3]) == "table") and (#status[3] == 8) then
            fac.alarm_tones = status[3]
            sounder.set(fac.alarm_tones)
        else
            log.debug(log_header .. "alarm tones not a table or length mismatch")
            valid = false
        end
    end

    return valid
end

-- update unit statuses
---@param statuses table
---@return boolean valid
function iocontrol.update_unit_statuses(statuses)
    local valid = true

    if type(statuses) ~= "table" then
        log.debug("iocontrol.update_unit_statuses: unit statuses not a table")
        valid = false
    elseif #statuses ~= #io.units then
        log.debug("iocontrol.update_unit_statuses: number of provided unit statuses does not match expected number of units")
        valid = false
    else
        local burn_rate_sum = 0.0
        local sna_count_sum = 0
        local pu_rate, po_rate, po_pl_rate, po_am_rate, spent_rate = 0.0, 0.0, 0.0, 0.0, 0.0

        -- get all unit statuses
        for i = 1, #statuses do
            local log_header = util.c("iocontrol.update_unit_statuses[unit ", i, "]: ")

            local unit = io.units[i]    ---@type ioctl_unit
            local status = statuses[i]

            local burn_rate = 0.0

            if type(status) ~= "table" or #status ~= 6 then
                log.debug(log_header .. "invalid status entry in unit statuses (not a table or invalid length)")
                valid = false
            else
                -- reactor PLC status
                local reactor_status = status[1]

                if type(reactor_status) ~= "table" then
                    reactor_status = {}
                    log.debug(log_header .. "reactor status not a table")
                end

                if #reactor_status == 0 then
                    unit.connected = false
                    unit.unit_ps.publish("computed_status", 1)   -- disconnected
                elseif #reactor_status == 3 then
                    local mek_status = reactor_status[1]
                    local rps_status = reactor_status[2]
                    local gen_status = reactor_status[3]

                    if #gen_status == 6 then
                        unit.reactor_data.last_status_update = gen_status[1]
                        unit.reactor_data.control_state      = gen_status[2]
                        unit.reactor_data.rps_tripped        = gen_status[3]
                        unit.reactor_data.rps_trip_cause     = gen_status[4]
                        unit.reactor_data.no_reactor         = gen_status[5]
                        unit.reactor_data.formed             = gen_status[6]
                    else
                        log.debug(log_header .. "reactor general status length mismatch")
                    end

                    unit.reactor_data.rps_status = rps_status   ---@type rps_status
                    unit.reactor_data.mek_status = mek_status   ---@type mek_status

                    -- if status hasn't been received, mek_status = {}
                    if type(unit.reactor_data.mek_status.act_burn_rate) == "number" then
                        burn_rate = unit.reactor_data.mek_status.act_burn_rate
                        burn_rate_sum = burn_rate_sum + burn_rate
                    end

                    if unit.reactor_data.mek_status.status then
                        unit.unit_ps.publish("computed_status", 5)       -- running
                    else
                        if unit.reactor_data.no_reactor then
                            unit.unit_ps.publish("computed_status", 3)   -- faulted
                        elseif not unit.reactor_data.formed then
                            unit.unit_ps.publish("computed_status", 2)   -- multiblock not formed
                        elseif unit.reactor_data.rps_status.force_dis then
                            unit.unit_ps.publish("computed_status", 7)   -- reactor force disabled
                        elseif unit.reactor_data.rps_tripped and unit.reactor_data.rps_trip_cause ~= "manual" then
                            unit.unit_ps.publish("computed_status", 6)   -- SCRAM
                        else
                            unit.unit_ps.publish("computed_status", 4)   -- disabled
                        end
                    end

                    for key, val in pairs(unit.reactor_data) do
                        if key ~= "rps_status" and key ~= "mek_struct" and key ~= "mek_status" then
                            unit.unit_ps.publish(key, val)
                        end
                    end

                    if type(unit.reactor_data.rps_status) == "table" then
                        for key, val in pairs(unit.reactor_data.rps_status) do
                            unit.unit_ps.publish(key, val)
                        end
                    end

                    if type(unit.reactor_data.mek_status) == "table" then
                        for key, val in pairs(unit.reactor_data.mek_status) do
                            unit.unit_ps.publish(key, val)
                        end
                    end

                    unit.connected = true
                else
                    log.debug(log_header .. "reactor status length mismatch")
                    valid = false
                end

                -- RTU statuses
                local rtu_statuses = status[2]

                if type(rtu_statuses) == "table" then
                    -- boiler statuses
                    if type(rtu_statuses.boilers) == "table" then
                        local boil_sum = 0

                        for id = 1, #unit.boiler_ps_tbl do
                            local connected = rtu_statuses.boilers[id] ~= nil
                            unit.rtu_hw.boilers[id].connected = connected

                            if not connected then
                                -- disconnected
                                unit.boiler_ps_tbl[id].publish("computed_status", 1)
                            end
                        end

                        for id, boiler in pairs(rtu_statuses.boilers) do
                            if type(unit.boiler_data_tbl[id]) == "table" then
                                local data = unit.boiler_data_tbl[id] ---@type boilerv_session_db
                                local ps   = unit.boiler_ps_tbl[id]   ---@type psil

                                local rtu_faulted = _record_multiblock_status(boiler, data, ps)
                                unit.rtu_hw.boilers[id].faulted = rtu_faulted

                                if rtu_faulted then
                                    ps.publish("computed_status", 3)        -- faulted
                                elseif data.formed then
                                    boil_sum = boil_sum + data.state.boil_rate

                                    if data.state.boil_rate > 0 then
                                        ps.publish("computed_status", 5)    -- active
                                    else
                                        ps.publish("computed_status", 4)    -- idle
                                    end
                                else
                                    ps.publish("computed_status", 2)        -- not formed
                                end
                            else
                                log.debug(util.c(log_header, "invalid boiler id ", id))
                                valid = false
                            end
                        end

                        unit.unit_ps.publish("boiler_boil_sum", boil_sum)
                    else
                        log.debug(log_header .. "boiler list not a table")
                        valid = false
                    end

                    -- turbine statuses
                    if type(rtu_statuses.turbines) == "table" then
                        local flow_sum = 0

                        for id = 1, #unit.turbine_ps_tbl do
                            local connected = rtu_statuses.turbines[id] ~= nil
                            unit.rtu_hw.turbines[id].connected = connected

                            if not connected then
                                -- disconnected
                                unit.turbine_ps_tbl[id].publish("computed_status", 1)
                            end
                        end

                        for id, turbine in pairs(rtu_statuses.turbines) do
                            if type(unit.turbine_data_tbl[id]) == "table" then
                                local data = unit.turbine_data_tbl[id] ---@type turbinev_session_db
                                local ps   = unit.turbine_ps_tbl[id]   ---@type psil

                                local rtu_faulted = _record_multiblock_status(turbine, data, ps)
                                unit.rtu_hw.turbines[id].faulted = rtu_faulted

                                if rtu_faulted then
                                    ps.publish("computed_status", 3)        -- faulted
                                elseif data.formed then
                                    flow_sum = flow_sum + data.state.flow_rate

                                    if data.tanks.energy_fill >= 0.99 then
                                        ps.publish("computed_status", 6)    -- trip
                                    elseif data.state.flow_rate < 100 then
                                        ps.publish("computed_status", 4)    -- idle
                                    else
                                        ps.publish("computed_status", 5)    -- active
                                    end
                                else
                                    ps.publish("computed_status", 2)        -- not formed
                                end
                            else
                                log.debug(util.c(log_header, "invalid turbine id ", id))
                                valid = false
                            end
                        end

                        unit.unit_ps.publish("turbine_flow_sum", flow_sum)
                    else
                        log.debug(log_header .. "turbine list not a table")
                        valid = false
                    end

                    -- dynamic tank statuses
                    if type(rtu_statuses.tanks) == "table" then
                        for id = 1, #unit.tank_ps_tbl do
                            if rtu_statuses.tanks[id] == nil then
                                -- disconnected
                                unit.tank_ps_tbl[id].publish("computed_status", 1)
                            end
                        end

                        for id, tank in pairs(rtu_statuses.tanks) do
                            if type(unit.tank_data_tbl[id]) == "table" then
                                local data = unit.tank_data_tbl[id] ---@type dynamicv_session_db
                                local ps   = unit.tank_ps_tbl[id]   ---@type psil

                                local rtu_faulted = _record_multiblock_status(tank, data, ps)

                                if rtu_faulted then
                                    ps.publish("computed_status", 3)        -- faulted
                                elseif data.formed then
                                    if data.tanks.fill >= 0.99 then
                                        ps.publish("computed_status", 6)    -- full
                                    elseif data.tanks.fill < 0.20 then
                                        ps.publish("computed_status", 5)    -- low
                                    else
                                        ps.publish("computed_status", 4)    -- on-line
                                    end
                                else
                                    ps.publish("computed_status", 2)        -- not formed
                                end
                            else
                                log.debug(util.c(log_header, "invalid dynamic tank id ", id))
                                valid = false
                            end
                        end
                    else
                        log.debug(log_header .. "dynamic tank list not a table")
                        valid = false
                    end

                    -- solar neutron activator status info
                    if type(rtu_statuses.sna) == "table" then
                        unit.num_snas      = rtu_statuses.sna[1] ---@type integer
                        unit.sna_peak_rate = rtu_statuses.sna[2] ---@type number
                        unit.sna_max_rate  = rtu_statuses.sna[3] ---@type number
                        unit.sna_out_rate  = rtu_statuses.sna[4] ---@type number

                        unit.unit_ps.publish("sna_count", unit.num_snas)
                        unit.unit_ps.publish("sna_peak_rate", unit.sna_peak_rate)
                        unit.unit_ps.publish("sna_max_rate", unit.sna_max_rate)
                        unit.unit_ps.publish("sna_out_rate", unit.sna_out_rate)

                        sna_count_sum = sna_count_sum + unit.num_snas
                    else
                        log.debug(log_header .. "sna statistic list not a table")
                        valid = false
                    end

                    -- environment detector status
                    if type(rtu_statuses.envds) == "table" then
                        local max_rad, max_reading, any_conn = 0, types.new_zero_radiation_reading(), false

                        for _, envd in pairs(rtu_statuses.envds) do
                            local radiation = envd[2] ---@type radiation_reading
                            local rad_raw   = envd[3] ---@type number

                            any_conn = true

                            if rad_raw > max_rad then
                                max_rad = rad_raw
                                max_reading = radiation
                            end
                        end

                        if any_conn then
                            unit.radiation = max_reading
                        else
                            unit.radiation = types.new_zero_radiation_reading()
                        end

                        unit.unit_ps.publish("radiation", unit.radiation)
                    else
                        log.debug(log_header .. "radiation monitor list not a table")
                        valid = false
                    end
                else
                    log.debug(log_header .. "rtu list not a table")
                    valid = false
                end

                -- annunciator
                unit.annunciator = status[3]

                if type(unit.annunciator) ~= "table" then
                    unit.annunciator = {}
                    log.debug(log_header .. "annunciator state not a table")
                    valid = false
                end

                for key, val in pairs(unit.annunciator) do
                    if key == "BoilerOnline" or key == "HeatingRateLow" or key == "WaterLevelLow" then
                        -- split up array for all boilers
                        for id = 1, #val do
                            unit.boiler_ps_tbl[id].publish(key, val[id])
                        end
                    elseif key == "TurbineOnline" or key == "SteamDumpOpen" or key == "TurbineOverSpeed" or
                           key == "GeneratorTrip" or key == "TurbineTrip" then
                        -- split up array for all turbines
                        for id = 1, #val do
                            unit.turbine_ps_tbl[id].publish(key, val[id])
                        end
                    elseif type(val) == "table" then
                        -- we missed one of the tables?
                        log.debug(log_header .. "unrecognized table found in annunciator list, this is a bug")
                        valid = false
                    else
                        -- non-table fields
                        unit.unit_ps.publish(key, val)
                    end
                end

                -- alarms
                local alarm_states = status[4]

                if type(alarm_states) == "table" then
                    for id = 1, #alarm_states do
                        local state = alarm_states[id]

                        unit.alarms[id] = state

                        if state == types.ALARM_STATE.TRIPPED or state == types.ALARM_STATE.ACKED then
                            unit.unit_ps.publish("Alarm_" .. id, 2)
                        elseif state == types.ALARM_STATE.RING_BACK then
                            unit.unit_ps.publish("Alarm_" .. id, 3)
                        else
                            unit.unit_ps.publish("Alarm_" .. id, 1)
                        end
                    end
                else
                    log.debug(log_header .. "alarm states not a table")
                    valid = false
                end

                -- unit state fields
                local unit_state = status[5]

                if type(unit_state) == "table" then
                    if #unit_state == 6 then
                        unit.waste_mode = unit_state[5]
                        unit.waste_product = unit_state[6]

                        unit.unit_ps.publish("U_StatusLine1", unit_state[1])
                        unit.unit_ps.publish("U_StatusLine2", unit_state[2])
                        unit.unit_ps.publish("U_AutoReady", unit_state[3])
                        unit.unit_ps.publish("U_AutoDegraded", unit_state[4])
                        unit.unit_ps.publish("U_AutoWaste", unit.waste_mode == types.WASTE_MODE.AUTO)
                        unit.unit_ps.publish("U_WasteMode", unit.waste_mode)
                        unit.unit_ps.publish("U_WasteProduct", unit.waste_product)
                    else
                        log.debug(log_header .. "unit state length mismatch")
                        valid = false
                    end
                else
                    log.debug(log_header .. "unit state not a table")
                    valid = false
                end

                -- valve states
                local valve_states = status[6]

                if type(valve_states) == "table" then
                    if #valve_states == 5 then
                        unit.unit_ps.publish("V_pu_conn", valve_states[1] > 0)
                        unit.unit_ps.publish("V_pu_state", valve_states[1] == 2)
                        unit.unit_ps.publish("V_po_conn", valve_states[2] > 0)
                        unit.unit_ps.publish("V_po_state", valve_states[2] == 2)
                        unit.unit_ps.publish("V_pl_conn", valve_states[3] > 0)
                        unit.unit_ps.publish("V_pl_state", valve_states[3] == 2)
                        unit.unit_ps.publish("V_am_conn", valve_states[4] > 0)
                        unit.unit_ps.publish("V_am_state", valve_states[4] == 2)
                        unit.unit_ps.publish("V_emc_conn", valve_states[5] > 0)
                        unit.unit_ps.publish("V_emc_state", valve_states[5] == 2)
                    else
                        log.debug(log_header .. "valve states length mismatch")
                        valid = false
                    end
                else
                    log.debug(log_header .. "valve states not a table")
                    valid = false
                end

                -- determine waste production for this unit, add to statistics

                local is_pu = unit.waste_product == types.WASTE_PRODUCT.PLUTONIUM
                local waste_rate = burn_rate / 10.0

                local u_spent_rate = waste_rate
                local u_pu_rate = util.trinary(is_pu, waste_rate, 0.0)
                local u_po_rate = unit.sna_out_rate

                unit.unit_ps.publish("pu_rate", u_pu_rate)
                unit.unit_ps.publish("po_rate", u_po_rate)

                unit.unit_ps.publish("sna_in", util.trinary(is_pu, 0, burn_rate))

                if unit.waste_product == types.WASTE_PRODUCT.POLONIUM then
                    u_spent_rate = u_po_rate
                    unit.unit_ps.publish("po_pl_rate", u_po_rate)
                    unit.unit_ps.publish("po_am_rate", 0)
                    po_pl_rate = po_pl_rate + u_po_rate
                elseif unit.waste_product == types.WASTE_PRODUCT.ANTI_MATTER then
                    u_spent_rate = 0
                    unit.unit_ps.publish("po_pl_rate", 0)
                    unit.unit_ps.publish("po_am_rate", u_po_rate)
                    po_am_rate = po_am_rate + u_po_rate
                else
                    unit.unit_ps.publish("po_pl_rate", 0)
                    unit.unit_ps.publish("po_am_rate", 0)
                end

                unit.unit_ps.publish("ws_rate", u_spent_rate)

                pu_rate = pu_rate + u_pu_rate
                po_rate = po_rate + u_po_rate
                spent_rate = spent_rate + u_spent_rate
            end
        end

        io.facility.ps.publish("burn_sum", burn_rate_sum)
        io.facility.ps.publish("sna_count", sna_count_sum)
        io.facility.ps.publish("pu_rate", pu_rate)
        io.facility.ps.publish("po_rate", po_rate)
        io.facility.ps.publish("po_pl_rate", po_pl_rate)
        io.facility.ps.publish("po_am_rate", po_am_rate)
        io.facility.ps.publish("spent_waste_rate", spent_rate)
    end

    return valid
end

--#endregion

-- get the IO controller database
function iocontrol.get_db() return io end

return iocontrol
