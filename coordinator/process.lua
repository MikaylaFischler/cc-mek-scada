--
-- Process Control Management
--

local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local types = require("scada-common.types")
local util  = require("scada-common.util")

local F_CMD = comms.FAC_COMMAND
local U_CMD = comms.UNIT_COMMAND

local PROCESS = types.PROCESS
local PRODUCT = types.WASTE_PRODUCT

local REQUEST_TIMEOUT_MS = 5000

---@class process_controller
local process = {}

local pctl = {
    io = nil,       ---@type ioctl
    comms = nil,    ---@type coord_comms
    ---@class sys_control_states
    control_states = {
        ---@class sys_auto_config
        process = {
            mode = PROCESS.INACTIVE,
            burn_target = 0.0,
            charge_target = 0.0,
            gen_target = 0.0,
            limits = {},
            waste_product = PRODUCT.PLUTONIUM,
            pu_fallback = false,
            sps_low_power = false
        },
        waste_modes = {},
        priority_groups = {}
    },
    next_handle = 0,
    commands = { unit = {}, fac = {} }
}

for _, v in pairs(U_CMD) do pctl.commands.unit[v] = { active = false, timeout = 0, requestors = {} } end
for _, v in pairs(F_CMD) do pctl.commands.fac[v]  = { active = false, timeout = 0, requestors = {} } end

-- write auto process control to config file
local function _write_auto_config()
    -- save config
    settings.set("ControlStates", pctl.control_states)
    local saved = settings.save("/coordinator.settings")
    if not saved then
        log.warning("process._write_auto_config(): failed to save coordinator settings file")
    end

    return saved
end

