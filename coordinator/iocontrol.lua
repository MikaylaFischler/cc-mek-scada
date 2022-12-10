local comms   = require("scada-common.comms")
local log     = require("scada-common.log")
local psil    = require("scada-common.psil")
local types   = require("scada-common.types")
local util    = require("scada-common.util")

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
    io.facility = {
        scram = false,
        num_units = conf.num_units, ---@type integer
        ps = psil.create(),

        induction_ps_tbl = {},
        induction_data_tbl = {}
    }

    -- create induction tables (max 1 per unit, preferably 1 total)
    for _ = 1, conf.num_units do
        local data = {} ---@type imatrix_session_db
        table.insert(io.facility.induction_ps_tbl, psil.create())
        table.insert(io.facility.induction_data_tbl, data)
    end

    io.units = {}
    for i = 1, conf.num_units do
        local function ack(alarm)
            comms.send_command(UNIT_COMMANDS.ACK_ALARM, i, alarm)
            log.debug(util.c("UNIT[", i, "]: ACK ALARM ", alarm))
        end

        local function reset(alarm)
            comms.send_command(UNIT_COMMANDS.RESET_ALARM, i, alarm)
            log.debug(util.c("UNIT[", i, "]: RESET ALARM ", alarm))
        end

        ---@class ioctl_entry
        local entry = {
            unit_id = i,                                ---@type integer
            initialized = false,

            num_boilers = 0,
            num_turbines = 0,

            control_state = false,
            burn_rate_cmd = 0.0,
            waste_control = 0,

            start = function () end,
            scram = function () end,
            reset_rps = function () end,
            ack_alarms = function () end,
            set_burn = function (rate) end,             ---@param rate number
            set_waste = function (mode) end,            ---@param mode integer

            start_ack = function (success) end,         ---@param success boolean
            scram_ack = function (success) end,         ---@param success boolean
            reset_rps_ack = function (success) end,     ---@param success boolean
            ack_alarms_ack = function (success) end,    ---@param success boolean
            set_burn_ack = function (success) end,      ---@param success boolean
            set_waste_ack = function (success) end,     ---@param success boolean

            alarm_callbacks = {
                c_breach    = { ack = function () ack(1) end,  reset = function () reset(1) end },
                radiation   = { ack = function () ack(2) end,  reset = function () reset(2) end },
                r_lost      = { ack = function () ack(3) end,  reset = function () reset(3) end },
                dmg_crit    = { ack = function () ack(4) end,  reset = function () reset(4) end },
                damage      = { ack = function () ack(5) end,  reset = function () reset(5) end },
                over_temp   = { ack = function () ack(6) end,  reset = function () reset(6) end },
                high_temp   = { ack = function () ack(7) end,  reset = function () reset(7) end },
                waste_leak  = { ack = function () ack(8) end,  reset = function () reset(8) end },
                waste_high  = { ack = function () ack(9) end,  reset = function () reset(9) end },
                rps_trans   = { ack = function () ack(10) end, reset = function () reset(10) end },
                rcs_trans   = { ack = function () ack(11) end, reset = function () reset(11) end },
                t_trip      = { ack = function () ack(12) end, reset = function () reset(12) end }
            },

            ---@type alarms
            alarms = {
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE,
                ALARM_STATE.INACTIVE
            },

            reactor_ps = psil.create(),
            reactor_data = {},                          ---@type reactor_db

            boiler_ps_tbl = {},
            boiler_data_tbl = {},

            turbine_ps_tbl = {},
            turbine_data_tbl = {}
        }

        function entry.start()
            entry.control_state = true
            comms.send_command(UNIT_COMMANDS.START, i)
            log.debug(util.c("UNIT[", i, "]: START"))
        end

        function entry.scram()
            entry.control_state = false
            comms.send_command(UNIT_COMMANDS.SCRAM, i)
            log.debug(util.c("UNIT[", i, "]: SCRAM"))
        end

        function entry.reset_rps()
            comms.send_command(UNIT_COMMANDS.RESET_RPS, i)
            log.debug(util.c("UNIT[", i, "]: RESET_RPS"))
        end

        function entry.ack_alarms()
            comms.send_command(UNIT_COMMANDS.ACK_ALL_ALARMS, i)
            log.debug(util.c("UNIT[", i, "]: ACK_ALL_ALARMS"))
        end

        function entry.set_burn(rate)
            comms.send_command(UNIT_COMMANDS.SET_BURN, i, rate)
            log.debug(util.c("UNIT[", i, "]: SET_BURN = ", rate))
        end

        function entry.set_waste(mode)
            comms.send_command(UNIT_COMMANDS.SET_WASTE, i, mode)
            log.debug(util.c("UNIT[", i, "]: SET_WASTE = ", mode))
        end

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
        local unit = io.units[id]    ---@type ioctl_entry

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
            unit.reactor_data.mek_struct = build.reactor
            for key, val in pairs(unit.reactor_data.mek_struct) do
                unit.reactor_ps.publish(key, val)
            end

            if (type(unit.reactor_data.mek_struct.length) == "number") and (unit.reactor_data.mek_struct.length ~= 0) and
                (type(unit.reactor_data.mek_struct.width) == "number")  and (unit.reactor_data.mek_struct.width ~= 0) then
                unit.reactor_ps.publish("size", { unit.reactor_data.mek_struct.length, unit.reactor_data.mek_struct.width })
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

        -- RTU statuses

        local rtu_statuses = status[1]

        if type(rtu_statuses) == "table" then
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
        -- get all unit statuses
        for i = 1, #statuses do
            local log_header = util.c("iocontrol.update_unit_statuses[unit ", i, "]: ")
            local unit = io.units[i]    ---@type ioctl_entry
            local status = statuses[i]

            if type(status) ~= "table" or #status ~= 5 then
                log.debug(log_header .. "invalid status entry in unit statuses (not a table or invalid length)")
                return false
            end

            -- reactor PLC status

            local reactor_status = status[1]

            if #reactor_status == 0 then
                unit.reactor_ps.publish("computed_status", 1)   -- disconnected
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

                if unit.reactor_data.mek_status.status then
                    unit.reactor_ps.publish("computed_status", 5)       -- running
                else
                    if unit.reactor_data.no_reactor then
                        unit.reactor_ps.publish("computed_status", 3)   -- faulted
                    elseif not unit.reactor_data.formed then
                        unit.reactor_ps.publish("computed_status", 2)   -- multiblock not formed
                    elseif unit.reactor_data.rps_status.force_dis then
                        unit.reactor_ps.publish("computed_status", 7)   -- reactor force disabled
                    elseif unit.reactor_data.rps_tripped and unit.reactor_data.rps_trip_cause ~= "manual" then
                        unit.reactor_ps.publish("computed_status", 6)   -- SCRAM
                    else
                        unit.reactor_ps.publish("computed_status", 4)   -- disabled
                    end
                end

                for key, val in pairs(unit.reactor_data) do
                    if key ~= "rps_status" and key ~= "mek_struct" and key ~= "mek_status" then
                        unit.reactor_ps.publish(key, val)
                    end
                end

                if type(unit.reactor_data.rps_status) == "table" then
                    for key, val in pairs(unit.reactor_data.rps_status) do
                        unit.reactor_ps.publish(key, val)
                    end
                end

                if type(unit.reactor_data.mek_status) == "table" then
                    for key, val in pairs(unit.reactor_data.mek_status) do
                        unit.reactor_ps.publish(key, val)
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
            else
                log.debug(log_header .. "rtu list not a table")
            end

            -- annunciator

            local annunciator = status[3]   ---@type annunciator

            for key, val in pairs(annunciator) do
                if key == "TurbineTrip" then
                    -- split up turbine trip table for all turbines and a general OR combination
                    local trips = val
                    local any = false

                    for id = 1, #trips do
                        any = any or trips[id]
                        unit.turbine_ps_tbl[id].publish(key, trips[id])
                    end

                    unit.reactor_ps.publish("TurbineTrip", any)
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
                    unit.reactor_ps.publish(key, val)
                end
            end

            -- alarms

            local alarm_states = status[4]

            if type(alarm_states) == "table" then
                for id = 1, #alarm_states do
                    local state = alarm_states[id]

                    unit.alarms[id] = state

                    if state == types.ALARM_STATE.TRIPPED or state == types.ALARM_STATE.ACKED then
                        unit.reactor_ps.publish("Alarm_" .. id, 2)
                    elseif state == types.ALARM_STATE.RING_BACK then
                        unit.reactor_ps.publish("Alarm_" .. id, 3)
                    else
                        unit.reactor_ps.publish("Alarm_" .. id, 1)
                    end
                end
            else
                log.debug(log_header .. "alarm states not a table")
            end

            -- unit state fields

            local unit_state = status[5]

            if type(unit_state) == "table" then
                if #unit_state == 3 then
                    unit.reactor_ps.publish("U_StatusLine1", unit_state[1])
                    unit.reactor_ps.publish("U_StatusLine2", unit_state[2])
                    unit.reactor_ps.publish("U_WasteMode",   unit_state[3])
                else
                    log.debug(log_header .. "unit state length mismatch")
                end
            else
                log.debug(log_header .. "unit state not a table")
            end
        end

        -- update alarm sounder
        sounder.eval(io.units)
    end

    return true
end

-- get the IO controller database
function iocontrol.get_db() return io end

return iocontrol
