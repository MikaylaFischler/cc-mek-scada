--
-- Process Control Management
--

local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local types = require("scada-common.types")
local util  = require("scada-common.util")

local FAC_COMMAND = comms.FAC_COMMAND
local UNIT_COMMAND = comms.UNIT_COMMAND

local PROCESS = types.PROCESS
local PRODUCT = types.WASTE_PRODUCT

---@class process_controller
local process = {}

local self = {
    io = nil,       ---@type ioctl
    comms = nil,    ---@type coord_comms
    ---@class coord_control_states
    control_states = {
        ---@class coord_auto_config
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
    }
}

--------------------------
-- UNIT COMMAND CONTROL --
--------------------------

-- initialize the process controller
---@param iocontrol ioctl iocontrl system
---@param coord_comms coord_comms coordinator communications
function process.init(iocontrol, coord_comms)
    self.io = iocontrol
    self.comms = coord_comms

    local ctl_proc = self.control_states.process

    for i = 1, self.io.facility.num_units do
        ctl_proc.limits[i] = 0.1
    end

    local ctrl_states = settings.get("ControlStates", {})
    local config = ctrl_states.process  ---@type coord_auto_config

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

        self.io.facility.ps.publish("process_mode", ctl_proc.mode)
        self.io.facility.ps.publish("process_burn_target", ctl_proc.burn_target)
        self.io.facility.ps.publish("process_charge_target", ctl_proc.charge_target)
        self.io.facility.ps.publish("process_gen_target", ctl_proc.gen_target)
        self.io.facility.ps.publish("process_waste_product", ctl_proc.waste_product)
        self.io.facility.ps.publish("process_pu_fallback", ctl_proc.pu_fallback)
        self.io.facility.ps.publish("process_sps_low_power", ctl_proc.sps_low_power)

        for id = 1, math.min(#ctl_proc.limits, self.io.facility.num_units) do
            local unit = self.io.units[id]   ---@type ioctl_unit
            unit.unit_ps.publish("burn_limit", ctl_proc.limits[id])
        end

        log.info("PROCESS: loaded auto control settings")

        -- notify supervisor of auto waste config
        self.comms.send_fac_command(FAC_COMMAND.SET_WASTE_MODE, ctl_proc.waste_product)
        self.comms.send_fac_command(FAC_COMMAND.SET_PU_FB, ctl_proc.pu_fallback)
        self.comms.send_fac_command(FAC_COMMAND.SET_SPS_LP, ctl_proc.sps_low_power)
    end

    -- unit waste states
    local waste_modes = ctrl_states.waste_modes  ---@type table|nil
    if type(waste_modes) == "table" then
        for id, mode in pairs(waste_modes) do
            self.control_states.waste_modes[id] = mode
            self.comms.send_unit_command(UNIT_COMMAND.SET_WASTE, id, mode)
        end

        log.info("PROCESS: loaded unit waste mode settings")
    end

    -- unit priority groups
    local prio_groups = ctrl_states.priority_groups ---@type table|nil
    if type(prio_groups) == "table" then
        for id, group in pairs(prio_groups) do
            self.control_states.priority_groups[id] = group
            self.comms.send_unit_command(UNIT_COMMAND.SET_GROUP, id, group)
        end

        log.info("PROCESS: loaded priority groups settings")
    end
end

-- facility SCRAM command
function process.fac_scram()
    self.comms.send_fac_command(FAC_COMMAND.SCRAM_ALL)
    log.debug("PROCESS: FAC SCRAM ALL")
end

-- facility alarm acknowledge command
function process.fac_ack_alarms()
    self.comms.send_fac_command(FAC_COMMAND.ACK_ALL_ALARMS)
    log.debug("PROCESS: FAC ACK ALL ALARMS")
end

-- start reactor
---@param id integer unit ID
function process.start(id)
    self.io.units[id].control_state = true
    self.comms.send_unit_command(UNIT_COMMAND.START, id)
    log.debug(util.c("PROCESS: UNIT[", id, "] START"))
end

-- SCRAM reactor
---@param id integer unit ID
function process.scram(id)
    self.io.units[id].control_state = false
    self.comms.send_unit_command(UNIT_COMMAND.SCRAM, id)
    log.debug(util.c("PROCESS: UNIT[", id, "] SCRAM"))
end

-- reset reactor protection system
---@param id integer unit ID
function process.reset_rps(id)
    self.comms.send_unit_command(UNIT_COMMAND.RESET_RPS, id)
    log.debug(util.c("PROCESS: UNIT[", id, "] RESET RPS"))
end

-- set burn rate
---@param id integer unit ID
---@param rate number burn rate
function process.set_rate(id, rate)
    self.comms.send_unit_command(UNIT_COMMAND.SET_BURN, id, rate)
    log.debug(util.c("PROCESS: UNIT[", id, "] SET BURN ", rate))
end

-- set waste mode
---@param id integer unit ID
---@param mode integer waste mode
function process.set_unit_waste(id, mode)
    -- publish so that if it fails then it gets reset
    self.io.units[id].unit_ps.publish("U_WasteMode", mode)

    self.comms.send_unit_command(UNIT_COMMAND.SET_WASTE, id, mode)
    log.debug(util.c("PROCESS: UNIT[", id, "] SET WASTE ", mode))

    self.control_states.waste_modes[id] = mode
    settings.set("ControlStates", self.control_states)

    if not settings.save("/coordinator.settings") then
        log.error("process.set_unit_waste(): failed to save coordinator settings file")
    end
end

-- acknowledge all alarms
---@param id integer unit ID
function process.ack_all_alarms(id)
    self.comms.send_unit_command(UNIT_COMMAND.ACK_ALL_ALARMS, id)
    log.debug(util.c("PROCESS: UNIT[", id, "] ACK ALL ALARMS"))
end

-- acknowledge an alarm
---@param id integer unit ID
---@param alarm integer alarm ID
function process.ack_alarm(id, alarm)
    self.comms.send_unit_command(UNIT_COMMAND.ACK_ALARM, id, alarm)
    log.debug(util.c("PROCESS: UNIT[", id, "] ACK ALARM ", alarm))
end

-- reset an alarm
---@param id integer unit ID
---@param alarm integer alarm ID
function process.reset_alarm(id, alarm)
    self.comms.send_unit_command(UNIT_COMMAND.RESET_ALARM, id, alarm)
    log.debug(util.c("PROCESS: UNIT[", id, "] RESET ALARM ", alarm))
end

-- assign a unit to a group
---@param unit_id integer unit ID
---@param group_id integer|0 group ID or 0 for independent
function process.set_group(unit_id, group_id)
    self.comms.send_unit_command(UNIT_COMMAND.SET_GROUP, unit_id, group_id)
    log.debug(util.c("PROCESS: UNIT[", unit_id, "] SET GROUP ", group_id))

    self.control_states.priority_groups[unit_id] = group_id
    settings.set("ControlStates", self.control_states)

    if not settings.save("/coordinator.settings") then
        log.error("process.set_group(): failed to save coordinator settings file")
    end
end

--------------------------
-- AUTO PROCESS CONTROL --
--------------------------

-- write auto process control to config file
local function _write_auto_config()
    -- save config
    settings.set("ControlStates", self.control_states)
    local saved = settings.save("/coordinator.settings")
    if not saved then
        log.warning("process._write_auto_config(): failed to save coordinator settings file")
    end

    return saved
end

-- stop automatic process control
function process.stop_auto()
    self.comms.send_fac_command(FAC_COMMAND.STOP)
    log.debug("PROCESS: STOP AUTO CTL")
end

-- start automatic process control
function process.start_auto()
    self.comms.send_auto_start(self.control_states.process)
    log.debug("PROCESS: START AUTO CTL")
end

-- set automatic process control waste mode
---@param product WASTE_PRODUCT waste product for auto control
function process.set_process_waste(product)
    self.comms.send_fac_command(FAC_COMMAND.SET_WASTE_MODE, product)

    log.debug(util.c("PROCESS: SET WASTE ", product))

    -- update config table and save
    self.control_states.process.waste_product = product
    _write_auto_config()
end

-- set automatic process control plutonium fallback
---@param enabled boolean whether to enable plutonium fallback
function process.set_pu_fallback(enabled)
    self.comms.send_fac_command(FAC_COMMAND.SET_PU_FB, enabled)

    log.debug(util.c("PROCESS: SET PU FALLBACK ", enabled))

    -- update config table and save
    self.control_states.process.pu_fallback = enabled
    _write_auto_config()
end

-- set automatic process control SPS usage at low power
---@param enabled boolean whether to enable SPS usage at low power
function process.set_sps_low_power(enabled)
    self.comms.send_fac_command(FAC_COMMAND.SET_SPS_LP, enabled)

    log.debug(util.c("PROCESS: SET SPS LOW POWER ", enabled))

    -- update config table and save
    self.control_states.process.sps_low_power = enabled
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
    local ctl_proc = self.control_states.process
    ctl_proc.mode = mode
    ctl_proc.burn_target = burn_target
    ctl_proc.charge_target = charge_target
    ctl_proc.gen_target = gen_target
    ctl_proc.limits = limits

    -- save config
    self.io.facility.save_cfg_ack(_write_auto_config())
end

-- handle a start command acknowledgement
---@param response table ack and configuration reply
function process.start_ack_handle(response)
    local ack = response[1]

    local ctl_proc = self.control_states.process
    ctl_proc.mode = response[2]
    ctl_proc.burn_target = response[3]
    ctl_proc.charge_target = response[4]
    ctl_proc.gen_target = response[5]

    for i = 1, math.min(#response[6], self.io.facility.num_units) do
        ctl_proc.limits[i] = response[6][i]

        local unit = self.io.units[i]   ---@type ioctl_unit
        unit.unit_ps.publish("burn_limit", ctl_proc.limits[i])
    end

    self.io.facility.ps.publish("process_mode", ctl_proc.mode)
    self.io.facility.ps.publish("process_burn_target", ctl_proc.burn_target)
    self.io.facility.ps.publish("process_charge_target", ctl_proc.charge_target)
    self.io.facility.ps.publish("process_gen_target", ctl_proc.gen_target)

    self.io.facility.start_ack(ack)
end

-- record waste product state after attempting to change it
---@param response WASTE_PRODUCT supervisor waste product state
function process.waste_ack_handle(response)
    self.control_states.process.waste_product = response
    self.io.facility.ps.publish("process_waste_product", response)
end

-- record plutonium fallback state after attempting to change it
---@param response boolean supervisor plutonium fallback state
function process.pu_fb_ack_handle(response)
    self.control_states.process.pu_fallback = response
    self.io.facility.ps.publish("process_pu_fallback", response)
end

return process
