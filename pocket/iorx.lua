--
-- I/O Control's Data Receive (Rx) Handlers
--

local const = require("scada-common.constants")
local types = require("scada-common.types")
local util  = require("scada-common.util")

local ALARM = types.ALARM
local ALARM_STATE = types.ALARM_STATE

local BLR_STATE = types.BOILER_STATE
local TRB_STATE = types.TURBINE_STATE
local TNK_STATE = types.TANK_STATE
local MTX_STATE = types.IMATRIX_STATE
local SPS_STATE = types.SPS_STATE

local io        ---@type pocket_ioctl
local iorx = {} ---@class iorx

-- populate facility data from API_GET_FAC
---@param data table
---@return boolean valid
function iorx.record_facility_data(data)
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

local function tripped(state) return state == ALARM_STATE.TRIPPED or state == ALARM_STATE.ACKED end

local function _record_multiblock_status(faulted, data, ps)
    ps.publish("formed", data.formed)
    ps.publish("faulted", faulted)

    ---@todo revisit this
    if data.build then
        for key, val in pairs(data.build) do ps.publish(key, val) end
    end

    for key, val in pairs(data.state) do ps.publish(key, val) end
    for key, val in pairs(data.tanks) do ps.publish(key, val) end
end

-- update unit status data from API_GET_UNIT
---@param data table
function iorx.record_unit_data(data)
    local unit = io.units[data[1]]

    unit.connected = data[2]
    local comp_statuses = data[3]
    unit.a_group = data[4]
    unit.alarms = data[5]

    local next_c_stat = 1

    unit.unit_ps.publish("auto_group_id", unit.a_group)
    unit.unit_ps.publish("auto_group", types.AUTO_GROUP_NAMES[unit.a_group + 1])

    --#region Annunciator

    unit.annunciator = data[6]

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
                anc.CoolantFeedMismatch or anc.BoilRateMismatch or anc.SteamFeedMismatch

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

    unit.reactor_data = data[7]

    local control_status = 1
    local reactor_status = 1
    local rps_status = 1

    if unit.connected then
        -- update RPS status
        if unit.reactor_data.rps_tripped then
            control_status = 2
            rps_status = util.trinary(unit.reactor_data.rps_trip_cause == "manual", 3, 2)
        else
            rps_status = 4
        end

        reactor_status = 4  -- ok, until proven otherwise

        -- update reactor/control status
        if unit.reactor_data.mek_status.status then
            control_status = util.trinary(unit.annunciator.AutoControl, 4, 3)
        else
            if unit.reactor_data.no_reactor then
                reactor_status = 2
            elseif (not unit.reactor_data.formed) or unit.reactor_data.rps_status.force_dis then
                reactor_status = 3
            end
        end

        for key, val in pairs(unit.reactor_data) do
            if key ~= "rps_status" and key ~= "mek_struct" and key ~= "mek_status" then
                unit.unit_ps.publish(key, val)
            end
        end

        for key, val in pairs(unit.reactor_data.rps_status) do
            unit.unit_ps.publish(key, val)
        end

        for key, val in pairs(unit.reactor_data.mek_struct) do
            unit.unit_ps.publish(key, val)
        end

        for key, val in pairs(unit.reactor_data.mek_status) do
            unit.unit_ps.publish(key, val)
        end
    end

    unit.unit_ps.publish("U_ControlStatus", control_status)
    unit.unit_ps.publish("U_ReactorStatus", reactor_status)
    unit.unit_ps.publish("U_ReactorStateStatus", comp_statuses[next_c_stat])
    unit.unit_ps.publish("U_RPS", rps_status)

    next_c_stat = next_c_stat + 1

    --#endregion

    --#region RTU Devices

    unit.boiler_data_tbl = data[8]

    for id = 1, #unit.boiler_data_tbl do
        local boiler = unit.boiler_data_tbl[id]
        local ps     = unit.boiler_ps_tbl[id]
        local c_stat = comp_statuses[next_c_stat]

        local boiler_status = 1

        if c_stat ~= BLR_STATE.OFFLINE then
            if c_stat == BLR_STATE.FAULT then
                boiler_status = 3
            elseif c_stat ~= BLR_STATE.UNFORMED then
                boiler_status = 4
            else
                boiler_status = 2
            end

            _record_multiblock_status(c_stat == BLR_STATE.FAULT, boiler, ps)
        end

        ps.publish("BoilerStatus", boiler_status)
        ps.publish("BoilerStateStatus", c_stat)

        next_c_stat = next_c_stat + 1
    end

    unit.turbine_data_tbl = data[9]

    for id = 1, #unit.turbine_data_tbl do
        local turbine = unit.turbine_data_tbl[id]
        local ps      = unit.turbine_ps_tbl[id]
        local c_stat  = comp_statuses[next_c_stat]

        local turbine_status = 1

        if c_stat ~= TRB_STATE.OFFLINE then
            if c_stat == TRB_STATE.FAULT then
                turbine_status = 3
            elseif turbine.formed then
                turbine_status = 4
            else
                turbine_status = 2
            end

            _record_multiblock_status(c_stat == TRB_STATE.FAULT, turbine, ps)
        end

        ps.publish("TurbineStatus", turbine_status)
        ps.publish("TurbineStateStatus", c_stat)

        next_c_stat = next_c_stat + 1
    end

    unit.tank_data_tbl = data[10]

    for id = 1, #unit.tank_data_tbl do
        local tank   = unit.tank_data_tbl[id]
        local ps     = unit.tank_ps_tbl[id]
        local c_stat = comp_statuses[next_c_stat]

        local tank_status = 1

        if c_stat ~= TNK_STATE.OFFLINE then
            if c_stat == TNK_STATE.FAULT then
                tank_status = 3
            elseif tank.formed then
                tank_status = 4
            else
                tank_status = 2
            end

            _record_multiblock_status(c_stat == TNK_STATE.FAULT, tank, ps)
        end

        ps.publish("DynamicTankStatus", tank_status)
        ps.publish("DynamicTankStateStatus", c_stat)

        next_c_stat = next_c_stat + 1
    end

    unit.last_rate_change_ms = data[11]
    unit.turbine_flow_stable = data[12]

    --#endregion

    --#region Status Information Display

    local ecam = {} -- aviation reference :)

    -- local function red(text) return { text = text, color = colors.red } end
    local function white(text) return { text = text, color = colors.white } end
    local function blue(text) return { text = text, color = colors.blue } end

    -- if unit.reactor_data.rps_status then
    --     for k, v in pairs(unit.alarms) do
    --         unit.alarms[k] = ALARM_STATE.TRIPPED
    --     end
    -- end

    if tripped(unit.alarms[ALARM.ContainmentBreach]) then
        local items = { white("REACTOR MELTDOWN"), blue("DON HAZMAT SUIT") }
        table.insert(ecam, { color = colors.red, text = "CONTAINMENT BREACH", help = "ContainmentBreach", items = items })
    end

    if tripped(unit.alarms[ALARM.ContainmentRadiation]) then
        local items = {
            white("RADIATION DETECTED"),
            blue("DON HAZMAT SUIT"),
            blue("RESOLVE LEAK"),
            blue("AWAIT SAFE LEVELS")
        }

        table.insert(ecam, { color = colors.red, text = "RADIATION LEAK", help = "ContainmentRadiation", items = items })
    end

    if tripped(unit.alarms[ALARM.CriticalDamage]) then
        local items = { white("MELTDOWN IMMINENT"), blue("EVACUATE") }
        table.insert(ecam, { color = colors.red, text = "RCT DAMAGE CRITICAL", help = "CriticalDamage", items = items })
    end

    if tripped(unit.alarms[ALARM.ReactorLost]) then
        local items = { white("REACTOR OFF-LINE"), blue("CHECK PLC") }
        table.insert(ecam, { color = colors.red, text = "REACTOR CONN LOST", help = "ReactorLost", items = items })
    end

    if tripped(unit.alarms[ALARM.ReactorDamage]) then
        local items = { white("REACTOR DAMAGED"), blue("CHECK RCS"), blue("AWAIT DMG REDUCED") }
        table.insert(ecam, { color = colors.red, text = "REACTOR DAMAGE", help = "ReactorDamage", items = items })
    end

    if tripped(unit.alarms[ALARM.ReactorOverTemp]) then
        local items = { white("DAMAGING TEMP"), blue("CHECK RCS"), blue("AWAIT COOLDOWN") }
        table.insert(ecam, { color = colors.red, text = "REACTOR OVER TEMP", help = "ReactorOverTemp", items = items })
    end

    if tripped(unit.alarms[ALARM.ReactorHighTemp]) then
        local items = { white("OVER EXPECTED TEMP"), blue("CHECK RCS") }
        table.insert(ecam, { color = colors.yellow, text = "REACTOR HIGH TEMP", help = "ReactorHighTemp", items = items})
    end

    if tripped(unit.alarms[ALARM.ReactorWasteLeak]) then
        local items = { white("AT WASTE CAPACITY"), blue("CHECK WASTE OUTPUT"), blue("KEEP RCT DISABLED") }
        table.insert(ecam, { color = colors.red, text = "REACTOR WASTE LEAK", help = "ReactorWasteLeak", items = items})
    end

    if tripped(unit.alarms[ALARM.ReactorHighWaste]) then
        local items = { blue("CHECK WASTE OUTPUT") }
        table.insert(ecam, { color = colors.yellow, text = "REACTOR WASTE HIGH", help = "ReactorHighWaste", items = items})
    end

    if tripped(unit.alarms[ALARM.RPSTransient]) then
        local items = {}
        local stat = unit.reactor_data.rps_status

        -- for k, _ in pairs(stat) do stat[k] = true end

        local function insert(cond, key, text, color) if cond[key] then table.insert(items, { text = text, help = key, color = color }) end end

        table.insert(items, white("REACTOR SCRAMMED"))
        insert(stat, "high_dmg", "HIGH DAMAGE", colors.red)
        insert(stat, "high_temp", "HIGH TEMPERATURE", colors.red)
        insert(stat, "low_cool", "CRIT LOW COOLANT")
        insert(stat, "ex_waste", "EXCESS WASTE")
        insert(stat, "ex_hcool", "EXCESS HEATED COOL")
        insert(stat, "no_fuel", "NO FUEL")
        insert(stat, "fault", "HARDWARE FAULT")
        insert(stat, "timeout", "SUPERVISOR DISCONN")
        insert(stat, "manual", "MANUAL SCRAM", colors.white)
        insert(stat, "automatic", "AUTOMATIC SCRAM")
        insert(stat, "sys_fail", "NOT FORMED", colors.red)
        insert(stat, "force_dis", "FORCE DISABLED", colors.red)
        table.insert(items, blue("RESOLVE PROBLEM"))
        table.insert(items, blue("RESET RPS"))

        table.insert(ecam, { color = colors.yellow, text = "RPS TRANSIENT", help = "RPSTransient", items = items})
    end

    if tripped(unit.alarms[ALARM.RCSTransient]) then
        local items = {}
        local annunc = unit.annunciator

        -- for k, v in pairs(annunc) do
        --     if type(v) == "boolean" then annunc[k] = true end
        --     if type(v) == "table" then
        --         for a, _ in pairs(v) do
        --             v[a] = true
        --         end
        --     end
        -- end

        local function insert(cond, key, text, color)
            if cond == true or (type(cond) == "table" and cond[key]) then table.insert(items, { text = text, help = key, color = color }) end
        end

        table.insert(items, white("COOLANT PROBLEM"))

        insert(annunc, "RCPTrip", "RCP TRIP", colors.red)
        insert(annunc, "CoolantLevelLow", "LOW COOLANT")

        if unit.num_boilers == 0 then
            if (util.time_ms() - unit.last_rate_change_ms) > const.FLOW_STABILITY_DELAY_MS then
                insert(annunc, "BoilRateMismatch", "BOIL RATE MISMATCH")
            end

            if unit.turbine_flow_stable then
                insert(annunc, "RCSFlowLow", "RCS FLOW LOW")
                insert(annunc, "CoolantFeedMismatch", "COOL FEED MISMATCH")
                insert(annunc, "SteamFeedMismatch", "STM FEED MISMATCH")
            end
        else
            if (util.time_ms() - unit.last_rate_change_ms) > const.FLOW_STABILITY_DELAY_MS then
                insert(annunc, "RCSFlowLow", "RCS FLOW LOW")
                insert(annunc, "BoilRateMismatch", "BOIL RATE MISMATCH")
                insert(annunc, "CoolantFeedMismatch", "COOL FEED MISMATCH")
            end

            if unit.turbine_flow_stable then
                insert(annunc, "SteamFeedMismatch", "STM FEED MISMATCH")
            end
        end

        insert(annunc, "MaxWaterReturnFeed", "MAX WTR RTRN FEED")

        for k, v in ipairs(annunc.WaterLevelLow) do insert(v, "WaterLevelLow", "BOILER " .. k .. " WTR LOW", colors.red) end
        for k, v in ipairs(annunc.HeatingRateLow) do insert(v, "HeatingRateLow", "BOILER " .. k .. " HEAT RATE") end
        for k, v in ipairs(annunc.TurbineOverSpeed) do insert(v, "TurbineOverSpeed", "TURBINE " .. k .. " OVERSPD", colors.red) end
        for k, v in ipairs(annunc.GeneratorTrip) do insert(v, "GeneratorTrip", "TURBINE " .. k .. " GEN TRIP") end

        table.insert(items, blue("CHECK COOLING SYS"))

        table.insert(ecam, { color = colors.yellow, text = "RCS TRANSIENT", help = "RCSTransient", items = items})
    end

    if tripped(unit.alarms[ALARM.TurbineTrip]) then
        local items = {}

        for k, v in ipairs(unit.annunciator.TurbineTrip) do
            if v then table.insert(items, { text = "TURBINE " .. k .. " TRIP", help = "TurbineTrip" }) end
        end

        table.insert(items, blue("CHECK ENERGY OUT"))
        table.insert(ecam, { color = colors.red, text = "TURBINE TRIP", help = "TurbineTripAlarm", items = items})
    end

    if not (tripped(unit.alarms[ALARM.ReactorLost]) or unit.connected) then
        local items = { blue("CHECK PLC") }
        table.insert(ecam, { color = colors.yellow, text = "REACTOR OFF-LINE", items = items })
    end

    for k, v in ipairs(unit.annunciator.BoilerOnline) do
        if not v then
            local items = { blue("CHECK RTU") }
            table.insert(ecam, { color = colors.yellow, text = "BOILER " .. k .. " OFF-LINE", items = items})
        end
    end

    for k, v in ipairs(unit.annunciator.TurbineOnline) do
        if not v then
            local items = { blue("CHECK RTU") }
            table.insert(ecam, { color = colors.yellow, text = "TURBINE " .. k .. " OFF-LINE", items = items})
        end
    end

    -- if no alarms, put some basic status messages in
    if #ecam == 0 then
        table.insert(ecam, { color = colors.green, text = "REACTOR " .. util.trinary(unit.reactor_data.mek_status.status, "NOMINAL", "IDLE"), items = {}})

        local plural = util.trinary(unit.num_turbines > 1, "S", "")
        table.insert(ecam, { color = colors.green, text = "TURBINE" .. plural .. util.trinary(unit.turbine_flow_stable, " STABLE", " STABILIZING"), items = {}})
    end

    unit.unit_ps.publish("U_ECAM", textutils.serialize(ecam))

    --#endregion
