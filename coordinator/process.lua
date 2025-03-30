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

local REQUEST_TIMEOUT_MS = 10000

---@class process_controller
local process = {}

local pctl = {
    io = nil,    ---@type ioctl
    comms = nil, ---@type coord_comms
    ---@class sys_control_states
    control_states = {
        ---@class sys_auto_config
        process = {
            mode = PROCESS.INACTIVE,           ---@type PROCESS
            burn_target = 0.0,
            charge_target = 0.0,
            gen_target = 0.0,
            limits = {},                       ---@type number[]
            waste_product = PRODUCT.PLUTONIUM, ---@type WASTE_PRODUCT
            pu_fallback = false,
            sps_low_power = false
        },
        waste_modes = {},    ---@type WASTE_MODE[]
        priority_groups = {} ---@type AUTO_GROUP[]
    },
    commands = {
        unit = {}, ---@type process_command_state[][]
        fac = {}   ---@type process_command_state[]
    }
}

---@class process_command_state
---@field active boolean if this command is live
---@field timeout integer expiration time of this command request
---@field requestors function[] list of callbacks from the requestors

-- write auto process control to config file
---@return boolean saved
local function _write_auto_config()
    -- save config
    settings.set("ControlStates", pctl.control_states)
    local saved = settings.save("/coordinator.settings")
    if not saved then
        log.warning("process._write_auto_config(): failed to save coordinator settings file")
    end

    return saved
end

--#region Core

-- initialize the process controller
---@param iocontrol ioctl iocontrl system
---@param coord_comms coord_comms coordinator communications
function process.init(iocontrol, coord_comms)
    pctl.io = iocontrol
    pctl.comms = coord_comms

    -- create command handling objects
    for _, v in pairs(F_CMD) do pctl.commands.fac[v]  = { active = false, timeout = 0, requestors = {} } end
    for i = 1, pctl.io.facility.num_units do
        pctl.commands.unit[i] = {}
        for _, v in pairs(U_CMD) do pctl.commands.unit[i][v] = { active = false, timeout = 0, requestors = {} } end
    end

    local ctl_proc = pctl.control_states.process

    for i = 1, pctl.io.facility.num_units do
        ctl_proc.limits[i] = 0.1
    end

    local ctrl_states = settings.get("ControlStates", {})   ---@type sys_control_states
    local config = ctrl_states.process

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
            local unit = pctl.io.units[id]
            unit.unit_ps.publish("burn_limit", ctl_proc.limits[id])
        end

        log.info("PROCESS: loaded auto control settings")

        -- notify supervisor of auto waste config
        pctl.comms.send_fac_command(F_CMD.SET_WASTE_MODE, ctl_proc.waste_product)
        pctl.comms.send_fac_command(F_CMD.SET_PU_FB, ctl_proc.pu_fallback)
        pctl.comms.send_fac_command(F_CMD.SET_SPS_LP, ctl_proc.sps_low_power)
    end

    -- unit waste states
    local waste_modes = ctrl_states.waste_modes
    if type(waste_modes) == "table" then
        for id, mode in pairs(waste_modes) do
            pctl.control_states.waste_modes[id] = mode
            pctl.comms.send_unit_command(U_CMD.SET_WASTE, id, mode)
        end

        log.info("PROCESS: loaded unit waste mode settings")
    end

    -- unit priority groups
    local prio_groups = ctrl_states.priority_groups
    if type(prio_groups) == "table" then
        for id, group in pairs(prio_groups) do
            pctl.control_states.priority_groups[id] = group
            pctl.comms.send_unit_command(U_CMD.SET_GROUP, id, group)
        end

        log.info("PROCESS: loaded priority groups settings")
    end

    -- report to the supervisor all initial configuration data has been sent
    -- startup resume can occur if needed
    local p = ctl_proc
    pctl.comms.send_ready(p.mode, p.burn_target, p.charge_target, p.gen_target, p.limits)
end

