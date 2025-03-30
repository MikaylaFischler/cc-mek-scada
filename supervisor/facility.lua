local log        = require("scada-common.log")
local types      = require("scada-common.types")
local util       = require("scada-common.util")

local unit       = require("supervisor.unit")
local fac_update = require("supervisor.facility_update")

local rsctl      = require("supervisor.session.rsctl")
local svsessions = require("supervisor.session.svsessions")

local AUTO_GROUP    = types.AUTO_GROUP
local PROCESS       = types.PROCESS
local RTU_ID_FAIL   = types.RTU_ID_FAIL
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local WASTE         = types.WASTE_PRODUCT

---@enum AUTO_SCRAM
local AUTO_SCRAM = {
    NONE = 0,
    MATRIX_FAULT = 1,
    MATRIX_FILL = 2,
    CRIT_ALARM = 3,
    RADIATION = 4,
    GEN_FAULT = 5
}

---@enum START_STATUS
local START_STATUS = {
    OK = 0,
    NO_UNITS = 1,
    BLADE_MISMATCH = 2
}

---@enum RECOVERY_STATE
local RCV_STATE = {
    INACTIVE = 0,
    PRIMED = 1,
    RUNNING = 2,
    STOPPED = 3
}

local CHARGE_SCALER = 1000000   -- convert MFE to FE
local GEN_SCALER    = 1000      -- convert kFE to FE

---@class facility_management
local facility = {}