end

-- update control app with unit data from API_GET_CTRL
---@param data table
function iorx.record_control_data(data)
    for u_id = 1, #data do
        local unit = io.units[u_id]
        local u_data = data[u_id]

        unit.connected = u_data[1]

        unit.reactor_data.rps_tripped = u_data[2]
        unit.unit_ps.publish("rps_tripped", u_data[2])
        unit.reactor_data.mek_status.status = u_data[3]
        unit.unit_ps.publish("status", u_data[3])
        unit.reactor_data.mek_status.temp = u_data[4]
        unit.unit_ps.publish("temp", u_data[4])
        unit.reactor_data.mek_status.burn_rate = u_data[5]
        unit.unit_ps.publish("burn_rate", u_data[5])
        unit.reactor_data.mek_status.act_burn_rate = u_data[6]
        unit.unit_ps.publish("act_burn_rate", u_data[6])
        unit.reactor_data.mek_struct.max_burn = u_data[7]
        unit.unit_ps.publish("max_burn", u_data[7])

        unit.annunciator.AutoControl = u_data[8]
        unit.unit_ps.publish("AutoControl", u_data[8])

        unit.a_group = u_data[9]
        unit.unit_ps.publish("auto_group_id", unit.a_group)
        unit.unit_ps.publish("auto_group", types.AUTO_GROUP_NAMES[unit.a_group + 1])

        local control_status = 1

        if unit.connected then
            if unit.reactor_data.rps_tripped then
                control_status = 2
            end

            if unit.reactor_data.mek_status.status then
                control_status = util.trinary(unit.annunciator.AutoControl, 4, 3)
            end
        end

        unit.unit_ps.publish("U_ControlStatus", control_status)
    end
