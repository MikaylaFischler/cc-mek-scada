local psil = require("scada-common.psil")

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

return database
