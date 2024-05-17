--
-- I/O Control for Pocket Integration with Supervisor & Coordinator
--

local log   = require("scada-common.log")
local psil  = require("scada-common.psil")
local types = require("scada-common.types")
local util  = require("scada-common.util")

local ALARM = types.ALARM
local ALARM_STATE = types.ALARM_STATE

---@todo nominal trip time is ping (0ms to 10ms usually)
local WARN_TT = 40
local HIGH_TT = 80

local iocontrol = {}

---@enum POCKET_LINK_STATE
local LINK_STATE = {
    UNLINKED = 0,
    SV_LINK_ONLY = 1,
    API_LINK_ONLY = 2,
    LINKED = 3
}

iocontrol.LINK_STATE = LINK_STATE

---@enum POCKET_APP_ID
local APP_ID = {
    ROOT = 1,
    -- main app page
    UNITS = 2,
    ABOUT = 3,
    -- diag app page
    ALARMS = 4,
    -- other
    DUMMY = 5,
    NUM_APPS = 5
}

iocontrol.APP_ID = APP_ID

---@class pocket_ioctl
local io = {
    version = "unknown",
    ps = psil.create()
}

---@class nav_tree_page
---@field _p nav_tree_page|nil page's parent
---@field _c table page's children
---@field nav_to function function to navigate to this page
---@field switcher function|nil function to switch between children
---@field tasks table tasks to run while viewing this page

-- allocate the page navigation system
function iocontrol.alloc_nav()
    local self = {
        pane = nil, ---@type graphics_element
        apps = {},
        containers = {},
        cur_app = APP_ID.ROOT
    }

    self.cur_page = self.root

    ---@class pocket_nav
    io.nav = {}

    -- set the root pane element to switch between apps with
    ---@param root_pane graphics_element
    function io.nav.set_pane(root_pane)
        self.pane = root_pane
    end

    function io.nav.set_sidebar(sidebar)
        self.sidebar = sidebar
    end

    -- register an app
    ---@param app_id POCKET_APP_ID app ID
    ---@param container graphics_element element that contains this app (usually a Div)
    ---@param pane graphics_element? multipane if this is a simple paned app, then nav_to must be a number
    function io.nav.register_app(app_id, container, pane)
        ---@class pocket_app
        local app = {
            loaded = false,
            load = nil,
            cur_page = nil, ---@type nav_tree_page
            pane = pane,
            paned_pages = {},
            sidebar_items = {}
        }

        app.load = function () app.loaded = true end

        -- delayed set of the pane if it wasn't ready at the start
        ---@param root_pane graphics_element multipane
        function app.set_root_pane(root_pane)
            app.pane = root_pane
        end

        function app.set_sidebar(items)
            app.sidebar_items = items
            if self.sidebar then self.sidebar.update(items) end
        end

        -- function to run on initial load into memory
        ---@param on_load function callback
        function app.set_on_load(on_load)
            app.load = function ()
                on_load()
                app.loaded = true
            end
        end

        -- if a pane was provided, this will switch between numbered pages
        ---@param idx integer page index
        function app.switcher(idx)
            if app.paned_pages[idx] then
                app.paned_pages[idx].nav_to()
            end
        end

        -- create a new page entry in the app's page navigation tree
        ---@param parent nav_tree_page? a parent page or nil to set this as the root
        ---@param nav_to function|integer function to navigate to this page or pane index
        ---@return nav_tree_page new_page this new page
        function app.new_page(parent, nav_to)
            ---@type nav_tree_page
            local page = { _p = parent, _c = {}, nav_to = function () end, switcher = function () end, tasks = {} }

            if parent == nil and app.cur_page == nil then
                app.cur_page = page
            end

            if type(nav_to) == "number" then
                app.paned_pages[nav_to] = page

                function page.nav_to()
                    app.cur_page = page
                    if app.pane then app.pane.set_value(nav_to) end
                end
            else
                function page.nav_to()
                    app.cur_page = page
                    nav_to()
                end
            end

            -- switch between children
            ---@param id integer child ID
            function page.switcher(id) if page._c[id] then page._c[id].nav_to() end end

            if parent ~= nil then
                table.insert(page._p._c, page)
            end

            return page
        end

        -- get the currently active page
        function app.get_current_page() return app.cur_page end

        -- attempt to navigate up the tree
        ---@return boolean success true if successfully navigated up
        function app.nav_up()
            local parent = app.cur_page._p
            if parent then parent.nav_to() end
            return parent ~= nil
        end

        self.apps[app_id] = app
        self.containers[app_id] = container

        return app
    end

    -- get a list of the app containers (usually Div elements)
    function io.nav.get_containers() return self.containers end

    -- open a given app
    ---@param app_id POCKET_APP_ID
    function io.nav.open_app(app_id)
        local app = self.apps[app_id]   ---@type pocket_app
        if app then
            if not app.loaded then app.load() end

            self.cur_app = app_id
            self.pane.set_value(app_id)

            if #app.sidebar_items > 0 then
                self.sidebar.update(app.sidebar_items)
            end
        else
            log.debug("tried to open unknown app")
        end
    end

    -- get the currently active page
    ---@return nav_tree_page
    function io.nav.get_current_page()
        return self.apps[self.cur_app].get_current_page()
    end

    -- attempt to navigate up
    function io.nav.nav_up()
        local app = self.apps[self.cur_app] ---@type pocket_app
        log.debug("attempting app nav up for app " .. self.cur_app)

        if not app.nav_up() then
            log.debug("internal app nav up failed, going to home screen")
            io.nav.open_app(APP_ID.ROOT)
        end
    end
