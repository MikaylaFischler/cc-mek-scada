local comms   = require("scada-common.comms")
local log     = require("scada-common.log")
local psil    = require("scada-common.psil")
local types   = require("scada-common.types")
local util    = require("scada-common.util")

local process = require("coordinator.process")
local sounder = require("coordinator.sounder")

local UNIT_COMMANDS = comms.UNIT_COMMANDS

local ALARM_STATE = types.ALARM_STATE

local iocontrol = {}

---@class ioctl
local io = {}

-- initialize the coordinator IO controller
---@param conf facility_conf configuration
---@param comms coord_comms comms reference
---@diagnostic disable-next-line: redefined-local
function iocontrol.init(conf, comms)
    ---@class ioctl_facility
    io.facility = {
        all_sys_ok = false,

        auto_ready = false,
        auto_active = false,
        auto_ramping = false,
        auto_saturated = false,
        auto_scram = false,

        radiation = { radiation = 0, unit = "nSv" },    ---@type radiation_reading

        num_units = conf.num_units,                     ---@type integer

        save_cfg_ack = function (success) end,          ---@param success boolean
        start_ack = function (success) end,             ---@param success boolean
        stop_ack = function (success) end,              ---@param success boolean
        scram_ack = function (success) end,             ---@param success boolean
        ack_alarms_ack = function (success) end,        ---@param success boolean

        ps = psil.create(),

        induction_ps_tbl = {},
        induction_data_tbl = {},

        env_d_ps = psil.create(),
        env_d_data = {}
    }

    -- create induction tables (max 1 per unit, preferably 1 total)
    for _ = 1, conf.num_units do
        local data = {} ---@type imatrix_session_db
        table.insert(io.facility.induction_ps_tbl, psil.create())
        table.insert(io.facility.induction_data_tbl, data)
    end

    io.units = {}
    for i = 1, conf.num_units do
        local function ack(alarm) process.ack_alarm(i, alarm) end
        local function reset(alarm) process.reset_alarm(i, alarm) end

        ---@class ioctl_unit
        local entry = {
            ---@type integer
            unit_id = i,

            num_boilers = 0,
            num_turbines = 0,

            control_state = false,
            burn_rate_cmd = 0.0,
            waste_control = 0,
            radiation = { radiation = 0, unit = "nSv" },                ---@type radiation_reading

            a_group = 0,                                                -- auto control group

            start = function () process.start(i) end,
            scram = function () process.scram(i) end,
            reset_rps = function () process.reset_rps(i) end,
            ack_alarms = function () process.ack_all_alarms(i) end,
            set_burn = function (rate) process.set_rate(i, rate) end,   ---@param rate number burn rate
            set_waste = function (mode) process.set_waste(i, mode) end, ---@param mode integer waste processing mode

            set_group = function (grp) process.set_group(i, grp) end,   ---@param grp integer|0 group ID or 0

            start_ack = function (success) end,                         ---@param success boolean
            scram_ack = function (success) end,                         ---@param success boolean
            reset_rps_ack = function (success) end,                     ---@param success boolean
            ack_alarms_ack = function (success) end,                    ---@param success boolean
            set_burn_ack = function (success) end,                      ---@param success boolean
            set_waste_ack = function (success) end,                     ---@param success boolean

            alarm_callbacks = {
                c_breach   = { ack = function () ack(1)  end, reset = function () reset(1)  end },
                radiation  = { ack = function () ack(2)  end, reset = function () reset(2)  end },
                r_lost     = { ack = function () ack(3)  end, reset = function () reset(3)  end },
                dmg_crit   = { ack = function () ack(4)  end, reset = function () reset(4)  end },
                damage     = { ack = function () ack(5)  end, reset = function () reset(5)  end },
                over_temp  = { ack = function () ack(6)  end, reset = function () reset(6)  end },
                high_temp  = { ack = function () ack(7)  end, reset = function () reset(7)  end },
                waste_leak = { ack = function () ack(8)  end, reset = function () reset(8)  end },
                waste_high = { ack = function () ack(9)  end, reset = function () reset(9)  end },
                rps_trans  = { ack = function () ack(10) end, reset = function () reset(10) end },
                rcs_trans  = { ack = function () ack(11) end, reset = function () reset(11) end },
                t_trip     = { ack = function () ack(12) end, reset = function () reset(12) end }
            },

            ---@type alarms
            alarms = {
                ALARM_STATE.INACTIVE,   -- containment breach
                ALARM_STATE.INACTIVE,   -- containment radiation
                ALARM_STATE.INACTIVE,   -- reactor lost
                ALARM_STATE.INACTIVE,   -- damage critical
                ALARM_STATE.INACTIVE,   -- reactor taking damage
                ALARM_STATE.INACTIVE,   -- reactor over temperature
                ALARM_STATE.INACTIVE,   -- reactor high temperature
                ALARM_STATE.INACTIVE,   -- waste leak
                ALARM_STATE.INACTIVE,   -- waste level high
                ALARM_STATE.INACTIVE,   -- RPS transient
                ALARM_STATE.INACTIVE,   -- RCS transient
                ALARM_STATE.INACTIVE    -- turbine trip
            },

            annunciator = {},           ---@type annunciator

            unit_ps = psil.create(),
            reactor_data = {},          ---@type reactor_db

            boiler_ps_tbl = {},
            boiler_data_tbl = {},

            turbine_ps_tbl = {},
            turbine_data_tbl = {}
        }

        -- create boiler tables
        for _ = 1, conf.defs[(i * 2) - 1] do
            local data = {} ---@type boilerv_session_db
            table.insert(entry.boiler_ps_tbl, psil.create())
            table.insert(entry.boiler_data_tbl, data)
        end

        -- create turbine tables
        for _ = 1, conf.defs[i * 2] do
            local data = {} ---@type turbinev_session_db
            table.insert(entry.turbine_ps_tbl, psil.create())
            table.insert(entry.turbine_data_tbl, data)
        end

        entry.num_boilers = #entry.boiler_data_tbl
        entry.num_turbines = #entry.turbine_data_tbl

        table.insert(io.units, entry)
    end

    -- pass IO control here since it can't be require'd due to a require loop
    process.init(io, comms)
