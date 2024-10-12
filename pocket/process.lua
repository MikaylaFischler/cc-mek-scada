--
-- Process Control Management
--

local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local util  = require("scada-common.util")

local FAC_COMMAND = comms.FAC_COMMAND
local UNIT_COMMAND = comms.UNIT_COMMAND

---@class pocket_process_controller
local process = {}

local self = {
    io = nil,   ---@type ioctl
    comms = nil ---@type pocket_comms
}

-- initialize the process controller
---@param iocontrol pocket_ioctl iocontrl system
---@param pocket_comms pocket_comms pocket communications
function process.init(iocontrol, pocket_comms)
    self.io = iocontrol
    self.comms = pocket_comms
end


------------------------------
--#region FACILITY COMMANDS --

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

--#endregion
------------------------------

--------------------------
--#region UNIT COMMANDS --

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

-- assign a unit to a group
---@param unit_id integer unit ID
---@param group_id integer|0 group ID or 0 for independent
function process.set_group(unit_id, group_id)
    self.comms.send_unit_command(UNIT_COMMAND.SET_GROUP, unit_id, group_id)
    log.debug(util.c("PROCESS: UNIT[", unit_id, "] SET GROUP ", group_id))
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

-- #endregion
--------------------------

---------------------------------
--#region AUTO PROCESS CONTROL --

-- process start command
---@param mode PROCESS process control mode
---@param burn_target number burn rate target
---@param charge_target number charge level target
---@param gen_target number generation rate target
---@param limits number[] unit burn rate limits
function process.process_start(mode, burn_target, charge_target, gen_target, limits)
    self.comms.send_auto_start({ mode, burn_target, charge_target, gen_target, limits })
    log.debug("PROCESS: START AUTO CTRL")
end

-- process stop command
function process.process_stop()
    self.comms.send_fac_command(FAC_COMMAND.STOP)
    log.debug("PROCESS: STOP AUTO CTRL")
end

-- #endregion
---------------------------------

return process
