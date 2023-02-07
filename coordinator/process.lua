
local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local types = require("scada-common.types")
local util  = require("scada-common.util")

local FAC_COMMANDS = comms.FAC_COMMANDS
local UNIT_COMMANDS = comms.UNIT_COMMANDS

local PROCESS = types.PROCESS

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
        limits = {}
    }
}

--------------------------
-- UNIT COMMAND CONTROL --
--------------------------

-- initialize the process controller
---@param iocontrol ioctl
---@diagnostic disable-next-line: redefined-local
function process.init(iocontrol, comms)
    self.io = iocontrol
    self.comms = comms

    for i = 1, self.io.facility.num_units do
        self.config.limits[i] = 0.1
    end

    -- load settings
    if not settings.load("/coord.settings") then
        log.error("process.init(): failed to load coordinator settings file")
    end

    local config = settings.get("PROCESS")  ---@type coord_auto_config|nil

    if type(config) == "table" then
        self.config.mode = config.mode
        self.config.burn_target = config.burn_target
        self.config.charge_target = config.charge_target
        self.config.gen_target = config.gen_target
        self.config.limits = config.limits

        self.io.facility.ps.publish("process_mode", self.config.mode)
        self.io.facility.ps.publish("process_burn_target", self.config.burn_target)
        self.io.facility.ps.publish("process_charge_target", self.config.charge_target)
        self.io.facility.ps.publish("process_gen_target", self.config.gen_target)

        for id = 1, math.min(#self.config.limits, self.io.facility.num_units) do
            local unit = self.io.units[id]   ---@type ioctl_unit
            unit.unit_ps.publish("burn_limit", self.config.limits[id])
        end

        log.info("PROCESS: loaded auto control settings from coord.settings")
    end

    local waste_mode = settings.get("WASTE_MODES")  ---@type table|nil

    if type(waste_mode) == "table" then
        for id, mode in pairs(waste_mode) do
            self.comms.send_unit_command(UNIT_COMMANDS.SET_WASTE, id, mode)
        end

        log.info("PROCESS: loaded waste mode settings from coord.settings")
    end

    local prio_groups = settings.get("PRIORITY_GROUPS") ---@type table|nil

    if type(prio_groups) == "table" then
        for id, group in pairs(prio_groups) do
            self.comms.send_unit_command(UNIT_COMMANDS.SET_GROUP, id, group)
        end

        log.info("PROCESS: loaded priority groups settings from coord.settings")
    end
end

-- facility SCRAM command
function process.fac_scram()
    self.comms.send_fac_command(FAC_COMMANDS.SCRAM_ALL)
    log.debug("FAC: SCRAM ALL")
end

-- facility alarm acknowledge command
function process.fac_ack_alarms()
    self.comms.send_fac_command(FAC_COMMANDS.ACK_ALL_ALARMS)
    log.debug("FAC: ACK ALL ALARMS")
end

-- start reactor
---@param id integer unit ID
function process.start(id)
    self.io.units[id].control_state = true
    self.comms.send_unit_command(UNIT_COMMANDS.START, id)
    log.debug(util.c("UNIT[", id, "]: START"))
end

-- SCRAM reactor
---@param id integer unit ID
function process.scram(id)
    self.io.units[id].control_state = false
    self.comms.send_unit_command(UNIT_COMMANDS.SCRAM, id)
    log.debug(util.c("UNIT[", id, "]: SCRAM"))
end

-- reset reactor protection system
---@param id integer unit ID
function process.reset_rps(id)
    self.comms.send_unit_command(UNIT_COMMANDS.RESET_RPS, id)
    log.debug(util.c("UNIT[", id, "]: RESET RPS"))
end

-- set burn rate
---@param id integer unit ID
---@param rate number burn rate
function process.set_rate(id, rate)
    self.comms.send_unit_command(UNIT_COMMANDS.SET_BURN, id, rate)
    log.debug(util.c("UNIT[", id, "]: SET BURN = ", rate))
end

-- set waste mode
---@param id integer unit ID
---@param mode integer waste mode
function process.set_waste(id, mode)
    -- publish so that if it fails then it gets reset
    self.io.units[id].unit_ps.publish("U_WasteMode", mode)

    self.comms.send_unit_command(UNIT_COMMANDS.SET_WASTE, id, mode)
    log.debug(util.c("UNIT[", id, "]: SET WASTE = ", mode))

    local waste_mode = settings.get("WASTE_MODES")  ---@type table|nil

    if type(waste_mode) ~= "table" then
        waste_mode = {}
    end

    waste_mode[id] = mode

    settings.set("WASTE_MODES", waste_mode)

    if not settings.save("/coord.settings") then
        log.error("process.set_waste(): failed to save coordinator settings file")
    end
end

-- acknowledge all alarms
---@param id integer unit ID
function process.ack_all_alarms(id)
    self.comms.send_unit_command(UNIT_COMMANDS.ACK_ALL_ALARMS, id)
    log.debug(util.c("UNIT[", id, "]: ACK ALL ALARMS"))
end

-- acknowledge an alarm
---@param id integer unit ID
---@param alarm integer alarm ID
function process.ack_alarm(id, alarm)
    self.comms.send_unit_command(UNIT_COMMANDS.ACK_ALARM, id, alarm)
    log.debug(util.c("UNIT[", id, "]: ACK ALARM ", alarm))
end

-- reset an alarm
---@param id integer unit ID
---@param alarm integer alarm ID
function process.reset_alarm(id, alarm)
    self.comms.send_unit_command(UNIT_COMMANDS.RESET_ALARM, id, alarm)
    log.debug(util.c("UNIT[", id, "]: RESET ALARM ", alarm))
end

-- assign a unit to a group
---@param unit_id integer unit ID
---@param group_id integer|0 group ID or 0 for independent
function process.set_group(unit_id, group_id)
    self.comms.send_unit_command(UNIT_COMMANDS.SET_GROUP, unit_id, group_id)
    log.debug(util.c("UNIT[", unit_id, "]: SET GROUP ", group_id))

    local prio_groups = settings.get("PRIORITY_GROUPS") ---@type table|nil

    if type(prio_groups) ~= "table" then
        prio_groups = {}
    end

    prio_groups[unit_id] = group_id

    settings.set("PRIORITY_GROUPS", prio_groups)

    if not settings.save("/coord.settings") then
        log.error("process.set_group(): failed to save coordinator settings file")
    end
end

--------------------------
-- AUTO PROCESS CONTROL --
--------------------------

-- stop automatic process control
function process.stop_auto()
    self.comms.send_fac_command(FAC_COMMANDS.STOP)
    log.debug("FAC: STOP AUTO")
end

-- start automatic process control
function process.start_auto()
    self.comms.send_auto_start(self.config)
    log.debug("FAC: START AUTO")
end

-- save process control settings
---@param mode PROCESS control mode
---@param burn_target number burn rate target
---@param charge_target number charge target
---@param gen_target number generation rate target
---@param limits table unit burn rate limits
function process.save(mode, burn_target, charge_target, gen_target, limits)
    -- attempt to load settings
    if not settings.load("/coord.settings") then
        log.warning("process.save(): failed to load coordinator settings file")
    end

    -- config table
    self.config = {
        mode = mode,
        burn_target = burn_target,
        charge_target = charge_target,
        gen_target = gen_target,
        limits = limits
    }

    -- save config
    settings.set("PROCESS", self.config)
    local saved = settings.save("/coord.settings")

    if not saved then
        log.warning("process.save(): failed to save coordinator settings file")
    end

    log.debug("saved = " .. util.strval(saved))

    self.io.facility.save_cfg_ack(saved)
end

-- handle a start command acknowledgement
---@param response table ack and configuration reply
function process.start_ack_handle(response)
    local ack = response[1]

    self.config.mode = response[2]
    self.config.burn_target = response[3]
    self.config.charge_target = response[4]
    self.config.gen_target = response[5]

    for i = 1, #response[6] do
        self.config.limits[i] = response[6][i]
    end

    self.io.facility.ps.publish("auto_mode", self.config.mode)
    self.io.facility.ps.publish("burn_target", self.config.burn_target)
    self.io.facility.ps.publish("charge_target", self.config.charge_target)
    self.io.facility.ps.publish("gen_target", self.config.gen_target)

    self.io.facility.start_ack(ack)
end

--------------------------
-- SUPERVISOR RESPONSES --
--------------------------

-- acknowledgement from the supervisor to assign a unit to a group
function process.sv_assign(unit_id, group_id)
    self.io.units[unit_id].group = group_id
end

-- acknowledgement from the supervisor to assign a unit a burn rate limit
function process.sv_limit(unit_id, limit)
    self.io.units[unit_id].limit = limit
end

return process