end

-- populate facility structure builds
---@param build table
---@return boolean valid
function iocontrol.record_facility_builds(build)
    if type(build) == "table" then
        local fac = io.facility

        -- induction matricies
        if type(build.induction) == "table" then
            for id, matrix in pairs(build.induction) do
                if type(fac.induction_data_tbl[id]) == "table" then
                    fac.induction_data_tbl[id].formed = matrix[1]  ---@type boolean
                    fac.induction_data_tbl[id].build  = matrix[2]  ---@type table

                    fac.induction_ps_tbl[id].publish("formed", matrix[1])

                    for key, val in pairs(fac.induction_data_tbl[id].build) do
                        fac.induction_ps_tbl[id].publish(key, val)
                    end
                else
                    log.debug(util.c("iocontrol.record_facility_builds: invalid induction matrix id ", id))
                end
            end
        end
    else
        log.error("facility builds not a table")
        return false
    end

    return true
end

-- populate unit structure builds
---@param builds table
---@return boolean valid
function iocontrol.record_unit_builds(builds)
    -- note: if not all units and RTUs are connected, some will be nil
    for id, build in pairs(builds) do
        local unit = io.units[id]    ---@type ioctl_unit

        if type(build) ~= "table" then
            log.error(util.c("corrupted unit builds provided, unit ", id, " not a table"))
            return false
        elseif type(unit) ~= "table" then
            log.error(util.c("corrupted unit builds provided, invalid unit ", id))
            return false
        end

        local log_header = util.c("iocontrol.record_unit_builds[unit ", id, "]: ")

        -- reactor build
        if type(build.reactor) == "table" then
            unit.reactor_data.mek_struct = build.reactor    ---@type mek_struct
            for key, val in pairs(unit.reactor_data.mek_struct) do
                unit.unit_ps.publish(key, val)
            end

            if (type(unit.reactor_data.mek_struct.length) == "number") and (unit.reactor_data.mek_struct.length ~= 0) and
                (type(unit.reactor_data.mek_struct.width) == "number")  and (unit.reactor_data.mek_struct.width ~= 0) then
                unit.unit_ps.publish("size", { unit.reactor_data.mek_struct.length, unit.reactor_data.mek_struct.width })
            end
        end

        -- boiler builds
        if type(build.boilers) == "table" then
            for b_id, boiler in pairs(build.boilers) do
                if type(unit.boiler_data_tbl[b_id]) == "table" then
                    unit.boiler_data_tbl[b_id].formed = boiler[1] ---@type boolean
                    unit.boiler_data_tbl[b_id].build  = boiler[2] ---@type table

                    unit.boiler_ps_tbl[b_id].publish("formed", boiler[1])

                    for key, val in pairs(unit.boiler_data_tbl[b_id].build) do
                        unit.boiler_ps_tbl[b_id].publish(key, val)
                    end
                else
                    log.debug(util.c(log_header, "invalid boiler id ", b_id))
                end
            end
        end

        -- turbine builds
        if type(build.turbines) == "table" then
            for t_id, turbine in pairs(build.turbines) do
                if type(unit.turbine_data_tbl[t_id]) == "table" then
                    unit.turbine_data_tbl[t_id].formed = turbine[1]   ---@type boolean
                    unit.turbine_data_tbl[t_id].build  = turbine[2]   ---@type table

                    unit.turbine_ps_tbl[t_id].publish("formed", turbine[1])

                    for key, val in pairs(unit.turbine_data_tbl[t_id].build) do
                        unit.turbine_ps_tbl[t_id].publish(key, val)
                    end
                else
                    log.debug(util.c(log_header, "invalid turbine id ", t_id))
                end
            end
        end
    end

    return true