end

-- initialize facility-independent components of pocket iocontrol
---@param comms pocket_comms
function iocontrol.init_core(comms)
    iocontrol.alloc_nav()

    ---@class pocket_ioctl_diag
    io.diag = {}

    -- alarm testing
    io.diag.tone_test = {
        test_1 = function (state) comms.diag__set_alarm_tone(1, state) end,
        test_2 = function (state) comms.diag__set_alarm_tone(2, state) end,
        test_3 = function (state) comms.diag__set_alarm_tone(3, state) end,
        test_4 = function (state) comms.diag__set_alarm_tone(4, state) end,
        test_5 = function (state) comms.diag__set_alarm_tone(5, state) end,
        test_6 = function (state) comms.diag__set_alarm_tone(6, state) end,
        test_7 = function (state) comms.diag__set_alarm_tone(7, state) end,
        test_8 = function (state) comms.diag__set_alarm_tone(8, state) end,
        stop_tones = function () comms.diag__set_alarm_tone(0, false) end,

        test_breach = function (state) comms.diag__set_alarm(ALARM.ContainmentBreach, state) end,
        test_rad = function (state) comms.diag__set_alarm(ALARM.ContainmentRadiation, state) end,
        test_lost = function (state) comms.diag__set_alarm(ALARM.ReactorLost, state) end,
        test_crit = function (state) comms.diag__set_alarm(ALARM.CriticalDamage, state) end,
        test_dmg = function (state) comms.diag__set_alarm(ALARM.ReactorDamage, state) end,
        test_overtemp = function (state) comms.diag__set_alarm(ALARM.ReactorOverTemp, state) end,
        test_hightemp = function (state) comms.diag__set_alarm(ALARM.ReactorHighTemp, state) end,
        test_wasteleak = function (state) comms.diag__set_alarm(ALARM.ReactorWasteLeak, state) end,
        test_highwaste = function (state) comms.diag__set_alarm(ALARM.ReactorHighWaste, state) end,
        test_rps = function (state) comms.diag__set_alarm(ALARM.RPSTransient, state) end,
        test_rcs = function (state) comms.diag__set_alarm(ALARM.RCSTransient, state) end,
        test_turbinet = function (state) comms.diag__set_alarm(ALARM.TurbineTrip, state) end,
        stop_alarms = function () comms.diag__set_alarm(0, false) end,

        get_tone_states = function () comms.diag__get_alarm_tones() end,

        ready_warn = nil,       ---@type graphics_element
        tone_buttons = {},
        alarm_buttons = {},
        tone_indicators = {}    -- indicators to update from supervisor tone states
    }

    -- API access
    ---@class pocket_ioctl_api
    io.api = {
        get_unit = function (unit) comms.api__get_unit(unit) end
    }
