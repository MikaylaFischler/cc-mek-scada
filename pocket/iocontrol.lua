--
-- I/O Control for Pocket Integration with Supervisor & Coordinator
--

local const   = require("scada-common.constants")
local psil    = require("scada-common.psil")
local types   = require("scada-common.types")
local util    = require("scada-common.util")

local process = require("pocket.process")

local ALARM = types.ALARM
local ALARM_STATE = types.ALARM_STATE

local ENERGY_SCALE = types.ENERGY_SCALE
local ENERGY_UNITS = types.ENERGY_SCALE_UNITS
local TEMP_SCALE = types.TEMP_SCALE
local TEMP_UNITS = types.TEMP_SCALE_UNITS

---@todo nominal trip time is ping (0ms to 10ms usually)
local WARN_TT = 40
local HIGH_TT = 80

local iocontrol = {}

---@enum POCKET_LINK_STATE
local LINK_STATE = {
    UNLINKED = 0,
    SV_LINK_ONLY = 1,
    API_LINK_ONLY = 2,
    LINKED = 3
}

iocontrol.LINK_STATE = LINK_STATE

---@class pocket_ioctl
local io = {
    version = "unknown",
    ps = psil.create()
}

local config = nil  ---@type pkt_config
local comms  = nil  ---@type pocket_comms

-- initialize facility-independent components of pocket iocontrol
---@param pkt_comms pocket_comms
---@param nav pocket_nav
---@param cfg pkt_config
function iocontrol.init_core(pkt_comms, nav, cfg)
    comms = pkt_comms
    config = cfg

    io.nav = nav

    ---@class pocket_ioctl_diag
    io.diag = {}

    -- alarm testing
    io.diag.tone_test = {
        test_1 = function (state) comms.diag__set_alarm_tone(1, state) end,
        test_2 = function (state) comms.diag__set_alarm_tone(2, state) end,
        test_3 = function (state) comms.diag__set_alarm_tone(3, state) end,
        test_4 = function (state) comms.diag__set_alarm_tone(4, state) end,
        test_5 = function (state) comms.diag__set_alarm_tone(5, state) end,
        test_6 = function (state) comms.diag__set_alarm_tone(6, state) end,
        test_7 = function (state) comms.diag__set_alarm_tone(7, state) end,
        test_8 = function (state) comms.diag__set_alarm_tone(8, state) end,
        stop_tones = function () comms.diag__set_alarm_tone(0, false) end,

        test_breach = function (state) comms.diag__set_alarm(ALARM.ContainmentBreach, state) end,
        test_rad = function (state) comms.diag__set_alarm(ALARM.ContainmentRadiation, state) end,
        test_lost = function (state) comms.diag__set_alarm(ALARM.ReactorLost, state) end,
        test_crit = function (state) comms.diag__set_alarm(ALARM.CriticalDamage, state) end,
        test_dmg = function (state) comms.diag__set_alarm(ALARM.ReactorDamage, state) end,
        test_overtemp = function (state) comms.diag__set_alarm(ALARM.ReactorOverTemp, state) end,
        test_hightemp = function (state) comms.diag__set_alarm(ALARM.ReactorHighTemp, state) end,
        test_wasteleak = function (state) comms.diag__set_alarm(ALARM.ReactorWasteLeak, state) end,
        test_highwaste = function (state) comms.diag__set_alarm(ALARM.ReactorHighWaste, state) end,
        test_rps = function (state) comms.diag__set_alarm(ALARM.RPSTransient, state) end,
        test_rcs = function (state) comms.diag__set_alarm(ALARM.RCSTransient, state) end,
        test_turbinet = function (state) comms.diag__set_alarm(ALARM.TurbineTrip, state) end,
        stop_alarms = function () comms.diag__set_alarm(0, false) end,

        get_tone_states = function () comms.diag__get_alarm_tones() end,

        ready_warn = nil,       ---@type TextBox
        tone_buttons = {},      ---@type SwitchButton[]
        alarm_buttons = {},     ---@type Checkbox[]
        tone_indicators = {}    ---@type IndicatorLight[] indicators to update from supervisor tone states
    }

    -- API access
    ---@class pocket_ioctl_api
    io.api = {
        get_unit = function (unit) comms.api__get_unit(unit) end
    }
