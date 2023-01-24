
local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local util  = require("scada-common.util")

local UNIT_COMMANDS = comms.UNIT_COMMANDS

---@class process_controller
local process = {}

local self = {
    io = nil,       ---@type ioctl
    comms = nil     ---@type coord_comms
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

    -- load settings
    if not settings.load("/coord.settings") then
        log.error("process.init(): failed to load coordinator settings file")
    end

    local waste_mode = settings.get("WASTE_MODES")  ---@type table|nil

    if type(waste_mode) == "table" then
        for id = 1, math.min(#waste_mode, self.io.facility.num_units) do
            self.comms.send_unit_command(UNIT_COMMANDS.SET_WASTE, id, waste_mode[id])
        end

        log.info("PROCESS: loaded waste mode settings from coord.settings")
    end
end

-- start reactor
---@param id integer unit ID
function process.start(id)
    self.io.units[id].control_state = true
    self.comms.send_command(UNIT_COMMANDS.START, id)
    log.debug(util.c("UNIT[", id, "]: START"))
end

-- SCRAM reactor
---@param id integer unit ID
function process.scram(id)
    self.io.units[id].control_state = false
    self.comms.send_command(UNIT_COMMANDS.SCRAM, id)
    log.debug(util.c("UNIT[", id, "]: SCRAM"))
end

-- reset reactor protection system
---@param id integer unit ID
function process.reset_rps(id)
    self.comms.send_command(UNIT_COMMANDS.RESET_RPS, id)
    log.debug(util.c("UNIT[", id, "]: RESET RPS"))
end

-- set burn rate
---@param id integer unit ID
---@param rate number burn rate
function process.set_rate(id, rate)
    self.comms.send_command(UNIT_COMMANDS.SET_BURN, id, rate)
    log.debug(util.c("UNIT[", id, "]: SET BURN = ", rate))
end

-- set waste mode
---@param id integer unit ID
---@param mode integer waste mode
function process.set_waste(id, mode)
    self.comms.send_command(UNIT_COMMANDS.SET_WASTE, id, mode)
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
    self.comms.send_command(UNIT_COMMANDS.ACK_ALL_ALARMS, id)
    log.debug(util.c("UNIT[", id, "]: ACK ALL ALARMS"))
end

-- acknowledge an alarm
---@param id integer unit ID
---@param alarm integer alarm ID
function process.ack_alarm(id, alarm)
    self.comms.send_command(UNIT_COMMANDS.ACK_ALARM, id, alarm)
    log.debug(util.c("UNIT[", id, "]: ACK ALARM ", alarm))
end

-- reset an alarm
---@param id integer unit ID
---@param alarm integer alarm ID
function process.reset_alarm(id, alarm)
    self.comms.send_command(UNIT_COMMANDS.RESET_ALARM, id, alarm)
    log.debug(util.c("UNIT[", id, "]: RESET ALARM ", alarm))
end

-- assign a unit to a group
---@param unit_id integer unit ID
---@param group_id integer|0 group ID or 0 for independent
function process.set_group(unit_id, group_id)
    self.comms.send_command(UNIT_COMMANDS.SET_GROUP, unit_id, group_id)
    log.debug(util.c("UNIT[", unit_id, "]: SET GROUP ", group_id))
end

-- set the burn rate limit
---@param id integer unit ID
---@param limit number burn rate limit
function process.set_limit(id, limit)
    self.comms.send_command(UNIT_COMMANDS.SET_LIMIT, id, limit)
    log.debug(util.c("UNIT[", id, "]: SET LIMIT = ", limit))
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