-- create a handle to process control for usage of commands that get acknowledgements
function process.create_handle()
    ---@class process_handle
    local handle = {}

    -- add this handle to the requestors and activate the command if inactive
    ---@param cmd process_command_state
    ---@param ack function
    local function request(cmd, ack)
        local new = not cmd.active

        if new then
            cmd.active = true
            cmd.timeout = util.time_ms() + REQUEST_TIMEOUT_MS
        end

        table.insert(cmd.requestors, ack)

        return new
    end

    local function u_request(u_id, cmd_id, ack) return request(pctl.commands.unit[u_id][cmd_id], ack) end
    local function f_request(cmd_id, ack) return request(pctl.commands.fac[cmd_id], ack) end

    --#region Facility Commands

    -- facility SCRAM command
    function handle.fac_scram()
        if f_request(F_CMD.SCRAM_ALL, handle.fac_ack.on_scram) then
            pctl.comms.send_fac_command(F_CMD.SCRAM_ALL)
            log.debug("PROCESS: FAC SCRAM ALL")
        end
    end

    -- facility alarm acknowledge command
    function handle.fac_ack_alarms()
        if f_request(F_CMD.ACK_ALL_ALARMS, handle.fac_ack.on_ack_alarms) then
            pctl.comms.send_fac_command(F_CMD.ACK_ALL_ALARMS)
            log.debug("PROCESS: FAC ACK ALL ALARMS")
        end
    end

    -- start automatic process control with current settings
    function handle.process_start()
        if f_request(F_CMD.START, handle.fac_ack.on_start) then
            local p = pctl.control_states.process
            pctl.comms.send_auto_start(p.mode, p.burn_target, p.charge_target, p.gen_target, p.limits)
            log.debug("PROCESS: START AUTO CTRL")
        end
    end

    -- start automatic process control with remote settings that haven't been set on the coordinator
    ---@param mode PROCESS process control mode
    ---@param burn_target number burn rate target
    ---@param charge_target number charge level target
    ---@param gen_target number generation rate target
    ---@param limits number[] unit burn rate limits
    function handle.process_start_remote(mode, burn_target, charge_target, gen_target, limits)
        if f_request(F_CMD.START, handle.fac_ack.on_start) then
            pctl.comms.send_auto_start(mode, burn_target, charge_target, gen_target, limits)
            log.debug("PROCESS: START AUTO CTRL")
        end
    end

    -- stop process control
    function handle.process_stop()
        if f_request(F_CMD.STOP, handle.fac_ack.on_stop) then
            pctl.comms.send_fac_command(F_CMD.STOP)
            log.debug("PROCESS: STOP AUTO CTRL")
        end
    end

    handle.fac_ack = {}

    -- luacheck: no unused args

    -- facility SCRAM ack, override to implement
    ---@param success boolean
    ---@diagnostic disable-next-line: unused-local
    function handle.fac_ack.on_scram(success) end

    -- facility acknowledge all alarms ack, override to implement
    ---@param success boolean
    ---@diagnostic disable-next-line: unused-local
    function handle.fac_ack.on_ack_alarms(success) end

    -- facility auto control start ack, override to implement
    ---@param success boolean
    ---@diagnostic disable-next-line: unused-local
    function handle.fac_ack.on_start(success) end

    -- facility auto control stop ack, override to implement
    ---@param success boolean
    ---@diagnostic disable-next-line: unused-local
    function handle.fac_ack.on_stop(success) end

    -- luacheck: unused args

    --#endregion

    --#region Unit Commands

    -- start a reactor
    ---@param id integer unit ID
    function handle.start(id)
        if u_request(id, U_CMD.START, handle.unit_ack[id].on_start) then
            pctl.io.units[id].control_state = true
            pctl.comms.send_unit_command(U_CMD.START, id)
            log.debug(util.c("PROCESS: UNIT[", id, "] START"))
        end
    end

    -- SCRAM reactor
    ---@param id integer unit ID
    function handle.scram(id)
        if u_request(id, U_CMD.SCRAM, handle.unit_ack[id].on_scram) then
            pctl.io.units[id].control_state = false
            pctl.comms.send_unit_command(U_CMD.SCRAM, id)
            log.debug(util.c("PROCESS: UNIT[", id, "] SCRAM"))
        end
    end

    -- reset reactor protection system
    ---@param id integer unit ID
    function handle.reset_rps(id)
        if u_request(id, U_CMD.RESET_RPS, handle.unit_ack[id].on_rps_reset) then
            pctl.comms.send_unit_command(U_CMD.RESET_RPS, id)
            log.debug(util.c("PROCESS: UNIT[", id, "] RESET RPS"))
        end
    end

    -- acknowledge all alarms
    ---@param id integer unit ID
    function handle.ack_all_alarms(id)
        if u_request(id, U_CMD.ACK_ALL_ALARMS, handle.unit_ack[id].on_ack_alarms) then
            pctl.comms.send_unit_command(U_CMD.ACK_ALL_ALARMS, id)
            log.debug(util.c("PROCESS: UNIT[", id, "] ACK ALL ALARMS"))
        end
    end

    -- unit command acknowledgement callbacks, indexed by unit ID
    ---@type process_unit_ack[]
    handle.unit_ack = {}

    for u = 1, pctl.io.facility.num_units do
        handle.unit_ack[u] = {}

        ---@class process_unit_ack
        local u_ack = handle.unit_ack[u]

        -- luacheck: no unused args

        -- unit start ack, override to implement
        ---@param success boolean
        ---@diagnostic disable-next-line: unused-local
        function u_ack.on_start(success) end

        -- unit SCRAM ack, override to implement
        ---@param success boolean
        ---@diagnostic disable-next-line: unused-local
        function u_ack.on_scram(success) end

        -- unit RPS reset ack, override to implement
        ---@param success boolean
        ---@diagnostic disable-next-line: unused-local
        function u_ack.on_rps_reset(success) end

        -- unit acknowledge all alarms ack, override to implement
        ---@param success boolean
        ---@diagnostic disable-next-line: unused-local
        function u_ack.on_ack_alarms(success) end

        -- luacheck: unused args
    end

    --#endregion

    return handle
