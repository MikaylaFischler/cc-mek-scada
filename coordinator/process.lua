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
    ---@class coord_auto_config
    config = {
        mode = PROCESS.INACTIVE,
        burn_target = 0.0,
        charge_target = 0.0,
        gen_target = 0.0,
        limits = {},
        waste_product = PRODUCT.PLUTONIUM,
        pu_fallback = false
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

    for i = 1, self.io.facility.num_units do
        self.config.limits[i] = 0.1
    end

    -- load settings
    if not settings.load("/coord.settings") then
        log.error("process.init(): failed to load coordinator settings file")
    end

    -- facility auto control configuration
    local config = settings.get("PROCESS")  ---@type coord_auto_config|nil
    if type(config) == "table" then
        self.config.mode = config.mode
        self.config.burn_target = config.burn_target
        self.config.charge_target = config.charge_target
        self.config.gen_target = config.gen_target
        self.config.limits = config.limits
        self.config.waste_product = config.waste_product
        self.config.pu_fallback = config.pu_fallback

        self.io.facility.ps.publish("process_mode", self.config.mode)
        self.io.facility.ps.publish("process_burn_target", self.config.burn_target)
        self.io.facility.ps.publish("process_charge_target", self.config.charge_target)
        self.io.facility.ps.publish("process_gen_target", self.config.gen_target)
        self.io.facility.ps.publish("process_waste_product", self.config.waste_product)
        self.io.facility.ps.publish("process_pu_fallback", self.config.pu_fallback)

        for id = 1, math.min(#self.config.limits, self.io.facility.num_units) do
            local unit = self.io.units[id]   ---@type ioctl_unit
            unit.unit_ps.publish("burn_limit", self.config.limits[id])
        end

        log.info("PROCESS: loaded auto control settings from coord.settings")

        -- notify supervisor of auto waste config
        self.comms.send_fac_command(FAC_COMMAND.SET_WASTE_MODE, self.config.waste_product)
        self.comms.send_fac_command(FAC_COMMAND.SET_PU_FB, self.config.pu_fallback)
    end

    -- unit waste states
    local waste_modes = settings.get("WASTE_MODES")  ---@type table|nil
    if type(waste_modes) == "table" then
        for id, mode in pairs(waste_modes) do
            self.comms.send_unit_command(UNIT_COMMAND.SET_WASTE, id, mode)
        end

        log.info("PROCESS: loaded unit waste mode settings from coord.settings")
    end

    -- unit priority groups
    local prio_groups = settings.get("PRIORITY_GROUPS") ---@type table|nil
    if type(prio_groups) == "table" then
        for id, group in pairs(prio_groups) do
            self.comms.send_unit_command(UNIT_COMMAND.SET_GROUP, id, group)
        end

        log.info("PROCESS: loaded priority groups settings from coord.settings")
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

    local waste_mode = settings.get("WASTE_MODES")  ---@type table|nil

    if type(waste_mode) ~= "table" then waste_mode = {} end

    waste_mode[id] = mode

    settings.set("WASTE_MODES", waste_mode)

    if not settings.save("/coord.settings") then
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

    local prio_groups = settings.get("PRIORITY_GROUPS") ---@type table|nil

    if type(prio_groups) ~= "table" then prio_groups = {} end

    prio_groups[unit_id] = group_id

    settings.set("PRIORITY_GROUPS", prio_groups)

    if not settings.save("/coord.settings") then
        log.error("process.set_group(): failed to save coordinator settings file")
    end
end

--------------------------
-- AUTO PROCESS CONTROL --
--------------------------

-- write auto process control to config file
local function _write_auto_config()
    -- attempt to load settings
    if not settings.load("/coord.settings") then
        log.warning("process._write_auto_config(): failed to load coordinator settings file")
    end

    -- save config
    settings.set("PROCESS", self.config)
    local saved = settings.save("/coord.settings")

    if not saved then
        log.warning("process._write_auto_config(): failed to save coordinator settings file")
    end

    return not not saved
end

-- stop automatic process control
function process.stop_auto()
    self.comms.send_fac_command(FAC_COMMAND.STOP)
    log.debug("PROCESS: STOP AUTO CTL")
end

-- start automatic process control
function process.start_auto()
    self.comms.send_auto_start(self.config)
    log.debug("PROCESS: START AUTO CTL")
end

-- set automatic process control waste mode
---@param product WASTE_PRODUCT waste product for auto control
function process.set_process_waste(product)
    self.comms.send_fac_command(FAC_COMMAND.SET_WASTE_MODE, product)

    log.debug(util.c("PROCESS: SET WASTE ", product))

    -- update config table and save
    self.config.waste_product = product
    _write_auto_config()
end

-- set automatic process control plutonium fallback
---@param enabled boolean whether to enable plutonium fallback
function process.set_pu_fallback(enabled)
    self.comms.send_fac_command(FAC_COMMAND.SET_PU_FB, enabled)

    log.debug(util.c("PROCESS: SET PU FALLBACK ", enabled))

    -- update config table and save
    self.config.pu_fallback = enabled
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
    self.config.mode = mode
    self.config.burn_target = burn_target
    self.config.charge_target = charge_target
    self.config.gen_target = gen_target
    self.config.limits = limits

    -- save config
    self.io.facility.save_cfg_ack(_write_auto_config())
end

-- handle a start command acknowledgement
---@param response table ack and configuration reply
function process.start_ack_handle(response)
    local ack = response[1]

    self.config.mode = response[2]
    self.config.burn_target = response[3]
    self.config.charge_target = response[4]
    self.config.gen_target = response[5]

    for i = 1, math.min(#response[6], self.io.facility.num_units) do
        self.config.limits[i] = response[6][i]

        local unit = self.io.units[i]   ---@type ioctl_unit
        unit.unit_ps.publish("burn_limit", self.config.limits[i])
    end

    self.io.facility.ps.publish("process_mode", self.config.mode)
    self.io.facility.ps.publish("process_burn_target", self.config.burn_target)
    self.io.facility.ps.publish("process_charge_target", self.config.charge_target)
    self.io.facility.ps.publish("process_gen_target", self.config.gen_target)

    self.io.facility.start_ack(ack)
end

-- record waste product state after attempting to change it
---@param response WASTE_PRODUCT supervisor waste product state
function process.waste_ack_handle(response)
    self.config.waste_product = response
    self.io.facility.ps.publish("process_waste_product", response)
end

-- record plutonium fallback state after attempting to change it
---@param response boolean supervisor plutonium fallback state
function process.pu_fb_ack_handle(response)
    self.config.pu_fallback = response
    self.io.facility.ps.publish("process_pu_fallback", response)
end

return process