end

-- update process app with unit data from API_GET_PROC
---@param data table
function iorx.record_process_data(data)
    -- get unit data
    for u_id = 1, #io.units do
        local unit = io.units[u_id]
        local u_data = data[u_id]

        unit.reactor_data.mek_status.status = u_data[1]
        unit.reactor_data.mek_struct.max_burn = u_data[2]
        unit.annunciator.AutoControl = u_data[6]
        unit.a_group = u_data[7]

        unit.unit_ps.publish("status", u_data[1])
        unit.unit_ps.publish("max_burn", u_data[2])
        unit.unit_ps.publish("burn_limit", u_data[3])
        unit.unit_ps.publish("U_AutoReady", u_data[4])
        unit.unit_ps.publish("U_AutoDegraded", u_data[5])
        unit.unit_ps.publish("AutoControl", u_data[6])
        unit.unit_ps.publish("auto_group_id", unit.a_group)
        unit.unit_ps.publish("auto_group", types.AUTO_GROUP_NAMES[unit.a_group + 1])
    end

    -- get facility data
    local fac = io.facility
    local f_data = data[#io.units + 1]

    fac.status_lines = f_data[1]

    fac.auto_ready = f_data[2][1]
    fac.auto_active = f_data[2][2]
    fac.auto_ramping = f_data[2][3]
    fac.auto_saturated = f_data[2][4]

    fac.auto_scram = f_data[3]
    fac.ascram_status = f_data[4]

    fac.ps.publish("status_line_1", fac.status_lines[1])
    fac.ps.publish("status_line_2", fac.status_lines[2])

    fac.ps.publish("auto_ready", fac.auto_ready)
    fac.ps.publish("auto_active", fac.auto_active)
    fac.ps.publish("auto_ramping", fac.auto_ramping)
    fac.ps.publish("auto_saturated", fac.auto_saturated)

    fac.ps.publish("auto_scram", fac.auto_scram)
    fac.ps.publish("as_matrix_fault", fac.ascram_status.matrix_fault)
    fac.ps.publish("as_matrix_fill", fac.ascram_status.matrix_fill)
    fac.ps.publish("as_crit_alarm", fac.ascram_status.crit_alarm)
    fac.ps.publish("as_radiation", fac.ascram_status.radiation)
    fac.ps.publish("as_gen_fault", fac.ascram_status.gen_fault)

    fac.ps.publish("process_mode", f_data[5][1])
    fac.ps.publish("process_burn_target", f_data[5][2])
    fac.ps.publish("process_charge_target", f_data[5][3])
    fac.ps.publish("process_gen_target", f_data[5][4])
end

-- update waste app with unit data from API_GET_WASTE
---@param data table
function iorx.record_waste_data(data)
    -- get unit data
    for u_id = 1, #io.units do
        local unit = io.units[u_id]
        local u_data = data[u_id]

        unit.waste_mode = u_data[1]
        unit.waste_product = u_data[2]
        unit.num_snas = u_data[3]
        unit.sna_peak_rate = u_data[4]
        unit.sna_max_rate = u_data[5]
        unit.sna_out_rate = u_data[6]
        unit.waste_stats = u_data[7]

        unit.unit_ps.publish("U_AutoWaste", unit.waste_mode == types.WASTE_MODE.AUTO)
        unit.unit_ps.publish("U_WasteMode", unit.waste_mode)
        unit.unit_ps.publish("U_WasteProduct", unit.waste_product)

        unit.unit_ps.publish("sna_count", unit.num_snas)
        unit.unit_ps.publish("sna_peak_rate", unit.sna_peak_rate)
        unit.unit_ps.publish("sna_max_rate", unit.sna_max_rate)
        unit.unit_ps.publish("sna_out_rate", unit.sna_out_rate)

        unit.unit_ps.publish("pu_rate", unit.waste_stats[1])
        unit.unit_ps.publish("po_rate", unit.waste_stats[2])
        unit.unit_ps.publish("po_pl_rate", unit.waste_stats[3])
    end

    -- get facility data
    local fac = io.facility
    local f_data = data[#io.units + 1]

    fac.auto_current_waste_product = f_data[1]
    fac.auto_pu_fallback_active = f_data[2]
    fac.auto_sps_disabled = f_data[3]

    fac.ps.publish("current_waste_product", fac.auto_current_waste_product)
    fac.ps.publish("pu_fallback_active", fac.auto_pu_fallback_active)
    fac.ps.publish("sps_disabled_low_power", fac.auto_sps_disabled)

    fac.ps.publish("process_waste_product", f_data[4])
    fac.ps.publish("process_pu_fallback", f_data[5])
    fac.ps.publish("process_sps_low_power", f_data[6])

    fac.waste_stats = f_data[7]

    fac.ps.publish("burn_sum", fac.waste_stats[1])
    fac.ps.publish("pu_rate", fac.waste_stats[2])
    fac.ps.publish("po_rate", fac.waste_stats[3])
    fac.ps.publish("po_pl_rate", fac.waste_stats[4])
    fac.ps.publish("po_am_rate", fac.waste_stats[5])
    fac.ps.publish("spent_waste_rate", fac.waste_stats[6])

    fac.sps_ps_tbl[1].publish("SPSStateStatus", f_data[8])
    fac.ps.publish("sps_process_rate", f_data[9])
end


-- update facility app with facility and unit data from API_GET_FAC_DTL
---@param data table
function iorx.record_fac_detail_data(data)
    local fac = io.facility

    local tank_statuses = data[5]
    local next_t_stat = 1

    -- annunciator

    fac.all_sys_ok = data[1]
    fac.rtu_count = data[2]
    fac.auto_scram = data[3]
    fac.ascram_status = data[4]

    fac.ps.publish("all_sys_ok", fac.all_sys_ok)
    fac.ps.publish("rtu_count", fac.rtu_count)
    fac.ps.publish("auto_scram", fac.auto_scram)
    fac.ps.publish("as_matrix_fault", fac.ascram_status.matrix_fault)
    fac.ps.publish("as_matrix_fill", fac.ascram_status.matrix_fill)
    fac.ps.publish("as_crit_alarm", fac.ascram_status.crit_alarm)
    fac.ps.publish("as_radiation", fac.ascram_status.radiation)
    fac.ps.publish("as_gen_fault", fac.ascram_status.gen_fault)

    -- unit data

    local units = data[12]

    for i = 1, io.facility.num_units do
        local unit = io.units[i]
        local u_rx = units[i]

        unit.connected    = u_rx[1]
        unit.annunciator  = u_rx[2]
        unit.reactor_data = u_rx[3]

        local control_status = 1
        if unit.connected then
            if unit.reactor_data.rps_tripped then control_status = 2 end
            if unit.reactor_data.mek_status.status then
                control_status = util.trinary(unit.annunciator.AutoControl, 4, 3)
            end
        end

        unit.unit_ps.publish("U_ControlStatus", control_status)

        unit.tank_data_tbl = u_rx[4]

        for id = 1, #unit.tank_data_tbl do
            local tank   = unit.tank_data_tbl[id]
            local ps     = unit.tank_ps_tbl[id]
            local c_stat = tank_statuses[next_t_stat]

            local tank_status = 1

            if c_stat ~= TNK_STATE.OFFLINE then
                if c_stat == TNK_STATE.FAULT then
                    tank_status = 3
                elseif tank.formed then
                    tank_status = 4
                else
                    tank_status = 2
                end
            end

            ps.publish("DynamicTankStatus", tank_status)
            ps.publish("DynamicTankStateStatus", c_stat)

            next_t_stat = next_t_stat + 1
        end
    end

    -- facility dynamic tank data

    fac.tank_data_tbl = data[6]

    for id = 1, #fac.tank_data_tbl do
        local tank   = fac.tank_data_tbl[id]
        local ps     = fac.tank_ps_tbl[id]
        local c_stat = tank_statuses[next_t_stat]

        local tank_status = 1

        if c_stat ~= TNK_STATE.OFFLINE then
            if c_stat == TNK_STATE.FAULT then
                tank_status = 3
            elseif tank.formed then
                tank_status = 4
            else
                tank_status = 2
            end

            _record_multiblock_status(c_stat == TNK_STATE.FAULT, tank, ps)
        end

        ps.publish("DynamicTankStatus", tank_status)
        ps.publish("DynamicTankStateStatus", c_stat)

        next_t_stat = next_t_stat + 1
    end

    -- induction matrix data

    fac.induction_data_tbl[1] = data[8]

    local matrix = fac.induction_data_tbl[1]
    local m_ps   = fac.induction_ps_tbl[1]
    local m_stat = data[7]

    local mtx_status = 1

    if m_stat ~= MTX_STATE.OFFLINE then
        if m_stat == MTX_STATE.FAULT then
            mtx_status = 3
        elseif matrix.formed then
            mtx_status = 4
        else
            mtx_status = 2
        end

        _record_multiblock_status(m_stat == MTX_STATE.FAULT, matrix, m_ps)
    end

    m_ps.publish("InductionMatrixStatus", mtx_status)
    m_ps.publish("InductionMatrixStateStatus", m_stat)

    m_ps.publish("eta_string", data[9][1])
    m_ps.publish("avg_charge", data[9][2])
    m_ps.publish("avg_inflow", data[9][3])
    m_ps.publish("avg_outflow", data[9][4])
    m_ps.publish("is_charging", data[9][5])
    m_ps.publish("is_discharging", data[9][6])
    m_ps.publish("at_max_io", data[9][7])

    -- sps data

    fac.sps_data_tbl[1] = data[11]

    local sps    = fac.sps_data_tbl[1]
    local s_ps   = fac.sps_ps_tbl[1]
    local s_stat = data[10]

    local sps_status = 1

    if s_stat ~= SPS_STATE.OFFLINE then
        if s_stat == SPS_STATE.FAULT then
            sps_status = 3
        elseif sps.formed then
            sps_status = 4
        else
            sps_status = 2
        end

        _record_multiblock_status(s_stat == SPS_STATE.FAULT, sps, s_ps)
    end

    s_ps.publish("SPSStatus", sps_status)
    s_ps.publish("SPSStateStatus", s_stat)
end

return function (io_obj)
    io = io_obj
    return iorx
end