end

-- initialize facility-dependent components of pocket iocontrol
---@param conf facility_conf facility configuration
function iocontrol.init_fac(conf)
    local temp_scale, energy_scale = config.TempScale, config.EnergyScale
    io.temp_label = TEMP_UNITS[temp_scale]
    io.energy_label = ENERGY_UNITS[energy_scale]

    -- temperature unit label and conversion function (from Kelvin)
    if temp_scale == TEMP_SCALE.CELSIUS then
        io.temp_convert = function (t) return t - 273.15 end
    elseif temp_scale == TEMP_SCALE.FAHRENHEIT then
        io.temp_convert = function (t) return (1.8 * (t - 273.15)) + 32 end
    elseif temp_scale == TEMP_SCALE.RANKINE then
        io.temp_convert = function (t) return 1.8 * t end
    else
        io.temp_label = "K"
        io.temp_convert = function (t) return t end
    end

    -- energy unit label and conversion function (from Joules unless otherwise specified)
    if energy_scale == ENERGY_SCALE.FE or energy_scale == ENERGY_SCALE.RF then
        io.energy_convert = util.joules_to_fe_rf
        io.energy_convert_from_fe = function (t) return t end
        io.energy_convert_to_fe = function (t) return t end
    else
        io.energy_label = "J"
        io.energy_convert = function (t) return t end
        io.energy_convert_from_fe = util.fe_rf_to_joules
        io.energy_convert_to_fe = util.joules_to_fe_rf
    end

    -- facility data structure
    ---@class pioctl_facility
    io.facility = {
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

        radiation = types.new_zero_radiation_reading(),

        start_ack = nil,         ---@type fun(success: boolean)
        stop_ack = nil,          ---@type fun(success: boolean)
        scram_ack = nil,         ---@type fun(success: boolean)
        ack_alarms_ack = nil,    ---@type fun(success: boolean)

        ps = psil.create(),

        induction_ps_tbl = {},   ---@type psil[]
        induction_data_tbl = {}, ---@type imatrix_session_db[]

        sps_ps_tbl = {},         ---@type psil[]
        sps_data_tbl = {},       ---@type sps_session_db[]

        tank_ps_tbl = {},        ---@type psil[]
        tank_data_tbl = {}       ---@type dynamicv_session_db[]
    }

    -- create induction and SPS tables (currently only 1 of each is supported)
    table.insert(io.facility.induction_ps_tbl, psil.create())
    table.insert(io.facility.induction_data_tbl, {})
    table.insert(io.facility.sps_ps_tbl, psil.create())
    table.insert(io.facility.sps_data_tbl, {})

    -- create unit data structures
    io.units = {}   ---@type pioctl_unit[]
    for i = 1, conf.num_units do
        ---@class pioctl_unit
        local entry = {
            unit_id = i,
            connected = false,
            ---@type { boilers: { connected: boolean, faulted: boolean }[], turbines: { connected: boolean, faulted: boolean }[] }
            rtu_hw = {},

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

            last_rate_change_ms = 0,
            turbine_flow_stable = false,

            -- auto control group
            a_group = types.AUTO_GROUP.MANUAL,

            start = function () process.start(i) end,
            scram = function () process.scram(i) end,
            reset_rps = function () process.reset_rps(i) end,
            ack_alarms = function () process.ack_all_alarms(i) end,
            set_burn = function (rate) process.set_rate(i, rate) end,   ---@param rate number burn rate

            start_ack = nil,        ---@type fun(success: boolean)
            scram_ack = nil,        ---@type fun(success: boolean)
            reset_rps_ack = nil,    ---@type fun(success: boolean)
            ack_alarms_ack = nil,   ---@type fun(success: boolean)

            ---@type { [ALARM]: ALARM_STATE }
            alarms = { ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE },

            annunciator = {},       ---@type annunciator

            unit_ps = psil.create(),
            reactor_data = {},      ---@type reactor_db

            boiler_ps_tbl = {},     ---@type psil[]
            boiler_data_tbl = {},   ---@type boilerv_session_db[]

            turbine_ps_tbl = {},    ---@type psil[]
            turbine_data_tbl = {},  ---@type turbinev_session_db[]

            tank_ps_tbl = {},       ---@type psil[]
            tank_data_tbl = {}      ---@type dynamicv_session_db[]
        }

        -- on other facility modes, overwrite unit TANK option with facility tank defs
        if io.facility.tank_mode ~= 0 then
            entry.has_tank = conf.cooling.fac_tank_defs[i] > 0
        end

        -- create boiler tables
        for _ = 1, conf.cooling.r_cool[i].BoilerCount do
            table.insert(entry.boiler_ps_tbl, psil.create())
            table.insert(entry.boiler_data_tbl, {})
        end

        -- create turbine tables
        for _ = 1, conf.cooling.r_cool[i].TurbineCount do
            table.insert(entry.turbine_ps_tbl, psil.create())
            table.insert(entry.turbine_data_tbl, {})
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