end

-- clear outstanding process commands that have timed out
function process.clear_timed_out()
    local now = util.time_ms()
    local objs = { pctl.commands.fac, table.unpack(pctl.commands.unit) }

    for _, obj in pairs(objs) do
        -- cancel expired requests
        for _, cmd in pairs(obj) do
            if cmd.active and now > cmd.timeout then
                cmd.active = false
                cmd.requestors = {}
            end
        end
    end
end

-- get the control states table
---@nodiscard
function process.get_control_states() return pctl.control_states end

--#endregion

--#region Command Handling

-- handle a command acknowledgement
---@param cmd_state process_command_state
---@param success boolean if the command was successful
local function cmd_ack(cmd_state, success)
    if cmd_state.active then
        cmd_state.active = false

        -- call all acknowledge callback functions
        for i = 1, #cmd_state.requestors do
            cmd_state.requestors[i](success)
        end

        cmd_state.requestors = {}
    end
end

-- handle a facility command acknowledgement
---@param command FAC_COMMAND command
---@param success boolean if the command was successful
function process.fac_ack(command, success)
    cmd_ack(pctl.commands.fac[command], success)
end

-- handle a unit command acknowledgement
---@param unit integer unit ID
---@param command UNIT_COMMAND command
---@param success boolean if the command was successful
function process.unit_ack(unit, command, success)
    cmd_ack(pctl.commands.unit[unit][command], success)
end

--#region One-Way Commands (no acknowledgements)

-- set burn rate
---@param id integer unit ID
---@param rate number burn rate
function process.set_rate(id, rate)
    pctl.comms.send_unit_command(U_CMD.SET_BURN, id, rate)
    log.debug(util.c("PROCESS: UNIT[", id, "] SET BURN ", rate))
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

--#endregion

--------------------------
-- AUTO PROCESS CONTROL --
--------------------------

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
---@param mode PROCESS process control mode
---@param burn_target number burn rate target
---@param charge_target number charge level target
---@param gen_target number generation rate target
---@param limits number[] unit burn rate limits
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
        pctl.io.units[i].unit_ps.publish("burn_limit", ctl_proc.limits[i])
    end

    pctl.io.facility.ps.publish("process_mode", ctl_proc.mode)
    pctl.io.facility.ps.publish("process_burn_target", ctl_proc.burn_target)
    pctl.io.facility.ps.publish("process_charge_target", pctl.io.energy_convert_from_fe(ctl_proc.charge_target))
    pctl.io.facility.ps.publish("process_gen_target", pctl.io.energy_convert_from_fe(ctl_proc.gen_target))

    _write_auto_config()

    process.fac_ack(F_CMD.START, ack)
end

-- record waste product settting after attempting to change it
---@param response WASTE_PRODUCT supervisor waste product settting
function process.waste_ack_handle(response)
    pctl.control_states.process.waste_product = response
    pctl.io.facility.ps.publish("process_waste_product", response)
end

-- record plutonium fallback settting after attempting to change it
---@param response boolean supervisor plutonium fallback settting
function process.pu_fb_ack_handle(response)
    pctl.control_states.process.pu_fallback = response
    pctl.io.facility.ps.publish("process_pu_fallback", response)
end

-- record SPS low power settting after attempting to change it
---@param response boolean supervisor SPS low power settting
function process.sps_lp_ack_handle(response)
    pctl.control_states.process.sps_low_power = response
    pctl.io.facility.ps.publish("process_sps_low_power", response)
end

--#endregion

return process