-- initialize the process controller
---@param iocontrol ioctl iocontrl system
---@param coord_comms coord_comms coordinator communications
function process.init(iocontrol, coord_comms)
    pctl.io = iocontrol
    pctl.comms = coord_comms

    local ctl_proc = pctl.control_states.process

    for i = 1, pctl.io.facility.num_units do
        ctl_proc.limits[i] = 0.1
    end

    local ctrl_states = settings.get("ControlStates", {})
    local config = ctrl_states.process  ---@type sys_auto_config

    -- facility auto control configuration
    if type(config) == "table" then
        ctl_proc.mode = config.mode
        ctl_proc.burn_target = config.burn_target
        ctl_proc.charge_target = config.charge_target
        ctl_proc.gen_target = config.gen_target
        ctl_proc.limits = config.limits
        ctl_proc.waste_product = config.waste_product
        ctl_proc.pu_fallback = config.pu_fallback
        ctl_proc.sps_low_power = config.sps_low_power

        pctl.io.facility.ps.publish("process_mode", ctl_proc.mode)
        pctl.io.facility.ps.publish("process_burn_target", ctl_proc.burn_target)
        pctl.io.facility.ps.publish("process_charge_target", pctl.io.energy_convert_from_fe(ctl_proc.charge_target))
        pctl.io.facility.ps.publish("process_gen_target", pctl.io.energy_convert_from_fe(ctl_proc.gen_target))
        pctl.io.facility.ps.publish("process_waste_product", ctl_proc.waste_product)
        pctl.io.facility.ps.publish("process_pu_fallback", ctl_proc.pu_fallback)
        pctl.io.facility.ps.publish("process_sps_low_power", ctl_proc.sps_low_power)

        for id = 1, math.min(#ctl_proc.limits, pctl.io.facility.num_units) do
            local unit = pctl.io.units[id]   ---@type ioctl_unit
            unit.unit_ps.publish("burn_limit", ctl_proc.limits[id])
        end

        log.info("PROCESS: loaded auto control settings")

        -- notify supervisor of auto waste config
        pctl.comms.send_fac_command(F_CMD.SET_WASTE_MODE, ctl_proc.waste_product)
        pctl.comms.send_fac_command(F_CMD.SET_PU_FB, ctl_proc.pu_fallback)
        pctl.comms.send_fac_command(F_CMD.SET_SPS_LP, ctl_proc.sps_low_power)
    end

    -- unit waste states
    local waste_modes = ctrl_states.waste_modes  ---@type table|nil
    if type(waste_modes) == "table" then
        for id, mode in pairs(waste_modes) do
            pctl.control_states.waste_modes[id] = mode
            pctl.comms.send_unit_command(U_CMD.SET_WASTE, id, mode)
        end

        log.info("PROCESS: loaded unit waste mode settings")
    end

    -- unit priority groups
    local prio_groups = ctrl_states.priority_groups ---@type table|nil
    if type(prio_groups) == "table" then
        for id, group in pairs(prio_groups) do
            pctl.control_states.priority_groups[id] = group
            pctl.comms.send_unit_command(U_CMD.SET_GROUP, id, group)
        end

        log.info("PROCESS: loaded priority groups settings")
    end
end

-- create a handle to process control for usage of commands that get acknowledgements
function process.create_handle()
    local self = {
        id = pctl.next_handle
    }

    pctl.next_handle = pctl.next_handle + 1

    ---@class process_handle
    local handle = {}

    local function request(cmd)
        local new = not cmd.active

        if new then
            cmd.active = true
            cmd.timeout = util.time_ms() + REQUEST_TIMEOUT_MS
        end

        cmd.requstors[self.id] = true

        return new
    end

    local function u_request(cmd_id) return request(pctl.commands.unit[cmd_id]) end
    local function f_request(cmd_id) return request(pctl.commands.fac[cmd_id]) end

    --#region Facility Commands

    -- facility SCRAM command
    function handle.fac_scram()
        if f_request(F_CMD.SCRAM_ALL) then
            pctl.comms.send_fac_command(F_CMD.SCRAM_ALL)
            log.debug("PROCESS: FAC SCRAM ALL")
        end
    end

    -- facility alarm acknowledge command
    function handle.fac_ack_alarms()
        if f_request(F_CMD.ACK_ALL_ALARMS) then
            pctl.comms.send_fac_command(F_CMD.ACK_ALL_ALARMS)
            log.debug("PROCESS: FAC ACK ALL ALARMS")
        end
    end

    --#endregion

    --#region Unit Commands

    -- start a reactor
    ---@param id integer unit ID
    function handle.start(id)
        if u_request(U_CMD.START) then
            pctl.io.units[id].control_state = true
            pctl.comms.send_unit_command(U_CMD.START, id)
            log.debug(util.c("PROCESS: UNIT[", id, "] START"))
        end
    end

    -- SCRAM reactor
    ---@param id integer unit ID
    function handle.scram(id)
        if u_request(U_CMD.SCRAM) then
            pctl.io.units[id].control_state = false
            pctl.comms.send_unit_command(U_CMD.SCRAM, id)
            log.debug(util.c("PROCESS: UNIT[", id, "] SCRAM"))
        end
    end

    -- reset reactor protection system
    ---@param id integer unit ID
    function handle.reset_rps(id)
        if u_request(U_CMD.RESET_RPS) then
            pctl.comms.send_unit_command(U_CMD.RESET_RPS, id)
            log.debug(util.c("PROCESS: UNIT[", id, "] RESET RPS"))
        end
    end

    -- acknowledge all alarms
    ---@param id integer unit ID
    function handle.ack_all_alarms(id)
        if u_request(U_CMD.ACK_ALL_ALARMS) then
            pctl.comms.send_unit_command(U_CMD.ACK_ALL_ALARMS, id)
            log.debug(util.c("PROCESS: UNIT[", id, "] ACK ALL ALARMS"))
        end
    end

    --#endregion

    return handle
end

function process.clear_timed_out()
end

function process.handle_ack()
end

--#region One-Way Commands (no acknowledgements)

-- set burn rate
---@param id integer unit ID
---@param rate number burn rate
function process.set_rate(id, rate)
    pctl.comms.send_unit_command(U_CMD.SET_BURN, id, rate)
    log.debug(util.c("PROCESS: UNIT[", id, "] SET BURN ", rate))
end

-- set waste mode
---@param id integer unit ID
---@param mode integer waste mode
function process.set_unit_waste(id, mode)
    -- publish so that if it fails then it gets reset
    pctl.io.units[id].unit_ps.publish("U_WasteMode", mode)

    pctl.comms.send_unit_command(U_CMD.SET_WASTE, id, mode)
    log.debug(util.c("PROCESS: UNIT[", id, "] SET WASTE ", mode))

    pctl.control_states.waste_modes[id] = mode
    settings.set("ControlStates", pctl.control_states)

    if not settings.save("/coordinator.settings") then
        log.error("process.set_unit_waste(): failed to save coordinator settings file")
    end
end

-- acknowledge an alarm
---@param id integer unit ID
---@param alarm integer alarm ID
function process.ack_alarm(id, alarm)
    pctl.comms.send_unit_command(U_CMD.ACK_ALARM, id, alarm)
    log.debug(util.c("PROCESS: UNIT[", id, "] ACK ALARM ", alarm))
end

-- reset an alarm
---@param id integer unit ID
---@param alarm integer alarm ID
function process.reset_alarm(id, alarm)
    pctl.comms.send_unit_command(U_CMD.RESET_ALARM, id, alarm)
    log.debug(util.c("PROCESS: UNIT[", id, "] RESET ALARM ", alarm))
end

-- assign a unit to a group
---@param unit_id integer unit ID
---@param group_id integer|0 group ID or 0 for independent
function process.set_group(unit_id, group_id)
    pctl.comms.send_unit_command(U_CMD.SET_GROUP, unit_id, group_id)
    log.debug(util.c("PROCESS: UNIT[", unit_id, "] SET GROUP ", group_id))

    pctl.control_states.priority_groups[unit_id] = group_id
    settings.set("ControlStates", pctl.control_states)

    if not settings.save("/coordinator.settings") then
        log.error("process.set_group(): failed to save coordinator settings file")
    end
end

--#endregion

--------------------------
-- AUTO PROCESS CONTROL --
--------------------------

-- start automatic process control
function process.start_auto()
    pctl.comms.send_auto_start(pctl.control_states.process)
    log.debug("PROCESS: START AUTO CTL")
end

-- stop automatic process control
function process.stop_auto()
    pctl.comms.send_fac_command(F_CMD.STOP)
    log.debug("PROCESS: STOP AUTO CTL")
end

-- set automatic process control waste mode
---@param product WASTE_PRODUCT waste product for auto control
function process.set_process_waste(product)
    pctl.comms.send_fac_command(F_CMD.SET_WASTE_MODE, product)

    log.debug(util.c("PROCESS: SET WASTE ", product))

    -- update config table and save
    pctl.control_states.process.waste_product = product
    _write_auto_config()
end

-- set automatic process control plutonium fallback
---@param enabled boolean whether to enable plutonium fallback
function process.set_pu_fallback(enabled)
    pctl.comms.send_fac_command(F_CMD.SET_PU_FB, enabled)

    log.debug(util.c("PROCESS: SET PU FALLBACK ", enabled))

    -- update config table and save
    pctl.control_states.process.pu_fallback = enabled
    _write_auto_config()
end

-- set automatic process control SPS usage at low power
---@param enabled boolean whether to enable SPS usage at low power
function process.set_sps_low_power(enabled)
    pctl.comms.send_fac_command(F_CMD.SET_SPS_LP, enabled)

    log.debug(util.c("PROCESS: SET SPS LOW POWER ", enabled))

    -- update config table and save
    pctl.control_states.process.sps_low_power = enabled
    _write_auto_config()
end

-- save process control settings
---@param mode PROCESS control mode
---@param burn_target number burn rate target
---@param charge_target number charge target
---@param gen_target number generation rate target
---@param limits table unit burn rate limits
function process.save(mode, burn_target, charge_target, gen_target, limits)
    log.debug("PROCESS: SAVE")

    -- update config table
    local ctl_proc = pctl.control_states.process
    ctl_proc.mode = mode
    ctl_proc.burn_target = burn_target
    ctl_proc.charge_target = charge_target
    ctl_proc.gen_target = gen_target
    ctl_proc.limits = limits

    -- save config
    pctl.io.facility.save_cfg_ack(_write_auto_config())
end

-- handle a start command acknowledgement
---@param response table ack and configuration reply
function process.start_ack_handle(response)
    local ack = response[1]

    local ctl_proc = pctl.control_states.process
    ctl_proc.mode = response[2]
    ctl_proc.burn_target = response[3]
    ctl_proc.charge_target = response[4]
    ctl_proc.gen_target = response[5]

    for i = 1, math.min(#response[6], pctl.io.facility.num_units) do
        ctl_proc.limits[i] = response[6][i]

        local unit = pctl.io.units[i]   ---@type ioctl_unit
        unit.unit_ps.publish("burn_limit", ctl_proc.limits[i])
    end

    pctl.io.facility.ps.publish("process_mode", ctl_proc.mode)
    pctl.io.facility.ps.publish("process_burn_target", ctl_proc.burn_target)
    pctl.io.facility.ps.publish("process_charge_target", pctl.io.energy_convert_from_fe(ctl_proc.charge_target))
    pctl.io.facility.ps.publish("process_gen_target", pctl.io.energy_convert_from_fe(ctl_proc.gen_target))

    pctl.io.facility.start_ack(ack)
end

-- record waste product state after attempting to change it
---@param response WASTE_PRODUCT supervisor waste product state
function process.waste_ack_handle(response)
    pctl.control_states.process.waste_product = response
    pctl.io.facility.ps.publish("process_waste_product", response)
end

-- record plutonium fallback state after attempting to change it
---@param response boolean supervisor plutonium fallback state
function process.pu_fb_ack_handle(response)
    pctl.control_states.process.pu_fallback = response
    pctl.io.facility.ps.publish("process_pu_fallback", response)
end

return process