-- set network link state
---@param state POCKET_LINK_STATE
---@param sv_addr integer|false|nil supervisor address if linked, nil if unchanged, false if unlinked
---@param api_addr integer|false|nil coordinator address if linked, nil if unchanged, false if unlinked
function iocontrol.report_link_state(state, sv_addr, api_addr)
    io.ps.publish("link_state", state)

    if state == LINK_STATE.API_LINK_ONLY or state == LINK_STATE.UNLINKED then
        io.ps.publish("svr_conn_quality", 0)
    end

    if state == LINK_STATE.SV_LINK_ONLY or state == LINK_STATE.UNLINKED then
        io.ps.publish("crd_conn_quality", 0)
    end

    if sv_addr then
        io.ps.publish("sv_addr", util.c(sv_addr, ":", config.SVR_Channel))
    elseif sv_addr == false then
        io.ps.publish("sv_addr", "unknown (not linked)")
    end

    if api_addr then
        io.ps.publish("api_addr", util.c(api_addr, ":", config.CRD_Channel))
    elseif api_addr == false then
        io.ps.publish("api_addr", "unknown (not linked)")
    end
end

-- show the reason the supervisor connection isn't linking
function iocontrol.report_svr_link_error(msg) io.ps.publish("svr_link_msg", msg) end

-- show the reason the coordinator api connection isn't linking
function iocontrol.report_crd_link_error(msg) io.ps.publish("api_link_msg", msg) end

-- determine supervisor connection quality (trip time)
---@param trip_time integer
function iocontrol.report_svr_tt(trip_time)
    local state = 3
    if trip_time > HIGH_TT then
        state = 1
    elseif trip_time > WARN_TT then
        state = 2
    end

    io.ps.publish("svr_conn_quality", state)
end

-- determine coordinator connection quality (trip time)
---@param trip_time integer
function iocontrol.report_crd_tt(trip_time)
    local state = 3
    if trip_time > HIGH_TT then
        state = 1
    elseif trip_time > WARN_TT then
        state = 2
    end

    io.ps.publish("crd_conn_quality", state)
end

-- populate facility data from API_GET_FAC
---@param data table
---@return boolean valid
function iocontrol.record_facility_data(data)
    local valid = true

    local fac = io.facility

    fac.all_sys_ok = data[1]
    fac.rtu_count = data[2]
    fac.radiation = data[3]

    -- auto control
    if type(data[4]) == "table" and #data[4] == 4 then
        fac.auto_ready = data[4][1]
        fac.auto_active = data[4][2]
        fac.auto_ramping = data[4][3]
        fac.auto_saturated = data[4][4]
    end

    -- waste
    if type(data[5]) == "table" and #data[5] == 2 then
        fac.auto_current_waste_product = data[5][1]
        fac.auto_pu_fallback_active = data[5][2]
    end

    fac.num_tanks = data[6]
    fac.has_imatrix = data[7]
    fac.has_sps = data[8]

    return valid
end

local function tripped(state) return state == ALARM_STATE.TRIPPED or state == ALARM_STATE.ACKED end

local function _record_multiblock_status(faulted, data, ps)
    ps.publish("formed", data.formed)
    ps.publish("faulted", faulted)

    for key, val in pairs(data.state) do ps.publish(key, val) end
    for key, val in pairs(data.tanks) do ps.publish(key, val) end
