local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local psil  = require("scada-common.psil")
local util  = require("scada-common.util")

local CRDN_COMMANDS = comms.CRDN_COMMANDS

local iocontrol = {}

---@class ioctl
local io = {}

-- initialize the coordinator IO controller
---@param conf facility_conf configuration
---@param comms coord_comms comms reference
function iocontrol.init(conf, comms)
    io.facility = {
        scram = false,
        num_units = conf.num_units,
        ps = psil.create()
    }

    io.units = {}
    for i = 1, conf.num_units do
        ---@class ioctl_entry
        local entry = {
            unit_id = i,        ---@type integer
            initialized = false,

            num_boilers = 0,
            num_turbines = 0,

            control_state = false,
            burn_rate_cmd = 0.0,
            waste_control = 0,

            start = function ()
                comms.send_command(i, CRDN_COMMANDS.START)
                log.debug(util.c("sent unit ", i, ": START"))
            end,

            scram = function ()
                comms.send_command(i, CRDN_COMMANDS.SCRAM)
                log.debug(util.c("sent unit ", i, ": SCRAM"))
            end,

            set_burn = function (rate)
                comms.send_command(i, CRDN_COMMANDS.SET_BURN, rate)
                log.debug(util.c("sent unit ", i, ": SET_BURN = ", rate))
            end,

            reactor_ps = psil.create(),
            reactor_data = {},  ---@type reactor_db

            boiler_ps_tbl = {},
            boiler_data_tbl = {},

            turbine_ps_tbl = {},
            turbine_data_tbl = {}
        }

        for _ = 1, conf.defs[(i * 2) - 1] do
            local data = {} ---@type boilerv_session_db
            table.insert(entry.boiler_ps_tbl, psil.create())
            table.insert(entry.boiler_data_tbl, data)
        end

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

-- populate structure builds
---@param builds table
---@return boolean valid
function iocontrol.record_builds(builds)
    if #builds ~= #io.units then
        log.error("number of provided unit builds does not match expected number of units")
        return false
    else
        -- note: if not all units and RTUs are connected, some will be nil
        for i = 1, #builds do
            local unit = io.units[i]    ---@type ioctl_entry
            local build = builds[i]

            -- reactor build
            if type(build.reactor) == "table" then
                unit.reactor_data.mek_struct = build.reactor
                for key, val in pairs(unit.reactor_data.mek_struct) do
                    unit.reactor_ps.publish(key, val)
                end

                if unit.reactor_data.mek_struct.length ~= 0 and unit.reactor_data.mek_struct.width ~= 0 then
                    unit.reactor_ps.publish("size", { unit.reactor_data.mek_struct.length, unit.reactor_data.mek_struct.width })
                end
            end

            -- boiler builds
            if type(build.boilers) == "table" then
                for id, boiler in pairs(build.boilers) do
                    unit.boiler_data_tbl[id] = {
                        formed = boiler[2], ---@type boolean|nil
                        build = boiler[1]   ---@type table
                    }

                    unit.boiler_ps_tbl[id].publish("formed", boiler[2])

                    for key, val in pairs(unit.boiler_data_tbl[id].build) do
                        unit.boiler_ps_tbl[id].publish(key, val)
                    end
                end
            end

            -- turbine builds
            if type(build.turbines) == "table" then
                for id, turbine in pairs(build.turbines) do
                    unit.turbine_data_tbl[id] = {
                        formed = turbine[2],    ---@type boolean|nil
                        build = turbine[1]      ---@type table
                    }

                    unit.turbine_ps_tbl[id].publish("formed", turbine[2])

                    for key, val in pairs(unit.turbine_data_tbl[id].build) do
                        unit.turbine_ps_tbl[id].publish(key, val)
                    end
                end
            end
        end
    end

    return true
end