end

-- initialize facility-dependent components of pocket iocontrol
---@param conf facility_conf configuration
---@param temp_scale 1|2|3|4 temperature unit (1 = K, 2 = C, 3 = F, 4 = R)
function iocontrol.init_fac(conf, temp_scale)
    -- temperature unit label and conversion function (from Kelvin)
    if temp_scale == 2 then
        io.temp_label = "\xb0C"
        io.temp_convert = function (t) return t - 273.15 end
    elseif temp_scale == 3 then
        io.temp_label = "\xb0F"
        io.temp_convert = function (t) return (1.8 * (t - 273.15)) + 32 end
    elseif temp_scale == 4 then
        io.temp_label = "\xb0R"
        io.temp_convert = function (t) return 1.8 * t end
    else
        io.temp_label = "K"
        io.temp_convert = function (t) return t end
    end

    -- facility data structure
    ---@class pioctl_facility
    io.facility = {
        num_units = conf.num_units,
        tank_mode = conf.cooling.fac_tank_mode,
        tank_defs = conf.cooling.fac_tank_defs,
        all_sys_ok = false,
        rtu_count = 0,

        auto_ready = false,
        auto_active = false,
        auto_ramping = false,
        auto_saturated = false,

        auto_scram = false,
        ---@type ascram_status
        ascram_status = {
            matrix_dc = false,
            matrix_fill = false,
            crit_alarm = false,
            radiation = false,
            gen_fault = false
        },

        ---@type WASTE_PRODUCT
        auto_current_waste_product = types.WASTE_PRODUCT.PLUTONIUM,
        auto_pu_fallback_active = false,

        radiation = types.new_zero_radiation_reading(),

        ps = psil.create(),

        induction_ps_tbl = {},
        induction_data_tbl = {},

        sps_ps_tbl = {},
        sps_data_tbl = {},

        tank_ps_tbl = {},
        tank_data_tbl = {},

        env_d_ps = psil.create(),
        env_d_data = {}
    }

    -- create induction and SPS tables (currently only 1 of each is supported)
    table.insert(io.facility.induction_ps_tbl, psil.create())
    table.insert(io.facility.induction_data_tbl, {})
    table.insert(io.facility.sps_ps_tbl, psil.create())
    table.insert(io.facility.sps_data_tbl, {})

    -- determine tank information
    if io.facility.tank_mode == 0 then
        io.facility.tank_defs = {}
        -- on facility tank mode 0, setup tank defs to match unit tank option
        for i = 1, conf.num_units do
            io.facility.tank_defs[i] = util.trinary(conf.cooling.r_cool[i].TankConnection, 1, 0)
        end

        io.facility.tank_list = { table.unpack(io.facility.tank_defs) }
    else
        -- decode the layout of tanks from the connections definitions
        local tank_mode = io.facility.tank_mode
        local tank_defs = io.facility.tank_defs
        local tank_list = { table.unpack(tank_defs) }

        local function calc_fdef(start_idx, end_idx)
            local first = 4
            for i = start_idx, end_idx do
                if io.facility.tank_defs[i] == 2 then
                    if i < first then first = i end
                end
            end
            return first
        end

        if tank_mode == 1 then
            -- (1) 1 total facility tank (A A A A)
            local first_fdef = calc_fdef(1, #tank_defs)
            for i = 1, #tank_defs do
                if i > first_fdef and tank_defs[i] == 2 then
                    tank_list[i] = 0
                end
            end
        elseif tank_mode == 2 then
            -- (2) 2 total facility tanks (A A A B)
            local first_fdef = calc_fdef(1, math.min(3, #tank_defs))
            for i = 1, #tank_defs do
                if (i ~= 4) and (i > first_fdef) and (tank_defs[i] == 2) then
                    tank_list[i] = 0
                end
            end
        elseif tank_mode == 3 then
            -- (3) 2 total facility tanks (A A B B)
            for _, a in pairs({ 1, 3 }) do
                local b = a + 1
                if (tank_defs[a] == 2) and (tank_defs[b] == 2) then
                    tank_list[b] = 0
                end
            end
        elseif tank_mode == 4 then
            -- (4) 2 total facility tanks (A B B B)
            local first_fdef = calc_fdef(2, #tank_defs)
            for i = 1, #tank_defs do
                if (i ~= 1) and (i > first_fdef) and (tank_defs[i] == 2) then
                    tank_list[i] = 0
                end
            end
        elseif tank_mode == 5 then
            -- (5) 3 total facility tanks (A A B C)
            local first_fdef = calc_fdef(1, math.min(2, #tank_defs))
            for i = 1, #tank_defs do
                if (not (i == 3 or i == 4)) and (i > first_fdef) and (tank_defs[i] == 2) then
                    tank_list[i] = 0
                end
            end
        elseif tank_mode == 6 then
            -- (6) 3 total facility tanks (A B B C)
            local first_fdef = calc_fdef(2, math.min(3, #tank_defs))
            for i = 1, #tank_defs do
                if (not (i == 1 or i == 4)) and (i > first_fdef) and (tank_defs[i] == 2) then
                    tank_list[i] = 0
                end
            end
        elseif tank_mode == 7 then
            -- (7) 3 total facility tanks (A B C C)
            local first_fdef = calc_fdef(3, #tank_defs)
            for i = 1, #tank_defs do
                if (not (i == 1 or i == 2)) and (i > first_fdef) and (tank_defs[i] == 2) then
                    tank_list[i] = 0
                end
            end
        end

        io.facility.tank_list = tank_list
    end

    -- create facility tank tables
    for i = 1, #io.facility.tank_list do
        if io.facility.tank_list[i] == 2 then
            table.insert(io.facility.tank_ps_tbl, psil.create())
            table.insert(io.facility.tank_data_tbl, {})
        end
    end

    -- create unit data structures
    io.units = {}
    for i = 1, conf.num_units do
        ---@class pioctl_unit
        local entry = {
            unit_id = i,
            connected = false,
            rtu_hw = {},

            num_boilers = 0,
            num_turbines = 0,
            num_snas = 0,
            has_tank = conf.cooling.r_cool[i].TankConnection,

            control_state = false,
            burn_rate_cmd = 0.0,
            radiation = types.new_zero_radiation_reading(),

            sna_peak_rate = 0.0,
            sna_max_rate = 0.0,
            sna_out_rate = 0.0,

            waste_mode = types.WASTE_MODE.MANUAL_PLUTONIUM,
            waste_product = types.WASTE_PRODUCT.PLUTONIUM,

            -- auto control group
            a_group = 0,

            ---@type alarms
            alarms = { ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE, ALARM_STATE.INACTIVE },

            annunciator = {},   ---@type annunciator

            unit_ps = psil.create(),
            reactor_data = {},  ---@type reactor_db

            boiler_ps_tbl = {},
            boiler_data_tbl = {},

            turbine_ps_tbl = {},
            turbine_data_tbl = {},

            tank_ps_tbl = {},
            tank_data_tbl = {}
        }

        -- on other facility modes, overwrite unit TANK option with facility tank defs
        if io.facility.tank_mode ~= 0 then
            entry.has_tank = conf.cooling.fac_tank_defs[i] > 0
        end

        -- create boiler tables
        for _ = 1, conf.cooling.r_cool[i].BoilerCount do
            table.insert(entry.boiler_ps_tbl, psil.create())
            table.insert(entry.boiler_data_tbl, {})
        end

        -- create turbine tables
        for _ = 1, conf.cooling.r_cool[i].TurbineCount do
            table.insert(entry.turbine_ps_tbl, psil.create())
            table.insert(entry.turbine_data_tbl, {})
        end

        -- create tank tables
        if io.facility.tank_defs[i] == 1 then
            table.insert(entry.tank_ps_tbl, psil.create())
            table.insert(entry.tank_data_tbl, {})
        end

        entry.num_boilers = #entry.boiler_data_tbl
        entry.num_turbines = #entry.turbine_data_tbl

        table.insert(io.units, entry)
    end
end

-- set network link state
---@param state POCKET_LINK_STATE
---@param sv_addr integer? supervisor address if linked
---@param api_addr integer? coordinator address if linked
function iocontrol.report_link_state(state, sv_addr, api_addr)
    io.ps.publish("link_state", state)

    if state == LINK_STATE.API_LINK_ONLY or state == LINK_STATE.UNLINKED then
        io.ps.publish("svr_conn_quality", 0)
    end

    if state == LINK_STATE.SV_LINK_ONLY or state == LINK_STATE.UNLINKED then
        io.ps.publish("crd_conn_quality", 0)
    end

    if state == LINK_STATE.LINKED then
        io.ps.publish("sv_addr", sv_addr)
        io.ps.publish("api_addr", api_addr)
    end
end

-- determine supervisor connection quality (trip time)
---@param trip_time integer
function iocontrol.report_svr_tt(trip_time)
    local state = 3
    if trip_time > HIGH_TT then
        state = 1
    elseif trip_time > WARN_TT then
        state = 2
    end

    io.ps.publish("svr_conn_quality", state)
end

-- determine coordinator connection quality (trip time)
---@param trip_time integer
function iocontrol.report_crd_tt(trip_time)
    local state = 3
    if trip_time > HIGH_TT then
        state = 1
    elseif trip_time > WARN_TT then
        state = 2
    end

    io.ps.publish("crd_conn_quality", state)
end

-- populate facility data from API_GET_FAC
---@param data table
---@return boolean valid
function iocontrol.record_facility_data(data)
    local valid = true

    local fac = io.facility

    fac.all_sys_ok = data[1]
    fac.rtu_count = data[2]
    fac.radiation = data[3]

    -- auto control
    if type(data[4]) == "table" and #data[4] == 4 then
        fac.auto_ready = data[4][1]
        fac.auto_active = data[4][2]
        fac.auto_ramping = data[4][3]
        fac.auto_saturated = data[4][4]
    end

    -- waste
    if type(data[5]) == "table" and #data[5] == 2 then
        fac.auto_current_waste_product = data[5][1]
        fac.auto_pu_fallback_active = data[5][2]
    end

    fac.num_tanks = data[6]
    fac.has_imatrix = data[7]
    fac.has_sps = data[8]

    return valid
end

-- update unit status data from API_GET_UNIT
---@param data table
function iocontrol.record_unit_data(data)
    if type(data[1]) == "number" and io.units[data[1]] then
        local unit = io.units[data[1]]  ---@type pioctl_unit

        unit.connected = data[2]
        unit.rtu_hw = data[3]
        unit.alarms = data[4]

        --#region Annunciator

        unit.annunciator = data[5]

        local rcs_disconn, rcs_warn, rcs_hazard = false, false, false

        for key, val in pairs(unit.annunciator) do
            if key == "BoilerOnline" or key == "TurbineOnline" then
                local every = true

                -- split up online arrays
                for id = 1, #val do
                    every = every and val[id]

                    if key == "BoilerOnline" then
                        unit.boiler_ps_tbl[id].publish(key, val[id])
                    else
                        unit.turbine_ps_tbl[id].publish(key, val[id])
                    end
                end

                if not every then rcs_disconn = true end

                unit.unit_ps.publish("U_" .. key, every)
            elseif key == "HeatingRateLow" or key == "WaterLevelLow" then
                -- split up array for all boilers
                local any = false
                for id = 1, #val do
                    any = any or val[id]
                    unit.boiler_ps_tbl[id].publish(key, val[id])
                end

                if key == "HeatingRateLow" and any then
                    rcs_warn = true
                elseif key == "WaterLevelLow" and any then
                    rcs_hazard = true
                end

                unit.unit_ps.publish("U_" .. key, any)
            elseif key == "SteamDumpOpen" or key == "TurbineOverSpeed" or key == "GeneratorTrip" or key == "TurbineTrip" then
                -- split up array for all turbines
                local any = false
                for id = 1, #val do
                    any = any or val[id]
                    unit.turbine_ps_tbl[id].publish(key, val[id])
                end

                if key == "GeneratorTrip" and any then
                    rcs_warn = true
                elseif (key == "TurbineOverSpeed" or key == "TurbineTrip") and any then
                    rcs_hazard = true
                end

                unit.unit_ps.publish("U_" .. key, any)
            else
                -- non-table fields
                unit.unit_ps.publish(key, val)
            end
        end

        local anc = unit.annunciator
        rcs_hazard = rcs_hazard or anc.RCPTrip
        rcs_warn = rcs_warn or anc.RCSFlowLow or anc.CoolantLevelLow or anc.RCSFault or anc.MaxWaterReturnFeed or
                   anc.CoolantFeedMismatch or anc.BoilRateMismatch or anc.SteamFeedMismatch or anc.MaxWaterReturnFeed

        local rcs_status = 4
        if rcs_hazard then
            rcs_status = 2
        elseif rcs_warn then
            rcs_status = 3
        elseif rcs_disconn then
            rcs_status = 1
        end

        unit.unit_ps.publish("U_RCS", rcs_status)

        --#endregion

        --#region Reactor Data

        unit.reactor_data = data[6]

        local control_status = 1
        local reactor_status = 1
        local rps_status = 1

        if unit.connected then
            -- update RPS status
            if unit.reactor_data.rps_tripped then
                control_status = 2
                rps_status = util.trinary(unit.reactor_data.rps_trip_cause == "manual", 3, 2)
            else rps_status = 4 end

            -- update reactor/control status
            if unit.reactor_data.mek_status.status then
                reactor_status = 4
                control_status = util.trinary(unit.annunciator.AutoControl, 4, 3)
            else
                if unit.reactor_data.no_reactor then
                    reactor_status = 2
                elseif not unit.reactor_data.formed or unit.reactor_data.rps_status.force_dis then
                    reactor_status = 3
                else
                    reactor_status = 4
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
        end

        unit.unit_ps.publish("U_ControlStatus", control_status)
        unit.unit_ps.publish("U_ReactorStatus", reactor_status)
        unit.unit_ps.publish("U_RPS", rps_status)

        --#endregion

        unit.boiler_data_tbl = data[7]

        for id = 1, #unit.boiler_data_tbl do
            local boiler = unit.boiler_data_tbl[id] ---@type boilerv_session_db
            local ps     = unit.boiler_ps_tbl[id]   ---@type psil

            local boiler_status = 1

            if unit.rtu_hw.boilers[id].connected then
                if unit.rtu_hw.boilers[id].faulted then
                    boiler_status = 3
                elseif boiler.formed then
                    boiler_status = 4
                else
                    boiler_status = 2
                end
            end

            ps.publish("BoilerStatus", boiler_status)
        end

        unit.turbine_data_tbl = data[8]

        for id = 1, #unit.turbine_data_tbl do
            local turbine = unit.turbine_data_tbl[id] ---@type turbinev_session_db
            local ps      = unit.turbine_ps_tbl[id]   ---@type psil

            local turbine_status = 1

            if unit.rtu_hw.turbines[id].connected then
                if unit.rtu_hw.turbines[id].faulted then
                    turbine_status = 3
                elseif turbine.formed then
                    turbine_status = 4
                else
                    turbine_status = 2
                end
            end

            ps.publish("TurbineStatus", turbine_status)
        end

        unit.tank_data_tbl = data[9]
    end
end

-- get the IO controller database
function iocontrol.get_db() return io end

return iocontrol