end

-- update facility status
---@param status table
---@return boolean valid
function iocontrol.update_facility_status(status)
    local log_header = util.c("iocontrol.update_facility_status: ")
    if type(status) ~= "table" then
        log.debug(log_header .. "status not a table")
        return false
    else
        local fac = io.facility

        -- auto control status information

        local ctl_status = status[1]

        if type(ctl_status) == "table" and (#ctl_status == 9) then
            fac.all_sys_ok = ctl_status[1]
            fac.auto_ready = ctl_status[2]
            fac.auto_active = ctl_status[3] > 0
            fac.auto_ramping = ctl_status[4]
            fac.auto_saturated = ctl_status[5]
            fac.auto_scram = ctl_status[6]
            fac.status_line_1 = ctl_status[7]
            fac.status_line_2 = ctl_status[8]

            fac.ps.publish("all_sys_ok", fac.all_sys_ok)
            fac.ps.publish("auto_ready", fac.auto_ready)
            fac.ps.publish("auto_active", fac.auto_active)
            fac.ps.publish("auto_ramping", fac.auto_ramping)
            fac.ps.publish("auto_saturated", fac.auto_saturated)
            fac.ps.publish("auto_scram", fac.auto_scram)
            fac.ps.publish("status_line_1", fac.status_line_1)
            fac.ps.publish("status_line_2", fac.status_line_2)

            local group_map = ctl_status[9]

            if (type(group_map) == "table") and (#group_map == fac.num_units) then
                local names = { "Manual", "Primary", "Secondary", "Tertiary", "Backup" }
                for i = 1, #group_map do
                    io.units[i].a_group = group_map[i]
                    io.units[i].unit_ps.publish("auto_group_id", group_map[i])
                    io.units[i].unit_ps.publish("auto_group", names[group_map[i] + 1])
                end
            end
        else
            log.debug(log_header .. "control status not a table or length mismatch")
        end

        -- RTU statuses

        local rtu_statuses = status[2]

        if type(rtu_statuses) == "table" then
            -- power statistics
            if type(rtu_statuses.power) == "table" then
                fac.induction_ps_tbl[1].publish("avg_charge", rtu_statuses.power[1])
                fac.induction_ps_tbl[1].publish("avg_inflow", rtu_statuses.power[2])
                fac.induction_ps_tbl[1].publish("avg_outflow", rtu_statuses.power[3])
            else
                log.debug(log_header .. "power statistics list not a table")
            end

            -- induction matricies statuses
            if type(rtu_statuses.induction) == "table" then
                for id = 1, #fac.induction_ps_tbl do
                    if rtu_statuses.induction[id] == nil then
                        -- disconnected
                        fac.induction_ps_tbl[id].publish("computed_status", 1)
                    end
                end

                for id, matrix in pairs(rtu_statuses.induction) do
                    if type(fac.induction_data_tbl[id]) == "table" then
                        local rtu_faulted                 = matrix[1]   ---@type boolean
                        fac.induction_data_tbl[id].formed = matrix[2]   ---@type boolean
                        fac.induction_data_tbl[id].state  = matrix[3]   ---@type table
                        fac.induction_data_tbl[id].tanks  = matrix[4]   ---@type table

                        local data = fac.induction_data_tbl[id]         ---@type imatrix_session_db

                        fac.induction_ps_tbl[id].publish("formed", data.formed)
                        fac.induction_ps_tbl[id].publish("faulted", rtu_faulted)

                        if data.formed then
                            if rtu_faulted then
                                fac.induction_ps_tbl[id].publish("computed_status", 3)    -- faulted
                            elseif data.tanks.energy_fill >= 0.99 then
                                fac.induction_ps_tbl[id].publish("computed_status", 6)    -- full
                            elseif data.tanks.energy_fill <= 0.01 then
                                fac.induction_ps_tbl[id].publish("computed_status", 5)    -- empty
                            else
                                fac.induction_ps_tbl[id].publish("computed_status", 4)    -- on-line
                            end
                        else
                            fac.induction_ps_tbl[id].publish("computed_status", 2)    -- not formed
                        end

                        for key, val in pairs(fac.induction_data_tbl[id].state) do
                            fac.induction_ps_tbl[id].publish(key, val)
                        end

                        for key, val in pairs(fac.induction_data_tbl[id].tanks) do
                            fac.induction_ps_tbl[id].publish(key, val)
                        end
                    else
                        log.debug(util.c(log_header, "invalid induction matrix id ", id))
                    end
                end
            else
                log.debug(log_header .. "induction matrix list not a table")
            end

            -- environment detector status
            if type(rtu_statuses.rad_mon) == "table" then
                if #rtu_statuses.rad_mon > 0 then
                    local rad_mon = rtu_statuses.rad_mon[1]
                    local rtu_faulted = rad_mon[1]  ---@type boolean
                    fac.radiation     = rad_mon[2]  ---@type number

                    fac.ps.publish("RadMonOnline", util.trinary(rtu_faulted, 2, 3))
                    fac.ps.publish("radiation", fac.radiation)
                else
                    fac.radiation = { radiation = 0, unit = "nSv" }
                    fac.ps.publish("RadMonOnline", 1)
                end
            else
                log.debug(log_header .. "radiation monitor list not a table")
                return false
            end
        end
    end

    return true
end

-- update unit statuses
---@param statuses table
---@return boolean valid
function iocontrol.update_unit_statuses(statuses)
    if type(statuses) ~= "table" then
        log.debug("iocontrol.update_unit_statuses: unit statuses not a table")
        return false
    elseif #statuses ~= #io.units then
        log.debug("iocontrol.update_unit_statuses: number of provided unit statuses does not match expected number of units")
        return false
    else
        local burn_rate_sum = 0.0

        -- get all unit statuses
        for i = 1, #statuses do
            local log_header = util.c("iocontrol.update_unit_statuses[unit ", i, "]: ")
            local unit = io.units[i]    ---@type ioctl_unit
            local status = statuses[i]

            if type(status) ~= "table" or #status ~= 5 then
                log.debug(log_header .. "invalid status entry in unit statuses (not a table or invalid length)")
                return false
            end

            -- reactor PLC status

            local reactor_status = status[1]

            if type(reactor_status) ~= "table" then
                reactor_status = {}
                log.debug(log_header .. "reactor status not a table")
            end

            if #reactor_status == 0 then
                unit.unit_ps.publish("computed_status", 1)   -- disconnected
            elseif #reactor_status == 3 then
                local mek_status = reactor_status[1]
                local rps_status = reactor_status[2]
                local gen_status = reactor_status[3]

                if #gen_status == 6 then
                    unit.reactor_data.last_status_update = gen_status[1]
                    unit.reactor_data.control_state      = gen_status[2]
                    unit.reactor_data.rps_tripped        = gen_status[3]
                    unit.reactor_data.rps_trip_cause     = gen_status[4]
                    unit.reactor_data.no_reactor         = gen_status[5]
                    unit.reactor_data.formed             = gen_status[6]
                else
                    log.debug(log_header .. "reactor general status length mismatch")
                end

                unit.reactor_data.rps_status = rps_status   ---@type rps_status
                unit.reactor_data.mek_status = mek_status   ---@type mek_status

                -- if status hasn't been received, mek_status = {}
                if type(unit.reactor_data.mek_status.act_burn_rate) == "number" then
                    burn_rate_sum = burn_rate_sum + unit.reactor_data.mek_status.act_burn_rate
                end

                if unit.reactor_data.mek_status.status then
                    unit.unit_ps.publish("computed_status", 5)       -- running
                else
                    if unit.reactor_data.no_reactor then
                        unit.unit_ps.publish("computed_status", 3)   -- faulted
                    elseif not unit.reactor_data.formed then
                        unit.unit_ps.publish("computed_status", 2)   -- multiblock not formed
                    elseif unit.reactor_data.rps_status.force_dis then
                        unit.unit_ps.publish("computed_status", 7)   -- reactor force disabled
                    elseif unit.reactor_data.rps_tripped and unit.reactor_data.rps_trip_cause ~= "manual" then
                        unit.unit_ps.publish("computed_status", 6)   -- SCRAM
                    else
                        unit.unit_ps.publish("computed_status", 4)   -- disabled
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
            else
                log.debug(log_header .. "reactor status length mismatch")
            end

            -- RTU statuses

            local rtu_statuses = status[2]

            if type(rtu_statuses) == "table" then
                -- boiler statuses
                if type(rtu_statuses.boilers) == "table" then
                    for id = 1, #unit.boiler_ps_tbl do
                        if rtu_statuses.boilers[i] == nil then
                            -- disconnected
                            unit.boiler_ps_tbl[id].publish("computed_status", 1)
                        end
                    end

                    for id, boiler in pairs(rtu_statuses.boilers) do
                        if type(unit.boiler_data_tbl[id]) == "table" then
                            local rtu_faulted               = boiler[1] ---@type boolean
                            unit.boiler_data_tbl[id].formed = boiler[2] ---@type boolean
                            unit.boiler_data_tbl[id].state  = boiler[3] ---@type table
                            unit.boiler_data_tbl[id].tanks  = boiler[4] ---@type table

                            local data = unit.boiler_data_tbl[id]  ---@type boilerv_session_db

                            unit.boiler_ps_tbl[id].publish("formed", data.formed)
                            unit.boiler_ps_tbl[id].publish("faulted", rtu_faulted)

                            if data.formed then
                                if rtu_faulted then
                                    unit.boiler_ps_tbl[id].publish("computed_status", 3)    -- faulted
                                elseif data.state.boil_rate > 0 then
                                    unit.boiler_ps_tbl[id].publish("computed_status", 5)    -- active
                                else
                                    unit.boiler_ps_tbl[id].publish("computed_status", 4)    -- idle
                                end
                            else
                                unit.boiler_ps_tbl[id].publish("computed_status", 2)    -- not formed
                            end

                            for key, val in pairs(unit.boiler_data_tbl[id].state) do
                                unit.boiler_ps_tbl[id].publish(key, val)
                            end

                            for key, val in pairs(unit.boiler_data_tbl[id].tanks) do
                                unit.boiler_ps_tbl[id].publish(key, val)
                            end
                        else
                            log.debug(util.c(log_header, "invalid boiler id ", id))
                        end
                    end
                else
                    log.debug(log_header .. "boiler list not a table")
                end

                -- turbine statuses
                if type(rtu_statuses.turbines) == "table" then
                    for id = 1, #unit.turbine_ps_tbl do
                        if rtu_statuses.turbines[i] == nil then
                            -- disconnected
                            unit.turbine_ps_tbl[id].publish("computed_status", 1)
                        end
                    end

                    for id, turbine in pairs(rtu_statuses.turbines) do
                        if type(unit.turbine_data_tbl[id]) == "table" then
                            local rtu_faulted                = turbine[1]   ---@type boolean
                            unit.turbine_data_tbl[id].formed = turbine[2]   ---@type boolean
                            unit.turbine_data_tbl[id].state  = turbine[3]   ---@type table
                            unit.turbine_data_tbl[id].tanks  = turbine[4]   ---@type table

                            local data = unit.turbine_data_tbl[id]  ---@type turbinev_session_db

                            unit.turbine_ps_tbl[id].publish("formed", data.formed)
                            unit.turbine_ps_tbl[id].publish("faulted", rtu_faulted)

                            if data.formed then
                                if data.tanks.energy_fill >= 0.99 then
                                    unit.turbine_ps_tbl[id].publish("computed_status", 6)   -- trip
                                elseif rtu_faulted then
                                    unit.turbine_ps_tbl[id].publish("computed_status", 3)   -- faulted
                                elseif data.state.flow_rate < 100 then
                                    unit.turbine_ps_tbl[id].publish("computed_status", 4)   -- idle
                                else
                                    unit.turbine_ps_tbl[id].publish("computed_status", 5)   -- active
                                end
                            else
                                unit.turbine_ps_tbl[id].publish("computed_status", 2)       -- not formed
                            end

                            for key, val in pairs(unit.turbine_data_tbl[id].state) do
                                unit.turbine_ps_tbl[id].publish(key, val)
                            end

                            for key, val in pairs(unit.turbine_data_tbl[id].tanks) do
                                unit.turbine_ps_tbl[id].publish(key, val)
                            end
                        else
                            log.debug(util.c(log_header, "invalid turbine id ", id))
                        end
                    end
                else
                    log.debug(log_header .. "turbine list not a table")
                    return false
                end

                -- environment detector status
                if type(rtu_statuses.rad_mon) == "table" then
                    if #rtu_statuses.rad_mon > 0 then
                        local rad_mon = rtu_statuses.rad_mon[1]
                        local rtu_faulted = rad_mon[1]  ---@type boolean
                        unit.radiation    = rad_mon[2]  ---@type number

                        unit.unit_ps.publish("RadMonOnline", util.trinary(rtu_faulted, 2, 3))
                        unit.unit_ps.publish("radiation", unit.radiation)
                    else
                        unit.radiation = { radiation = 0, unit = "nSv" }
                        unit.unit_ps.publish("RadMonOnline", 1)
                    end
                else
                    log.debug(log_header .. "radiation monitor list not a table")
                    return false
                end
            else
                log.debug(log_header .. "rtu list not a table")
            end

            -- annunciator

            unit.annunciator = status[3]

            if type(unit.annunciator) ~= "table" then
                unit.annunciator = {}
                log.debug(log_header .. "annunciator state not a table")
            end

            for key, val in pairs(unit.annunciator) do
                if key == "TurbineTrip" then
                    -- split up turbine trip table for all turbines and a general OR combination
                    local trips = val
                    local any = false

                    for id = 1, #trips do
                        any = any or trips[id]
                        unit.turbine_ps_tbl[id].publish(key, trips[id])
                    end

                    unit.unit_ps.publish("TurbineTrip", any)
                elseif key == "BoilerOnline" or key == "HeatingRateLow" or key == "WaterLevelLow" then
                    -- split up array for all boilers
                    for id = 1, #val do
                        unit.boiler_ps_tbl[id].publish(key, val[id])
                    end
                elseif key == "TurbineOnline" or key == "SteamDumpOpen" or key == "TurbineOverSpeed" then
                    -- split up array for all turbines
                    for id = 1, #val do
                        unit.turbine_ps_tbl[id].publish(key, val[id])
                    end
                elseif type(val) == "table" then
                    -- we missed one of the tables?
                    log.error(log_header .. "unrecognized table found in annunciator list, this is a bug", true)
                else
                    -- non-table fields
                    unit.unit_ps.publish(key, val)
                end
            end

            -- alarms

            local alarm_states = status[4]

            if type(alarm_states) == "table" then
                for id = 1, #alarm_states do
                    local state = alarm_states[id]

                    unit.alarms[id] = state

                    if state == types.ALARM_STATE.TRIPPED or state == types.ALARM_STATE.ACKED then
                        unit.unit_ps.publish("Alarm_" .. id, 2)
                    elseif state == types.ALARM_STATE.RING_BACK then
                        unit.unit_ps.publish("Alarm_" .. id, 3)
                    else
                        unit.unit_ps.publish("Alarm_" .. id, 1)
                    end
                end
            else
                log.debug(log_header .. "alarm states not a table")
            end

            -- unit state fields

            local unit_state = status[5]

            if type(unit_state) == "table" then
                if #unit_state == 5 then
                    unit.unit_ps.publish("U_StatusLine1", unit_state[1])
                    unit.unit_ps.publish("U_StatusLine2", unit_state[2])
                    unit.unit_ps.publish("U_WasteMode", unit_state[3])
                    unit.unit_ps.publish("U_AutoReady", unit_state[4])
                    unit.unit_ps.publish("U_AutoDegraded", unit_state[5])
                else
                    log.debug(log_header .. "unit state length mismatch")
                end
            else
                log.debug(log_header .. "unit state not a table")
            end
        end

        io.facility.ps.publish("burn_sum", burn_rate_sum)

        -- update alarm sounder
        sounder.eval(io.units)
    end

    return true
end

-- get the IO controller database
function iocontrol.get_db() return io end

return iocontrol