-- create a new facility management object
---@nodiscard
---@param config svr_config supervisor configuration
function facility.new(config)
    ---@class _facility_self
    local self = {
        units = {},     ---@type reactor_unit[]
        types = { AUTO_SCRAM = AUTO_SCRAM, START_STATUS = START_STATUS, RCV_STATE = RCV_STATE },
        status_text = { "START UP", "initializing..." },
        all_sys_ok = false,
        allow_testing = false,
        -- facility tanks
        ---@class sv_cooling_conf
        cooling_conf = {
            r_cool = config.CoolingConfig,
            fac_tank_mode = config.FacilityTankMode,
            fac_tank_defs = config.FacilityTankDefs,
            fac_tank_list = config.FacilityTankList,
            fac_tank_conns = config.FacilityTankConns,
            tank_fluid_types = config.TankFluidTypes,
            aux_coolant = config.AuxiliaryCoolant
        },
        -- rtus
        rtu_gw_conn_count = 0,
        rtu_list = {},  ---@type unit_session[][]
        redstone = {},  ---@type redstone_session[]
        induction = {}, ---@type imatrix_session[]
        sps = {},       ---@type sps_session[]
        tanks = {},     ---@type dynamicv_session[]
        envd = {},      ---@type envd_session[]
        -- redstone I/O control
        io_ctl = nil,   ---@type rs_controller
        -- process control
        recovery = RCV_STATE.INACTIVE,  ---@type RECOVERY_STATE
        recovery_boot_state = nil,      ---@type sv_boot_state|nil
        last_unit_states = {},          ---@type boolean[]
        units_ready = false,
        mode = PROCESS.INACTIVE,        ---@type PROCESS
        last_mode = PROCESS.INACTIVE,   ---@type PROCESS
        return_mode = PROCESS.INACTIVE, ---@type PROCESS
        mode_set = PROCESS.MAX_BURN,    ---@type PROCESS
        start_fail = START_STATUS.OK,   ---@type START_STATUS
        max_burn_combined = 0.0,        -- maximum burn rate to clamp at
        burn_target = 0.1,              -- burn rate target for aggregate burn mode
        charge_setpoint = 0,            -- FE charge target setpoint
        gen_rate_setpoint = 0,          -- FE/t charge rate target setpoint
        group_map = {},                 ---@type AUTO_GROUP[] units -> group IDs
        prio_defs = { {}, {}, {}, {} }, ---@type reactor_unit[][] priority definitions (each level is a table of units)
        at_max_burn = false,
        ascram = false,
        ascram_reason = AUTO_SCRAM.NONE,
        ---@class ascram_status
        ascram_status = {
            matrix_fault = false,
            matrix_fill = false,
            crit_alarm = false,
            radiation = false,
            gen_fault = false
        },
        -- closed loop control
        charge_conversion = 1.0,
        time_start = 0.0,
        initial_ramp = true,
        waiting_on_ramp = false,    -- waiting on auto ramping
        waiting_on_stable = false,  -- waiting on gen rate stabilization
        accumulator = 0.0,
        saturated = false,
        last_update = 0,
        last_error = 0.0,
        last_time = 0.0,
        -- waste processing
        waste_product = WASTE.PLUTONIUM,         ---@type WASTE_PRODUCT
        current_waste_product = WASTE.PLUTONIUM, ---@type WASTE_PRODUCT
        pu_fallback = false,
        sps_low_power = false,
        disabled_sps = false,
        -- alarm tones
        tone_states = {},       ---@type { [TONE]: boolean }
        test_tone_set = false,
        test_tone_reset = false,
        test_tone_states = {},  ---@type { [TONE]: boolean }
        test_alarm_states = {}, ---@type { [ALARM]: boolean }
        -- statistics
        im_stat_init = false,
        avg_charge = util.mov_avg(3),  -- 3 seconds
        avg_inflow = util.mov_avg(6),  -- 3 seconds
        avg_outflow = util.mov_avg(6), -- 3 seconds
        -- induction matrix charge delta stats
        avg_net = util.mov_avg(60),    -- 60 seconds
        imtx_last_capacity = 0,
        imtx_last_charge = 0,
        imtx_last_charge_t = 0,
        -- track faulted induction matrix update times to reject
        imtx_faulted_times = { 0, 0, 0 }
    }

    --#region SETUP

    -- provide self to facility update functions
    local f_update = fac_update(self)

    -- create units
    for i = 1, config.UnitCount do
        table.insert(self.units, unit.new(i, self.cooling_conf.r_cool[i].BoilerCount, self.cooling_conf.r_cool[i].TurbineCount, config.ExtChargeIdling, self.cooling_conf.aux_coolant[i]))
        table.insert(self.group_map, AUTO_GROUP.MANUAL)
        table.insert(self.last_unit_states, false)
    end

    -- list for RTU session management
    self.rtu_list = { self.redstone, self.induction, self.sps, self.tanks, self.envd }

    -- init redstone RTU I/O controller
    self.io_ctl = rsctl.new(self.redstone)

    -- fill blank alarm/tone states
    for _ = 1, 12 do table.insert(self.test_alarm_states, false) end
    for _ = 1, 8 do
        table.insert(self.tone_states, false)
        table.insert(self.test_tone_states, false)
    end

    -- init next boot state
    settings.set("LastProcessState", PROCESS.INACTIVE)
    settings.set("LastUnitStates", self.last_unit_states)
    if not settings.save("/supervisor.settings") then
        log.warning("FAC: failed to save initial control state into supervisor settings file")
    end

    --#endregion

    -- PRIVATE FUNCTIONS --

    -- check an auto process control configuration and save it if its valid (does not start the process)
    ---@param auto_cfg start_auto_config configuration
    ---@return boolean ready, number[] unit_limits
    local function _auto_check_and_save(auto_cfg)
        local ready = false

        -- load up current limits
        local limits = {}
        for i = 1, config.UnitCount do
            limits[i] = self.units[i].get_control_inf().lim_br100 * 100
        end

        -- only allow changes if not running
        if self.mode == PROCESS.INACTIVE then
            if (type(auto_cfg.mode) == "number") and (auto_cfg.mode > PROCESS.INACTIVE) and (auto_cfg.mode <= PROCESS.GEN_RATE) then
                self.mode_set = auto_cfg.mode
            end

            if (type(auto_cfg.burn_target) == "number") and auto_cfg.burn_target >= 0.1 then
                self.burn_target = auto_cfg.burn_target
            end

            if (type(auto_cfg.charge_target) == "number") and auto_cfg.charge_target >= 0 then
                self.charge_setpoint = auto_cfg.charge_target * CHARGE_SCALER
            end

            if (type(auto_cfg.gen_target) == "number") and auto_cfg.gen_target >= 0 then
                self.gen_rate_setpoint = auto_cfg.gen_target * GEN_SCALER
            end

            if (type(auto_cfg.limits) == "table") and (#auto_cfg.limits == config.UnitCount) then
                for i = 1, config.UnitCount do
                    local limit = auto_cfg.limits[i]

                    if (type(limit) == "number") and (limit >= 0.1) then
                        limits[i] = limit
                        self.units[i].set_burn_limit(limit)
                    end
                end
            end

            ready = self.mode_set > 0

            if ((self.mode_set == PROCESS.CHARGE) and (self.charge_setpoint <= 0)) or
               ((self.mode_set == PROCESS.GEN_RATE) and (self.gen_rate_setpoint <= 0)) or
               ((self.mode_set == PROCESS.BURN_RATE) and (self.burn_target < 0.1)) then
                ready = false
            end
        end

        return ready, limits
    end

    -- PUBLIC FUNCTIONS --

    ---@class facility
    local public = {}

    --#region Add/Link Devices

    -- link a redstone RTU session
    ---@param rs_unit unit_session
    function public.add_redstone(rs_unit) table.insert(self.redstone, rs_unit) end

    -- link an induction matrix RTU session
    ---@param imatrix unit_session
    ---@return boolean linked induction matrix accepted (max 1)
    function public.add_imatrix(imatrix)
        local fail_code, fail_str = svsessions.check_rtu_id(imatrix, self.induction, 1)
        local ok = fail_code == RTU_ID_FAIL.OK

        if ok then
            table.insert(self.induction, imatrix)
            log.debug(util.c("FAC: linked induction matrix [", imatrix.get_unit_id(), "@", imatrix.get_session_id(), "]"))
        else
            log.warning(util.c("FAC: rejected induction matrix linking due to failure code ", fail_code, " (", fail_str, ")"))
        end

        return ok
    end

    -- link an SPS RTU session
    ---@param sps unit_session
    ---@return boolean linked SPS accepted (max 1)
    function public.add_sps(sps)
        local fail_code, fail_str = svsessions.check_rtu_id(sps, self.sps, 1)
        local ok = fail_code == RTU_ID_FAIL.OK

        if ok then
            table.insert(self.sps, sps)
            log.debug(util.c("FAC: linked SPS [", sps.get_unit_id(), "@", sps.get_session_id(), "]"))
        else
            log.warning(util.c("FAC: rejected SPS linking due to failure code ", fail_code, " (", fail_str, ")"))
        end

        return ok
    end

    -- link a dynamic tank RTU session
    ---@param dynamic_tank unit_session
    function public.add_tank(dynamic_tank)
        local fail_code, fail_str = svsessions.check_rtu_id(dynamic_tank, self.tanks, #self.cooling_conf.fac_tank_list)
        local ok = fail_code == RTU_ID_FAIL.OK

        if ok then
            table.insert(self.tanks, dynamic_tank)
            log.debug(util.c("FAC: linked dynamic tank #", dynamic_tank.get_device_idx(), " [", dynamic_tank.get_unit_id(), "@", dynamic_tank.get_session_id(), "]"))
        else
            log.warning(util.c("FAC: rejected dynamic tank linking due to failure code ", fail_code, " (", fail_str, ")"))
        end

        return ok
    end

    -- link an environment detector RTU session
    ---@param envd unit_session
    ---@return boolean linked environment detector accepted
    function public.add_envd(envd)
        local fail_code, fail_str = svsessions.check_rtu_id(envd, self.envd, 99)
        local ok = fail_code == RTU_ID_FAIL.OK

        if ok then
            table.insert(self.envd, envd)
            log.debug(util.c("FAC: linked environment detector #", envd.get_device_idx(), " [", envd.get_unit_id(), "@", envd.get_session_id(), "]"))
        else
            log.warning(util.c("FAC: rejected environment detector linking due to failure code ", fail_code, " (", fail_str, ")"))
        end

        return ok
    end

    -- purge devices associated with the given RTU session ID
    ---@param session integer RTU session ID
    function public.purge_rtu_devices(session)
        for _, v in pairs(self.rtu_list) do util.filter_table(v, function (s) return s.get_session_id() ~= session end) end
    end

    --#endregion

    --#region Update

    -- update (iterate) the facility management
    function public.update()
        -- run reboot recovery routine if needed
        f_update.boot_recovery()

        -- run process control and evaluate automatic SCRAM
        f_update.pre_auto()
        f_update.auto_control(config.ExtChargeIdling)
        f_update.auto_safety()
        f_update.post_auto()

        -- handle redstone I/O
        f_update.redstone(public.ack_all)

        -- unit tasks
        f_update.unit_mgmt()

        -- update alarm tones
        f_update.alarm_audio()
    end

    -- call the update function of all units in the facility<br>
    -- additionally sets the requested auto waste mode if applicable
    function public.update_units()
        for i = 1, #self.units do
            local u = self.units[i]
            u.auto_set_waste(self.current_waste_product)
            u.update()
        end
    end

    --#endregion

    --#region Startup Recovery

    -- on exit, use this to clear the boot state so we don't resume when exiting cleanly
    function public.clear_boot_state()
        settings.unset("LastProcessState")
        settings.unset("LastUnitStates")

        if not settings.save("/supervisor.settings") then
            log.warning("facility.clear_boot_state(): failed to save supervisor settings file")
        else
            log.debug("FAC: cleared boot state on exit")
        end
    end

    -- initialize facility resume boot recovery
    ---@param state sv_boot_state|nil
    function public.boot_recovery_init(state)
        if self.recovery == RCV_STATE.INACTIVE and state then
            self.recovery_boot_state = state
            self.recovery = RCV_STATE.PRIMED
            log.info("FAC: startup resume ready")
        end
    end

    -- attempt facility resume boot recovery
    ---@param auto_cfg start_auto_config configuration
    function public.boot_recovery_start(auto_cfg)
        if self.recovery == RCV_STATE.PRIMED then
            self.recovery = util.trinary(_auto_check_and_save(auto_cfg), RCV_STATE.RUNNING, RCV_STATE.STOPPED)
            log.info(util.c("FAC: startup resume ", util.trinary(self.recovery == RCV_STATE.RUNNING, "started", "failed")))
        else self.recovery = RCV_STATE.STOPPED end
    end

    -- used on certain coordinator commands to end reboot recovery (remain in current operational state)
    function public.cancel_recovery()
        if self.recovery == RCV_STATE.RUNNING then
            self.recovery = RCV_STATE.STOPPED
            self.recovery_boot_state = nil
            log.info("FAC: process startup resume cancelled by user operation")
        end
    end

    --#endregion

    --#region Commands

    -- SCRAM all reactor units
    function public.scram_all()
        for i = 1, #self.units do
            self.units[i].scram()
        end
    end

    -- ack all alarms on all reactor units
    function public.ack_all()
        for i = 1, #self.units do
            self.units[i].ack_all()
        end
    end

    -- check automatic control mode
    function public.auto_is_active() return self.mode ~= PROCESS.INACTIVE end

    -- stop auto control
    function public.auto_stop() self.mode = PROCESS.INACTIVE end

    -- set automatic control configuration and start the process
    ---@param auto_cfg start_auto_config configuration
    ---@return table response ready state (successfully started) and current configuration (after updating)
    function public.auto_start(auto_cfg)
        local ready, limits = _auto_check_and_save(auto_cfg)

        if ready and self.units_ready then
            self.mode = self.mode_set
        end

        log.debug(util.c("FAC: process start ", util.trinary(ready, "accepted", "rejected")))

        return {
            ready,
            self.mode_set,
            self.burn_target,
            self.charge_setpoint / CHARGE_SCALER,
            self.gen_rate_setpoint / GEN_SCALER,
            limits
        }
    end

    --#endregion

    --#region Settings

    -- set the automatic control group of a unit
    ---@param unit_id integer unit ID
    ---@param group AUTO_GROUP group ID or 0 for independent
    function public.set_group(unit_id, group)
        if (group >= AUTO_GROUP.MANUAL and group <= AUTO_GROUP.BACKUP) and (unit_id > 0 and unit_id <= config.UnitCount) and self.mode == PROCESS.INACTIVE then
            -- remove from old group if previously assigned
            local old_group = self.group_map[unit_id]
            if old_group ~= AUTO_GROUP.MANUAL then
                util.filter_table(self.prio_defs[old_group], function (u) return u.get_id() ~= unit_id end)
            end

            self.group_map[unit_id] = group

            -- add to group if not independent
            if group > AUTO_GROUP.MANUAL then
                table.insert(self.prio_defs[group], self.units[unit_id])
            end
        end
    end

    -- get the automatic control group of a unit
    ---@param unit_id integer unit ID
    ---@nodiscard
    function public.get_group(unit_id) return self.group_map[unit_id] end

    -- set waste production
    ---@param product WASTE_PRODUCT target product
    ---@return WASTE_PRODUCT product newly set value, if valid
    function public.set_waste_product(product)
        if product == WASTE.PLUTONIUM or product == WASTE.POLONIUM or product == WASTE.ANTI_MATTER then
            self.waste_product = product
        end

        return self.waste_product
    end

    -- enable/disable plutonium fallback
    ---@param enabled boolean requested state
    ---@return boolean enabled newly set value
    function public.set_pu_fallback(enabled)
        self.pu_fallback = enabled == true
        return self.pu_fallback
    end

    -- enable/disable SPS at low power
    ---@param enabled boolean requested state
    ---@return boolean enabled newly set value
    function public.set_sps_low_power(enabled)
        self.sps_low_power = enabled == true
        return self.sps_low_power
    end

    --#endregion

    --#region Diagnostic Testing

    -- attempt to set a test tone state
    ---@param id TONE|0 tone ID or 0 to disable all
    ---@param state boolean state
    ---@return boolean allow_testing, { [TONE]: boolean } test_tone_states
    function public.diag_set_test_tone(id, state)
        if self.allow_testing then
            self.test_tone_set = true
            self.test_tone_reset = false

            if id == 0 then
                for i = 1, #self.test_tone_states do self.test_tone_states[i] = false end
            else
                self.test_tone_states[id] = state
            end
        end

        return self.allow_testing, self.test_tone_states
    end

    -- attempt to set a test alarm state
    ---@param id ALARM|0 alarm ID or 0 to disable all
    ---@param state boolean state
    ---@return boolean allow_testing, { [ALARM]: boolean } test_alarm_states
    function public.diag_set_test_alarm(id, state)
        if self.allow_testing then
            self.test_tone_set = true
            self.test_tone_reset = false

            if id == 0 then
                for i = 1, #self.test_alarm_states do self.test_alarm_states[i] = false end
            else
                self.test_alarm_states[id] = state
            end
        end

        return self.allow_testing, self.test_alarm_states
    end

    --#endregion

    --#region Read States/Properties

    -- get current alarm tone on/off states
    ---@nodiscard
    function public.get_alarm_tones() return self.tone_states end

    -- get build properties of all facility devices
    ---@nodiscard
    ---@param type RTU_UNIT_TYPE? type or nil to include only a particular unit type, or to include all if nil
    function public.get_build(type)
        local all = type == nil
        local build = {}

        if all or type == RTU_UNIT_TYPE.IMATRIX then
            build.induction = {}
            for i = 1, #self.induction do
                local matrix = self.induction[i]
                build.induction[i] = { matrix.get_db().formed, matrix.get_db().build }
            end
        end

        if all or type == RTU_UNIT_TYPE.SPS then
            build.sps = {}
            for i = 1, #self.sps do
                local sps = self.sps[i]
                build.sps[i] = { sps.get_db().formed, sps.get_db().build }
            end
        end

        if all or type == RTU_UNIT_TYPE.DYNAMIC_VALVE then
            build.tanks = {}
            for i = 1, #self.tanks do
                local tank = self.tanks[i]
                build.tanks[tank.get_device_idx()] = { tank.get_db().formed, tank.get_db().build }
            end
        end

        return build
    end

    -- get automatic process control status
    ---@nodiscard
    function public.get_control_status()
        local astat = self.ascram_status
        return {
            self.all_sys_ok,
            self.units_ready,
            self.mode,
            self.waiting_on_ramp or self.waiting_on_stable,
            self.at_max_burn or self.saturated,
            self.ascram,
            astat.matrix_fault,
            astat.matrix_fill,
            astat.crit_alarm,
            astat.radiation,
            astat.gen_fault or self.mode == PROCESS.GEN_RATE_FAULT_IDLE,
            self.status_text[1],
            self.status_text[2],
            self.group_map,
            self.current_waste_product,
            self.pu_fallback and (self.current_waste_product == WASTE.PLUTONIUM) and (self.waste_product ~= WASTE.PLUTONIUM),
            self.disabled_sps
        }
    end

    -- check which RTUs are connected
    ---@nodiscard
    function public.check_rtu_conns()
        local conns = {}

        conns.induction = #self.induction > 0
        conns.sps = #self.sps > 0

        conns.tanks = {}
        for i = 1, #self.tanks do
            conns.tanks[self.tanks[i].get_device_idx()] = true
        end

        return conns
    end

    -- get RTU statuses
    ---@nodiscard
    function public.get_rtu_statuses()
        local status = {}

        -- total count of all connected RTUs in the facility
        status.count = self.rtu_gw_conn_count

        -- power averages from induction matricies
        status.power = {
            self.avg_charge.compute(),
            self.avg_inflow.compute(),
            self.avg_outflow.compute(),
            0
        }

        -- status of induction matricies (including tanks)
        status.induction = {}
        for i = 1, #self.induction do
            local matrix = self.induction[i]
            local db = matrix.get_db()

            status.induction[i] = { matrix.is_faulted(), db.formed, db.state, db.tanks }

            local fe_per_ms = self.avg_net.compute()
            local remaining = util.joules_to_fe_rf(util.trinary(fe_per_ms >= 0, db.tanks.energy_need, db.tanks.energy))
            status.power[4] = remaining / fe_per_ms
        end

        -- status of sps
        status.sps = {}
        for i = 1, #self.sps do
            local sps = self.sps[i]
            local db = sps.get_db()
            status.sps[i] = { sps.is_faulted(), db.formed, db.state, db.tanks }
        end

        -- status of dynamic tanks
        status.tanks = {}
        for i = 1, #self.tanks do
            local tank = self.tanks[i]
            local db = tank.get_db()
            status.tanks[tank.get_device_idx()] = { tank.is_faulted(), db.formed, db.state, db.tanks }
        end

        -- radiation monitors (environment detectors)
        status.envds = {}
        for i = 1, #self.envd do
            local envd = self.envd[i]
            local db = envd.get_db()
            status.envds[envd.get_device_idx()] = { envd.is_faulted(), db.radiation, db.radiation_raw }
        end

        return status
    end

    --#endregion

    -- supervisor sessions reporting the list of active RTU gateway sessions
    ---@param sessions rtu_session_struct[] session list of all connected RTU gateways
    function public.report_rtu_gateways(sessions) self.rtu_gw_conn_count = #sessions end

    -- get the facility cooling configuration
    function public.get_cooling_conf() return self.cooling_conf end

    -- get the units in this facility
    ---@nodiscard
    function public.get_units() return self.units end

    return public
end

return facility
