--
-- I/O Control for Pocket Integration with Supervisor & Coordinator
--

local psil    = require("scada-common.psil")
local types   = require("scada-common.types")
local util    = require("scada-common.util")

local iorx    = require("pocket.iorx")
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

    iocontrol.rx = iorx(io)

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
        get_fac = function () comms.api__get_facility() end,
        get_unit = function (unit) comms.api__get_unit(unit) end,
        get_ctrl = function () comms.api__get_control() end,
        get_proc = function () comms.api__get_process() end,
        get_waste = function () comms.api__get_waste() end,
        get_rad = function () comms.api__get_rad() end
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
        tank_list = conf.cooling.fac_tank_list,
        tank_conns = conf.cooling.fac_tank_conns,
        tank_fluid_types = conf.cooling.tank_fluid_types,
        all_sys_ok = false,
        rtu_count = 0,

        status_lines = { "", "" },

        auto_ready = false,
        auto_active = false,
        auto_ramping = false,
        auto_saturated = false,

        auto_scram = false,
        ---@type ascram_status
        ascram_status = {
            matrix_fault = false,
            matrix_fill = false,
            crit_alarm = false,
            radiation = false,
            gen_fault = false
        },

        ---@type WASTE_PRODUCT
        auto_current_waste_product = types.WASTE_PRODUCT.PLUTONIUM,
        auto_pu_fallback_active = false,
        auto_sps_disabled = false,
        waste_stats = { 0, 0, 0, 0, 0, 0 }, -- waste in, pu, po, po pellets, am, spent waste

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
        tank_data_tbl = {},      ---@type dynamicv_session_db[]

        rad_monitors = {}        ---@type { radiation: radiation_reading, raw: number }[]
    }

    -- create induction and SPS tables (currently only 1 of each is supported)
    table.insert(io.facility.induction_ps_tbl, psil.create())
    table.insert(io.facility.induction_data_tbl, {})
    table.insert(io.facility.sps_ps_tbl, psil.create())
    table.insert(io.facility.sps_data_tbl, {})

    -- create facility tank tables
    for i = 1, #io.facility.tank_list do
        if io.facility.tank_list[i] == 2 then
            table.insert(io.facility.tank_ps_tbl, psil.create())
            table.insert(io.facility.tank_data_tbl, {})
        end
    end

    -- create unit data structures
    io.units = {}   ---@type pioctl_unit[]
    for i = 1, conf.num_units do
        ---@class pioctl_unit
        local entry = {
            unit_id = i,
            connected = false,

            num_boilers = 0,
            num_turbines = 0,
            num_snas = 0,
            has_tank = conf.cooling.r_cool[i].TankConnection,

            status_lines = { "", "" },

            auto_ready = false,
            auto_degraded = false,

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
            waste_stats = { 0, 0, 0 },  -- plutonium, polonium, po pellets

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

---@diagnostic disable-next-line: missing-fields
            annunciator = {},       ---@type annunciator

            unit_ps = psil.create(),
            reactor_data = types.new_reactor_db(),

            boiler_ps_tbl = {},     ---@type psil[]
            boiler_data_tbl = {},   ---@type boilerv_session_db[]

            turbine_ps_tbl = {},    ---@type psil[]
            turbine_data_tbl = {},  ---@type turbinev_session_db[]

            tank_ps_tbl = {},       ---@type psil[]
            tank_data_tbl = {},     ---@type dynamicv_session_db[]

            rad_monitors = {}       ---@type { radiation: radiation_reading, raw: number }[]
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

-- get the IO controller database
function iocontrol.get_db() return io end

return iocontrol