-- update unit statuses
---@param statuses table
---@return boolean valid
function iocontrol.update_statuses(statuses)
    if #statuses ~= #io.units then
        log.error("number of provided unit statuses does not match expected number of units")
        return false
    else
        for i = 1, #statuses do
            local unit = io.units[i]    ---@type ioctl_entry
            local status = statuses[i]

            -- reactor PLC status

            local reactor_status = status[1]

            if #reactor_status == 0 then
                unit.reactor_ps.publish("computed_status", 1)   -- disconnected
            else
                local mek_status = reactor_status[1]
                local rps_status = reactor_status[2]
                local gen_status = reactor_status[3]

                unit.reactor_data.last_status_update = gen_status[1]
                unit.reactor_data.control_state      = gen_status[2]
                unit.reactor_data.rps_tripped        = gen_status[3]
                unit.reactor_data.rps_trip_cause     = gen_status[4]
                unit.reactor_data.degraded           = gen_status[5]

                unit.reactor_data.rps_status = rps_status   ---@type rps_status
                unit.reactor_data.mek_status = mek_status   ---@type mek_status

                if unit.reactor_data.mek_status.status then
                    unit.reactor_ps.publish("computed_status", 3)       -- running
                else
                    if unit.reactor_data.degraded then
                        unit.reactor_ps.publish("computed_status", 5)   -- faulted
                    elseif unit.reactor_data.rps_tripped and unit.reactor_data.rps_trip_cause ~= "manual" then
                        unit.reactor_ps.publish("computed_status", 4)   -- SCRAM
                    else
                        unit.reactor_ps.publish("computed_status", 2)   -- disabled
                    end
                end

                for key, val in pairs(unit.reactor_data) do
                    if key ~= "rps_status" and key ~= "mek_struct" and key ~= "mek_status" then
                        unit.reactor_ps.publish(key, val)
                    end
                end

                for key, val in pairs(unit.reactor_data.rps_status) do
                    unit.reactor_ps.publish(key, val)
                end

                for key, val in pairs(unit.reactor_data.mek_status) do
                    unit.reactor_ps.publish(key, val)
                end
            end

            -- annunciator

            local annunciator = status[2]   ---@type annunciator

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
                elseif key == "BoilerOnline" or key == "HeatingRateLow" then
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
                    log.error("unrecognized table found in annunciator list, this is a bug", true)
                else
                    -- non-table fields
                    unit.reactor_ps.publish(key, val)
                end
            end

            -- RTU statuses

            local rtu_statuses = status[3]

            -- boiler statuses

            for id = 1, #unit.boiler_data_tbl do
                if rtu_statuses.boilers[i] == nil then
                    -- disconnected
                    unit.boiler_ps_tbl[id].publish("computed_status", 1)
                end
            end

            for id, boiler in pairs(rtu_statuses.boilers) do
                unit.boiler_data_tbl[id].state = boiler[1]  ---@type table
                unit.boiler_data_tbl[id].tanks = boiler[2]  ---@type table

                local data = unit.boiler_data_tbl[id]  ---@type boilerv_session_db

                if data.state.boil_rate > 0 then
                    unit.boiler_ps_tbl[id].publish("computed_status", 3)    -- active
                else
                    unit.boiler_ps_tbl[id].publish("computed_status", 2)    -- idle
                end

                for key, val in pairs(unit.boiler_data_tbl[id].state) do
                    unit.boiler_ps_tbl[id].publish(key, val)
                end

                for key, val in pairs(unit.boiler_data_tbl[id].tanks) do
                    unit.boiler_ps_tbl[id].publish(key, val)
                end
            end

            -- turbine statuses

            for id = 1, #unit.turbine_ps_tbl do
                if rtu_statuses.turbines[i] == nil then
                    -- disconnected
                    unit.turbine_ps_tbl[id].publish("computed_status", 1)
                end
            end

            for id, turbine in pairs(rtu_statuses.turbines) do
                unit.turbine_data_tbl[id].state = turbine[1]    ---@type table
                unit.turbine_data_tbl[id].tanks = turbine[2]    ---@type table

                local data = unit.turbine_data_tbl[id]  ---@type turbinev_session_db

                if data.tanks.steam_fill >= 0.99 then
                    unit.turbine_ps_tbl[id].publish("computed_status", 4)   -- trip
                elseif data.state.flow_rate < 100 then
                    unit.turbine_ps_tbl[id].publish("computed_status", 2)   -- idle
                else
                    unit.turbine_ps_tbl[id].publish("computed_status", 3)   -- active
                end

                for key, val in pairs(unit.turbine_data_tbl[id].state) do
                    unit.turbine_ps_tbl[id].publish(key, val)
                end

                for key, val in pairs(unit.turbine_data_tbl[id].tanks) do
                    unit.turbine_ps_tbl[id].publish(key, val)
                end
            end
        end
    end

    return true
end

-- get the IO controller database
function iocontrol.get_db() return io end

return iocontrol
