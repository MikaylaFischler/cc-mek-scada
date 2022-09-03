local psil = require("scada-common.psil")
local log  = require("scada-common.log")

local database = {}

database.WASTE = { Pu = 0, Po = 1, AntiMatter = 2 }

---@class coord_db
local db = {}

-- initialize the coordinator database
---@param conf facility_conf configuration
function database.init(conf)
    db.facility = {
        scram = false,
        num_units = conf.num_units,
        ps = psil.create()
    }

    db.units = {}
    for i = 1, conf.num_units do
        ---@class coord_db_entry
        local entry = {
            unit_id = i,        ---@type integer
            initialized = false,

            waste_mode = 0,

            reactor_ps = psil.create(),
            reactor_data = {},  ---@type reactor_db

            boiler_ps_tbl = {},
            boiler_data_tbl = {},

            turbine_ps_tbl = {},
            turbine_data_tbl = {}
        }

        for _ = 1, conf.defs[(i * 2) - 1] do
            local data = {} ---@type boiler_session_db|boilerv_session_db
            table.insert(entry.boiler_ps_tbl, psil.create())
            table.insert(entry.boiler_data_tbl, data)
        end

        for _ = 1, conf.defs[i * 2] do
            local data = {} ---@type turbine_session_db|turbinev_session_db
            table.insert(entry.turbine_ps_tbl, psil.create())
            table.insert(entry.turbine_data_tbl, data)
        end

        table.insert(db.units, entry)
    end
end

-- populate structure builds
---@param builds table
---@return boolean valid
function database.populate_builds(builds)
    if #builds ~= #db.units then
        log.error("number of provided unit builds does not match expected number of units")
        return false
    else
        for i = 1, #builds do
            local unit = db.units[i]    ---@type coord_db_entry
            local build = builds[i]

            -- reactor build
            unit.reactor_data.mek_struct = build.reactor
            for key, val in pairs(unit.reactor_data.mek_struct) do
                unit.reactor_ps.publish(key, val)
            end

            -- boiler builds
            for id, boiler in pairs(build.boilers) do
                unit.boiler_data_tbl[id] = {
                    formed = boiler[2], ---@type boolean|nil
                    build = boiler[1]   ---@type table
                }

                unit.boiler_ps_tbl[id].publish("formed", boiler[2])

                local key_prefix = "unit_" .. i .. "_boiler_" .. id .. "_"

                for key, val in pairs(unit.boiler_data_tbl[id].build) do
                    unit.boiler_ps_tbl[id].publish(key_prefix .. key, val)
                end
            end

            -- turbine builds
            for id, turbine in pairs(build.turbines) do
                unit.turbine_data_tbl[id] = {
                    formed = turbine[2],    ---@type boolean|nil
                    build = turbine[1]      ---@type table
                }

                unit.turbine_ps_tbl[id].publish("formed", turbine[2])

                local key_prefix = "unit_" .. i .. "_turbine_" .. id .. "_"

                for key, val in pairs(unit.turbine_data_tbl[id].build) do
                    unit.turbine_ps_tbl[id].publish(key_prefix .. key, val)
                end
            end
        end
    end

    return true
end

-- update unit statuses
---@param statuses table
---@return boolean valid
function database.update_statuses(statuses)
    if #statuses ~= #db.units then
        log.error("number of provided unit statuses does not match expected number of units")
        return false
    else
        for i = 1, #statuses do
            local unit = db.units[i]    ---@type coord_db_entry
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
                unit.reactor_data.overridden         = gen_status[3]
                unit.reactor_data.degraded           = gen_status[4]
                unit.reactor_data.rps_tripped        = gen_status[5]
                unit.reactor_data.rps_trip_cause     = gen_status[6]

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
                    if key ~= "mek_struct" then
                        unit.reactor_ps.publish(key, val)
                    end
                end
            end

            -- RTU statuses

            local rtu_statuses = status[2]

            -- boiler statuses

            for id = 1, #unit.boiler_data_tbl do
                if rtu_statuses.boilers[i] == nil then
                    -- disconnected
                    unit.boiler_ps_tbl[id].publish(id .. "_computed_status", 1)
                end
            end

            for id, boiler in pairs(rtu_statuses.boilers) do
                unit.boiler_data_tbl[id].state = boiler[1]  ---@type table
                unit.boiler_data_tbl[id].tanks = boiler[2]  ---@type table

                local key_prefix = id .. "_"

                local data = unit.boiler_data_tbl[id]  ---@type boiler_session_db|boilerv_session_db

                if data.state.boil_rate > 0 then
                    unit.boiler_ps_tbl[id].publish(id .. "_computed_status", 3)    -- active
                else
                    unit.boiler_ps_tbl[id].publish(id .. "_computed_status", 2)    -- idle
                end

                for key, val in pairs(unit.boiler_data_tbl[id].state) do
                    unit.boiler_ps_tbl[id].publish(key_prefix .. key, val)
                end

                for key, val in pairs(unit.boiler_data_tbl[id].tanks) do
                    unit.boiler_ps_tbl[id].publish(key_prefix .. key, val)
                end
            end

            -- turbine statuses

            for id = 1, #unit.turbine_ps_tbl do
                if rtu_statuses.turbines[i] == nil then
                    -- disconnected
                    unit.turbine_ps_tbl[id].publish(id .. "_computed_status", 1)
                end
            end

            for id, turbine in pairs(rtu_statuses.turbines) do
                unit.turbine_data_tbl[id].state = turbine[1]    ---@type table
                unit.turbine_data_tbl[id].tanks = turbine[2]    ---@type table

                local key_prefix = id .. "_"

                local data = unit.turbine_data_tbl[id]  ---@type turbine_session_db|turbinev_session_db

                if data.tanks.steam_fill >= 0.99 then
                    unit.turbine_ps_tbl[id].publish(id .. "_computed_status", 4)    -- trip
                elseif data.state.flow_rate < 100 then
                    unit.turbine_ps_tbl[id].publish(id .. "_computed_status", 2)    -- idle
                else
                    unit.turbine_ps_tbl[id].publish(id .. "_computed_status", 3)    -- active
                end

                for key, val in pairs(unit.turbine_data_tbl[id].state) do
                    unit.turbine_ps_tbl[id].publish(key_prefix .. key, val)
                end

                for key, val in pairs(unit.turbine_data_tbl[id].tanks) do
                    unit.turbine_ps_tbl[id].publish(key_prefix .. key, val)
                end
            end
        end
    end

    return true
end

-- get the database
function database.get() return db end

return database