end

-- update unit status data from API_GET_UNIT
---@param data table
function iocontrol.record_unit_data(data)
    local unit = io.units[data[1]]

    unit.connected = data[2]
    unit.rtu_hw = data[3]
    unit.a_group = data[4]
    unit.alarms = data[5]

    unit.unit_ps.publish("auto_group_id", unit.a_group)
    unit.unit_ps.publish("auto_group", types.AUTO_GROUP_NAMES[unit.a_group + 1])

    --#region Annunciator

    unit.annunciator = data[6]

    local rcs_disconn, rcs_warn, rcs_hazard = false, false, false

    for key, val in pairs(unit.annunciator) do
        if key == "BoilerOnline" or key == "TurbineOnline" then
            local every = true

            -- split up online arrays
            for id = 1, #val do
                every = every and val[id]

                if key == "BoilerOnline" then
                    unit.boiler_ps_tbl[id].publish(key, val[id])
                else
                    unit.turbine_ps_tbl[id].publish(key, val[id])
                end
            end

            if not every then rcs_disconn = true end

            unit.unit_ps.publish("U_" .. key, every)
        elseif key == "HeatingRateLow" or key == "WaterLevelLow" then
            -- split up array for all boilers
            local any = false
            for id = 1, #val do
                any = any or val[id]
                unit.boiler_ps_tbl[id].publish(key, val[id])
            end

            if key == "HeatingRateLow" and any then
                rcs_warn = true
            elseif key == "WaterLevelLow" and any then
                rcs_hazard = true
            end

            unit.unit_ps.publish("U_" .. key, any)
        elseif key == "SteamDumpOpen" or key == "TurbineOverSpeed" or key == "GeneratorTrip" or key == "TurbineTrip" then
            -- split up array for all turbines
            local any = false
            for id = 1, #val do
                any = any or val[id]
                unit.turbine_ps_tbl[id].publish(key, val[id])
            end

            if key == "GeneratorTrip" and any then
                rcs_warn = true
            elseif (key == "TurbineOverSpeed" or key == "TurbineTrip") and any then
                rcs_hazard = true
            end

            unit.unit_ps.publish("U_" .. key, any)
        else
            -- non-table fields
            unit.unit_ps.publish(key, val)
        end
    end

    local anc = unit.annunciator
    rcs_hazard = rcs_hazard or anc.RCPTrip
    rcs_warn = rcs_warn or anc.RCSFlowLow or anc.CoolantLevelLow or anc.RCSFault or anc.MaxWaterReturnFeed or
                anc.CoolantFeedMismatch or anc.BoilRateMismatch or anc.SteamFeedMismatch

    local rcs_status = 4
    if rcs_hazard then
        rcs_status = 2
    elseif rcs_warn then
        rcs_status = 3
    elseif rcs_disconn then
        rcs_status = 1
    end

    unit.unit_ps.publish("U_RCS", rcs_status)

    --#endregion

    --#region Reactor Data

    unit.reactor_data = data[7]

    local control_status = 1
    local reactor_status = 1
    local reactor_state = 1
    local rps_status = 1

    if unit.connected then
        -- update RPS status
        if unit.reactor_data.rps_tripped then
            control_status = 2

            if unit.reactor_data.rps_trip_cause == "manual" then
                reactor_state = 4   -- disabled
                rps_status = 3
            else
                reactor_state = 6   -- SCRAM
                rps_status = 2
            end
        else
            rps_status = 4
            reactor_state = 4
        end

        -- update reactor/control status
        if unit.reactor_data.mek_status.status then
            reactor_status = 4
            reactor_state = 5  -- running
            control_status = util.trinary(unit.annunciator.AutoControl, 4, 3)
        else
            if unit.reactor_data.no_reactor then
                reactor_status = 2
                reactor_state = 3   -- faulted
            elseif not unit.reactor_data.formed then
                reactor_status = 3
                reactor_state = 2   -- not formed
            elseif unit.reactor_data.rps_status.force_dis then
                reactor_status = 3
                reactor_state = 7   -- force disabled
            else
                reactor_status = 4
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
    end

    unit.unit_ps.publish("U_ControlStatus", control_status)
    unit.unit_ps.publish("U_ReactorStatus", reactor_status)
    unit.unit_ps.publish("U_ReactorStateStatus", reactor_state)
    unit.unit_ps.publish("U_RPS", rps_status)

    --#endregion

    --#region RTU Devices

    unit.boiler_data_tbl = data[8]

    for id = 1, #unit.boiler_data_tbl do
        local boiler = unit.boiler_data_tbl[id]
        local ps     = unit.boiler_ps_tbl[id]

        local boiler_status = 1
        local computed_status = 1

        if unit.rtu_hw.boilers[id].connected then
            if unit.rtu_hw.boilers[id].faulted then
                boiler_status = 3
                computed_status = 3
            elseif boiler.formed then
                boiler_status = 4

                if boiler.state.boil_rate > 0 then
                    computed_status = 5
                else
                    computed_status = 4
                end
            else
                boiler_status = 2
                computed_status = 2
            end

            _record_multiblock_status(unit.rtu_hw.boilers[id].faulted, boiler, ps)
        end

        ps.publish("BoilerStatus", boiler_status)
        ps.publish("BoilerStateStatus", computed_status)
    end

    unit.turbine_data_tbl = data[9]

    for id = 1, #unit.turbine_data_tbl do
        local turbine = unit.turbine_data_tbl[id]
        local ps      = unit.turbine_ps_tbl[id]

        local turbine_status = 1
        local computed_status = 1

        if unit.rtu_hw.turbines[id].connected then
            if unit.rtu_hw.turbines[id].faulted then
                turbine_status = 3
                computed_status = 3
            elseif turbine.formed then
                turbine_status = 4

                if turbine.tanks.energy_fill >= 0.99 then
                    computed_status = 6
                elseif turbine.state.flow_rate < 100 then
                    computed_status = 4
                else
                    computed_status = 5
                end
            else
                turbine_status = 2
                computed_status = 2
            end

            _record_multiblock_status(unit.rtu_hw.turbines[id].faulted, turbine, ps)
        end

        ps.publish("TurbineStatus", turbine_status)
        ps.publish("TurbineStateStatus", computed_status)
    end

    unit.tank_data_tbl = data[10]

    unit.last_rate_change_ms = data[11]
    unit.turbine_flow_stable = data[12]

    --#endregion

    --#region Status Information Display

    local ecam = {} -- aviation reference :)

    -- local function red(text) return { text = text, color = colors.red } end
    local function white(text) return { text = text, color = colors.white } end
    local function blue(text) return { text = text, color = colors.blue } end

    -- unit.reactor_data.rps_status = {
    --     high_dmg = false,
    --     high_temp = false,
    --     low_cool = false,
    --     ex_waste = false,
    --     ex_hcool = false,
    --     no_fuel = false,
    --     fault = false,
    --     timeout = false,
    --     manual = false,
    --     automatic = false,
    --     sys_fail = false,
    --     force_dis = false
    -- }

    -- if unit.reactor_data.rps_status then
    --     for k, v in pairs(unit.alarms) do
    --         unit.alarms[k] = ALARM_STATE.TRIPPED
    --     end
    -- end

    if tripped(unit.alarms[ALARM.ContainmentBreach]) then
        local items = { white("REACTOR MELTDOWN"), blue("DON HAZMAT SUIT") }
        table.insert(ecam, { color = colors.red, text = "CONTAINMENT BREACH", help = "ContainmentBreach", items = items })
    end

    if tripped(unit.alarms[ALARM.ContainmentRadiation]) then
        local items = {
            white("RADIATION DETECTED"),
            blue("DON HAZMAT SUIT"),
            blue("RESOLVE LEAK"),
            blue("AWAIT SAFE LEVELS")
        }

        table.insert(ecam, { color = colors.red, text = "RADIATION LEAK", help = "ContainmentRadiation", items = items })
    end

    if tripped(unit.alarms[ALARM.CriticalDamage]) then
        local items = { white("MELTDOWN IMMINENT"), blue("EVACUATE") }
        table.insert(ecam, { color = colors.red, text = "RCT DAMAGE CRITICAL", help = "CriticalDamage", items = items })
    end

    if tripped(unit.alarms[ALARM.ReactorLost]) then
        local items = { white("REACTOR OFF-LINE"), blue("CHECK PLC") }
        table.insert(ecam, { color = colors.red, text = "REACTOR CONN LOST", help = "ReactorLost", items = items })
    end

    if tripped(unit.alarms[ALARM.ReactorDamage]) then
        local items = { white("REACTOR DAMAGED"), blue("CHECK RCS"), blue("AWAIT DMG REDUCED") }
        table.insert(ecam, { color = colors.red, text = "REACTOR DAMAGE", help = "ReactorDamage", items = items })
    end

    if tripped(unit.alarms[ALARM.ReactorOverTemp]) then
        local items = { white("DAMAGING TEMP"), blue("CHECK RCS"), blue("AWAIT COOLDOWN") }
        table.insert(ecam, { color = colors.red, text = "REACTOR OVER TEMP", help = "ReactorOverTemp", items = items })
    end

    if tripped(unit.alarms[ALARM.ReactorHighTemp]) then
        local items = { white("OVER EXPECTED TEMP"), blue("CHECK RCS") }
        table.insert(ecam, { color = colors.yellow, text = "REACTOR HIGH TEMP", help = "ReactorHighTemp", items = items})
    end

    if tripped(unit.alarms[ALARM.ReactorWasteLeak]) then
        local items = { white("AT WASTE CAPACITY"), blue("CHECK WASTE OUTPUT"), blue("KEEP RCT DISABLED") }
        table.insert(ecam, { color = colors.red, text = "REACTOR WASTE LEAK", help = "ReactorWasteLeak", items = items})
    end

    if tripped(unit.alarms[ALARM.ReactorHighWaste]) then
        local items = { blue("CHECK WASTE OUTPUT") }
        table.insert(ecam, { color = colors.yellow, text = "REACTOR WASTE HIGH", help = "ReactorHighWaste", items = items})
    end

    if tripped(unit.alarms[ALARM.RPSTransient]) then
        local items = {}
        local stat = unit.reactor_data.rps_status

        -- for k, _ in pairs(stat) do stat[k] = true end

        local function insert(cond, key, text, color) if cond[key] then table.insert(items, { text = text, help = key, color = color }) end end

        table.insert(items, white("REACTOR SCRAMMED"))
        insert(stat, "high_dmg", "HIGH DAMAGE", colors.red)
        insert(stat, "high_temp", "HIGH TEMPERATURE", colors.red)
        insert(stat, "low_cool", "CRIT LOW COOLANT")
        insert(stat, "ex_waste", "EXCESS WASTE")
        insert(stat, "ex_hcool", "EXCESS HEATED COOL")
        insert(stat, "no_fuel", "NO FUEL")
        insert(stat, "fault", "HARDWARE FAULT")
        insert(stat, "timeout", "SUPERVISOR DISCONN")
        insert(stat, "manual", "MANUAL SCRAM", colors.white)
        insert(stat, "automatic", "AUTOMATIC SCRAM")
        insert(stat, "sys_fail", "NOT FORMED", colors.red)
        insert(stat, "force_dis", "FORCE DISABLED", colors.red)
        table.insert(items, blue("RESOLVE PROBLEM"))
        table.insert(items, blue("RESET RPS"))

        table.insert(ecam, { color = colors.yellow, text = "RPS TRANSIENT", help = "RPSTransient", items = items})
    end

    if tripped(unit.alarms[ALARM.RCSTransient]) then
        local items = {}
        local annunc = unit.annunciator

        -- for k, v in pairs(annunc) do
        --     if type(v) == "boolean" then annunc[k] = true end
        --     if type(v) == "table" then
        --         for a, _ in pairs(v) do
        --             v[a] = true
        --         end
        --     end
        -- end

        local function insert(cond, key, text, color)
            if cond == true or (type(cond) == "table" and cond[key]) then table.insert(items, { text = text, help = key, color = color }) end
        end

        table.insert(items, white("COOLANT PROBLEM"))

        insert(annunc, "RCPTrip", "RCP TRIP", colors.red)
        insert(annunc, "CoolantLevelLow", "LOW COOLANT")

        if unit.num_boilers == 0 then
            if (util.time_ms() - unit.last_rate_change_ms) > const.FLOW_STABILITY_DELAY_MS then
                insert(annunc, "BoilRateMismatch", "BOIL RATE MISMATCH")
            end

            if unit.turbine_flow_stable then
                insert(annunc, "RCSFlowLow", "RCS FLOW LOW")
                insert(annunc, "CoolantFeedMismatch", "COOL FEED MISMATCH")
                insert(annunc, "SteamFeedMismatch", "STM FEED MISMATCH")
            end
        else
            if (util.time_ms() - unit.last_rate_change_ms) > const.FLOW_STABILITY_DELAY_MS then
                insert(annunc, "RCSFlowLow", "RCS FLOW LOW")
                insert(annunc, "BoilRateMismatch", "BOIL RATE MISMATCH")
                insert(annunc, "CoolantFeedMismatch", "COOL FEED MISMATCH")
            end

            if unit.turbine_flow_stable then
                insert(annunc, "SteamFeedMismatch", "STM FEED MISMATCH")
            end
        end

        insert(annunc, "MaxWaterReturnFeed", "MAX WTR RTRN FEED")

        for k, v in ipairs(annunc.WaterLevelLow) do insert(v, "WaterLevelLow", "BOILER " .. k .. " WTR LOW", colors.red) end
        for k, v in ipairs(annunc.HeatingRateLow) do insert(v, "HeatingRateLow", "BOILER " .. k .. " HEAT RATE") end
        for k, v in ipairs(annunc.TurbineOverSpeed) do insert(v, "TurbineOverSpeed", "TURBINE " .. k .. " OVERSPD", colors.red) end
        for k, v in ipairs(annunc.GeneratorTrip) do insert(v, "GeneratorTrip", "TURBINE " .. k .. " GEN TRIP") end

        table.insert(items, blue("CHECK COOLING SYS"))

        table.insert(ecam, { color = colors.yellow, text = "RCS TRANSIENT", help = "RCSTransient", items = items})
    end

    if tripped(unit.alarms[ALARM.TurbineTrip]) then
        local items = {}

        for k, v in ipairs(unit.annunciator.TurbineTrip) do
            if v then table.insert(items, { text = "TURBINE " .. k .. " TRIP", help = "TurbineTrip" }) end
        end

        table.insert(items, blue("CHECK ENERGY OUT"))
        table.insert(ecam, { color = colors.red, text = "TURBINE TRIP", help = "TurbineTripAlarm", items = items})
    end

    if not (tripped(unit.alarms[ALARM.ReactorLost]) or unit.connected) then
        local items = { blue("CHECK PLC") }
        table.insert(ecam, { color = colors.yellow, text = "REACTOR OFF-LINE", items = items })
    end

    for k, v in ipairs(unit.annunciator.BoilerOnline) do
        if not v then
            local items = { blue("CHECK RTU") }
            table.insert(ecam, { color = colors.yellow, text = "BOILER " .. k .. " OFF-LINE", items = items})
        end
    end

    for k, v in ipairs(unit.annunciator.TurbineOnline) do
        if not v then
            local items = { blue("CHECK RTU") }
            table.insert(ecam, { color = colors.yellow, text = "TURBINE " .. k .. " OFF-LINE", items = items})
        end
    end

    -- if no alarms, put some basic status messages in
    if #ecam == 0 then
        table.insert(ecam, { color = colors.green, text = "REACTOR " .. util.trinary(unit.reactor_data.mek_status.status, "NOMINAL", "IDLE"), items = {}})

        local plural = util.trinary(unit.num_turbines > 1, "S", "")
        table.insert(ecam, { color = colors.green, text = "TURBINE" .. plural .. util.trinary(unit.turbine_flow_stable, " STABLE", " STABILIZING"), items = {}})
    end

    unit.unit_ps.publish("U_ECAM", textutils.serialize(ecam))

    --#endregion
end

-- get the IO controller database
function iocontrol.get_db() return io end

return iocontrol
