local const   = require("scada-common.constants")

local docs = {}

---@enum DOC_LIST_TYPE
local DOC_LIST_TYPE = {
    BULLET = 1,
    NUMBERED = 2,
    INDICATOR = 3,
    LED = 4
}

docs.DOC_LIST_TYPE = DOC_LIST_TYPE

local target

---@param key string item identifier for linking
---@param name string item name for display
---@param desc string text body
local function doc(key, name, desc)
    ---@class pocket_doc_item
    local item = { key = key, name = name, desc = desc }
    table.insert(target, item)
end

---@param type DOC_LIST_TYPE
---@param items table
---@param colors table|nil colors for indicators or nil for normal lists
local function list(type, items, colors)
    ---@class pocket_doc_list
    local list_def = { type = type, items = items, colors = colors }
    table.insert(target, list_def)
end

-- important to note in the future: The PLC should always be in a chunk with the reactor to ensure it can protect it on chunk load if you do not keep it all chunk loaded

docs.alarms = {}

target = docs.alarms
doc("ContainmentBreach", "Containment Breach", "Reactor disconnected or indicated unformed while being at or above 100% damage; explosion assumed.")
doc("ContainmentRadiation", "Containment Radiation", "Environment detector(s) assigned to the unit have observed high levels of radiation.")
doc("ReactorLost", "Reactor Lost", "Reactor PLC has stopped communicating with the supervisor.")
doc("CriticalDamage", "Damage Critical", "Reactor damage has reached or exceeded 100%, so it will explode at any moment.")
doc("ReactorDamage", "Reactor Damage", "Reactor temperature causing increasing damage to the reactor casing.")
doc("ReactorOverTemp", "Reactor Over Temp", "Reactor temperature is at or above maximum safe temperature, so it is now taking damage.")
doc("ReactorHighTemp", "Reactor High Temp", "Reactor temperature is above expected operating levels and may exceed maximum safe temperature soon.")
doc("ReactorWasteLeak", "Reactor Waste Leak", "The reactor is full of spent waste so it will now emit radiation if additional waste is generated.")
doc("ReactorHighWaste", "Reactor High Waste", "Reactor waste levels are high and may leak soon.")
doc("RPSTransient", "RPS Transient", "Reactor protection system was activated.")
doc("RCSTransient", "RCS Transient", "Something is wrong with the reactor coolant system, check RCS indicators for details.")
doc("TurbineTripAlarm", "Turbine Trip", "A turbine stopped rotating, likely due to having full energy storage. This will prevent cooling, so it needs to be resolved before using that unit.")

docs.annunc = {
    unit = {
        main_section = {}, rps_section = {}, rcs_section = {}
    },
    facility = {
        main_section = {}
    }
}

target = docs.annunc.unit.main_section
doc("PLCOnline", "PLC Online", "Indicates if the fission reactor PLC is connected. If it isn't, check that your PLC is on and configured properly.")
doc("PLCHeartbeat", "PLC Heartbeat", "An indicator of status data being live. As status messages are received from the PLC, this light will turn on and off. If it gets stuck, the supervisor has stopped receiving data or a screen has frozen.")
doc("RadiationMonitor", "Radiation Monitor", "On if at least one environment detector is connected and assigned to this unit.")
doc("AutoControl", "Automatic Control", "On if the reactor is under the control of one of the automatic control modes.")
doc("ReactorSCRAM", "Reactor SCRAM", "On if the reactor protection system is holding the reactor SCRAM'd.")
doc("ManualReactorSCRAM", "Manual Reactor SCRAM", "On if the operator (you) initiated a SCRAM.")
doc("AutoReactorSCRAM", "Auto Reactor SCRAM", "On if the automatic control system initiated a SCRAM. The main view screen annunciator will have an indication as to why.")
doc("RadiationWarning", "Radiation Warning", "On if radiation levels are above normal. There is likely a leak somewhere, so that should be identified and fixed. Hazmat suit recommended.")
doc("RCPTrip", "RCP Trip", "Reactor coolant pump tripped. This is a technical concept not directly mapping to Mekansim. Here, it indicates if there is either high heated coolant or low cooled coolant that caused an RPS trip. Check the coolant system if this occurs.")
doc("RCSFlowLow", "RCS Flow Low", "Indicates if the reactor coolant system flow is low. This is observed when the cooled coolant level in the reactor is dropping. This can occur while a turbine spins up, but if it persists, check that the cooling system is operating properly. This can occur with smaller boilers or when using pipes and not having enough.")
doc("CoolantLevelLow", "Coolant Level Low", "On if the reactor coolant level is lower than it should be. Check the coolant system.")
doc("ReactorTempHigh", "Reactor Temp. High", "On if the reactor temperature is above expected maximum operating temperature. This is not yet damaging, but should be attended to. Check coolant system.")
doc("ReactorHighDeltaT", "Reactor High Delta T", "On if the reactor temperature is climbing rapidly. This can occur when a reactor is starting up, but it is a concern if it happens while the burn rate is not increasing.")
doc("FuelInputRateLow", "Fuel Input Rate Low", "On if the fissile fuel levels in the reactor are dropping or very low. Ensure a steady supply of fuel is entering the reactor.")
doc("WasteLineOcclusion", "Waste Line Occlusion", "Waste levels in the reactor are increasing. Ensure your waste processing system is operating at a sufficient rate for your burn rate.")
doc("HighStartupRate", "Startup Rate High", "This is a rough calculation of if your burn rate is high enough to cause a loss of coolant on startup. A burn rate above this is likely to cause that, but it could occur at even higher or even lower rates depending on your setup (such as pipes, water supplies, and boiler tanks).")

target = docs.annunc.unit.rps_section
doc("rps_tripped", "RPS Trip", "Indicates if the reactor protection system has caused a SCRAM.")
doc("manual", "Manual Reactor SCRAM", "Indicates if the operator (you) tripped the RPS by pressing SCRAM.")
doc("automatic", "Auto Reactor SCRAM", "Indicates if the automatic control system tripped the RPS.")
doc("high_dmg", "Damage Level High", "Indicates if the RPS tripped due to significant reactor damage. Await damage levels to lower.")
doc("ex_waste", "Excess Waste", "Indicates if the RPS tripped due to very high waste levels. Ensure waste processing system is keeping up.")
doc("ex_hcool", "Excess Heated Coolant", "Indicates if the RPS tripped due to very high heated coolant levels. Check that the cooling system is able to keep up with heated coolant flow.")
doc("high_temp", "Temperature High", "Indicates if the RPS tripped due to reaching damaging temperatures. Await damage levels to lower.")
doc("low_cool", "Coolant Level Low Low", "Indicates if the RPS tripped due to very low coolant levels that result in the temperature uncontrollably rising. Ensure that the cooling system can provide sufficient cooled coolant flow.")
doc("no_fuel", "No Fuel", "Indicates if the RPS tripped due to no fuel being available. Check fuel input.")
doc("fault", "PPM Fault", "Indicates if the RPS tripped due to a peripheral access fault. Something went wrong interfacing with the reactor, try restarting the PLC.")
doc("timeout", "Connection Timeout", "Indicates if the RPS tripped due to losing connection with the supervisory computer. Check that your PLC and supervisor remain chunk loaded.")
doc("sys_fail", "System Failure", "Indicates if the RPS tripped due to the reactor not being formed. Ensure that the multi-block is formed.")

target = docs.annunc.unit.rcs_section
doc("RCSFault", "RCS Hardware Fault", "Indicates if one or more of the RCS devices have a peripheral fault. Check that your machines are formed. If this persists, try rebooting affected RTUs.")
doc("EmergencyCoolant", "Emergency Coolant", "Off if no emergency coolant redstone is configured, white when it is configured but not in use, and green/blue when it is activated. This is based on an RTU having a redstone emergency coolant output configured for this unit.")
doc("CoolantFeedMismatch", "Coolant Feed Mismatch", "The coolant system is accumulating heated coolant or losing cooled coolant, likely due to one of the machines not keeping up with the needs of the reactor. The flow monitor can help figure out where the problem is.")
doc("BoilRateMismatch", "Boil Rate Mismatch", "The total heating rate of the reactor exceed the tolerance from the steam input rate of the turbines OR for sodium setups, the boiler boil rates exceed the tolerance from the steam input rate of the turbines. The flow monitor can help figure out where the problem is.")
doc("SteamFeedMismatch", "Steam Feed Mismatch", "There is an above tolerance difference between turbine flow and steam input rates or the reactor/boilers are gaining steam or losing water. The flow monitor can help figure out where the problem is.")
doc("MaxWaterReturnFeed", "Max Water Return Feed", "The turbines are condensing the max rate of water that they can per the structure build. If water return is insufficient, add more saturating condensers to your turbine(s).")
doc("WaterLevelLow", "Water Level Low", "The water level in the boiler is low. A larger boiler water tank may help, or you can feed additional water into the boiler from elsewhere.")
doc("HeatingRateLow", "Heating Rate Low", "The boiler is not hot enough to boil water, but it is receiving heated coolant. This is almost never a safety concern.")
doc("SteamDumpOpen", "Steam Relief Valve Open", "This turns yellow if the turbine is set to dumping excess and red if it is set to dumping [all]. 'Relief Valve' in this case is that setting allowing the venting of steam. You should never have this set to dumping [all]. Emergency coolant activation from the supervisor will automatically set it to dumping excess to ensure there is no backup of steam as water is added.")
doc("TurbineOverSpeed", "Turbine Over Speed", "The turbine is at steam capacity, but not tripped. You may need more turbines if they can't keep up.")
doc("GeneratorTrip", "Generator Trip", "The turbine is no longer outputting power due to it having nowhere to go. Likely due to full power storage. This will lead to a Turbine Trip if not addressed.")
doc("TurbineTrip", "Turbine Trip", "The turbine has reached its maximum power charge and has stopped rotating, and as a result stopped cooling steam to water. Ensure the turbine has somewhere to output power, as this is the most common cause of reactor meltdowns. However, the likelihood of a meltdown with this system in place is much lower, especially with emergency coolant helping during turbine trips.")

target = docs.annunc.facility.main_section
doc("all_sys_ok", "Unit Systems Online", "All unit systems (reactors, boilers, and turbines) are connected.")
doc("rad_computed_status", "Radiation Monitor", "At least one facility radiation monitor is connected")
doc("im_computed_status", "Induction Matrix", "The induction matrix is connected.")
doc("sps_computed_status", "SPS Connected", "Indicates if the super-critical phase shifter is connected.")
doc("auto_ready", "Configured Units Ready", "All units assigned to automatic control are ready to run automatic control.")
doc("auto_active", "Process Active", "Automatic process control is active.")
doc("auto_ramping", "Process Ramping", "Automatic process control is performing an initial ramp-up of the reactors for later PID control (generation and charge mode).")
doc("auto_saturated", "Min/Max Burn Rate", "Auto control has either commanded 0 mB/t or the maximum total burn rate available (from assigned units).")
doc("auto_scram", "Automatic SCRAM", "Automatic control system SCRAM'ed the assigned reactors due to a safety hazard, shown by the below indicators.")
doc("as_matrix_dc", "Matrix Disconnected", "Automatic SCRAM occurred due to loss of induction matrix connection.")
doc("as_matrix_fill", "Matrix Charge High", "Automatic SCRAM occurred due to induction matrix charge exceeding acceptable limit.")
doc("as_crit_alarm", "Unit Critical Alarm", "Automatic SCRAM occurred due to critical level unit alarm(s).")
doc("as_radiation", "Facility Radiation High", "Automatic SCRAM occurred due to high facility radiation levels.")
doc("as_gen_fault", "Gen. Control Fault", "Automatic SCRAM occurred due to assigned units being degraded/no longer ready during generation mode. The system will automatically resume (starting with initial ramp) once the problem is resolved.")

docs.fp = {
    common = {}, r_plc = {}, rtu_gw = {}
}

--comp id "This must never be the identical between devices, and that can only happen if you duplicate a computer (such as middle-click on it and place it elsewhere in creative mode)."

target = docs.fp.common
doc("fp_status", "STATUS", "This is always lit, except on the Reactor PLC. For that, it is green once initialized and OK (has all its peripherals) and red if something is wrong, in which case you should refer to the other indicator lights.")
doc("fp_heartbeat", "HEARTBEAT", "This alternates between lit and unlit as the main loop on the device runs. If this freezes, something is wrong and the logs will indicate why.")
doc("fp_modem", "MODEM", "This lights up if the wireless/ender modem is connected. In parentheses is the unique computer ID of this device, which will show up in places such as the supervisor's connection lists.")
doc("fp_modem", "NETWORK", "This is present when in standard color modes and indicates the network status using multiple colors. Off is no link, green is linked, red is link denied, orange is mismatching comms versions, and yellow is Reactor PLC-specific, indicating a unit ID collision (duplicate unit IDs in use).")
list(DOC_LIST_TYPE.LED, { "not linked", "linked" }, { colors.gray, colors.green })
doc("fp_nt_linked", "NT LINKED", "(color accessibility modes only) This lights up once the device is linked to the supervisor.")
doc("fp_nt_version", "NT VERSION", "(color accessibility modes only) This lights up if the communications versions of the supervisor and this device do not match. Make sure everything is up-to-date.")
doc("fp_fw", "FW", "Firmware application version of this device.")
doc("fp_nt", "NT", "Network (comms) version this device has. These must match between devices in order for them to connect.")

target = docs.fp.r_plc
doc("fp_nt_collision", "NT COLLISION", "(color accessibility modes only) This lights up if the Reactor PLC reactor unit ID conflicts with (is a duplicate of) another already connected Reactor PLC.")
doc("fp_rplc_rt_main", "RT MAIN", "This lights up as long as the device's main loop co-routine is running, which it should be as long as STATUS is green.")
doc("fp_rplc_rt_rps", "RT RPS", "This should always be lit up if a reactor is connected as it indicates the RPS co-routine is running, otherwise safety checks will not be running.")
doc("fp_rplc_rt_ctx", "RT COMMS TX", "This should always be lit if the Reactor PLC is not running in standalone mode, as it indicates the communications transmission co-routine is running.")
doc("fp_rplc_rt_crx", "RT COMMS RX", "This should always be lit if the Reactor PLC is not running in standalone mode, as it indicates the communications receiver/handler co-routine is running.")
doc("fp_rplc_rt_spctl", "RT SPCTL", "This should always be lit if the Reactor PLC is not running in standalone mode, as it indicates the process setpoint controller co-routine is running.")
doc("fp_rct_active", "RCT ACTIVE", "The reactor is active (running).")
doc("fp_emer_cool", "EMER COOLANT", "This is only present if PLC-controlled emergency coolant is configured on that device. When lit, it indicates that it has been activated.")
doc("fp_rps_trip", "RPS TRIP", "Flashes when the RPS has SCRAM'd the reactor due to a safety trip.")
doc("fp_rps_man", "MANUAL", "The RPS was tripped manually (SCRAM by user, not via the Mekanism Reactor UI).")
doc("fp_rps_auto", "AUTOMATIC", "The RPS was tripped by the supervisor automatically.")
doc("fp_rps_to", "TIMEOUT", "The RPS tripped due to losing the supervisor connection.")
doc("fp_rps_pflt", "PLC FAULT", "The RPS tripped due to a peripheral error.")
doc("fp_rps_rflt", "RCT FAULT", "The RPS tripped due to the reactor not being formed.")
doc("fp_rps_temp", "HI DAMAGE", "The RPS tripped due to being >= " .. const.RPS_LIMITS.MAX_DAMAGE_PERCENT .. "% damaged.")
doc("fp_rps_temp", "HI TEMP", "The RPS tripped due to high reactor temperature (>= " .. const.RPS_LIMITS.MAX_DAMAGE_TEMPERATURE .. "K).")
doc("fp_rps_fuel", "LO FUEL", "The RPS tripped due to having no fuel.")
doc("fp_rps_waste", "HI WASTE", "The RPS tripped due to having high levels of waste (> " .. const.RPS_LIMITS.MAX_WASTE_FILL .. "%).")
doc("fp_rps_ccool", "LO CCOOLANT", "The RPS tripped due to having low levels of cooled coolant (< " .. const.RPS_LIMITS.MIN_COOLANT_FILL .. "%).")
doc("fp_rps_ccool", "HI HCOOLANT", "The RPS tripped due to having high levels of heated coolant (> " .. const.RPS_LIMITS.MAX_HEATED_COLLANT_FILL .. "%).")

target = docs.fp.rtu_gw
doc("fp_rtu_rt_main", "RT MAIN", "This indicates if the device's main loop co-routine is running.")
doc("fp_rtu_rt_comms", "RT COMMS", "This indicates if the communications handler co-routine is running.")
doc("fp_rtu_rt", "RT", "In each RTU entry row, an RT light indicates if the co-routine for that RTU unit is running. This is never lit for redstone units.")
doc("fp_rtu_rt", "Device Status", "In each RTU entry row, the light to the left of the device name indicates its peripheral status.")

docs.glossary = {
    abbvs = {}, terms = {}
}

target = docs.glossary.abbvs
doc("G_ACK", "ACK", "Alarm ACKnowledge. Pressing this acknowledges that you understand an alarm occurred and would like to stop the audio tone(s).")
doc("G_Auto", "Auto", "Automatic.")
doc("G_CRD", "CRD", "Coordinator. Abbreviation for the coordinator computer.")
doc("G_DBG", "DBG", "Debug. Abbreviation for the debugging sessions from pocket computers found on the supervisor's front panel.")
doc("G_FP", "FP", "Front Panel. See Terminology.")
doc("G_Hi", "Hi", "High.")
doc("G_Lo", "Lo", "Low.")
doc("G_PID", "PID", "A Proportional Integral Derivitave closed-loop controller.")
doc("G_PKT", "PKT", "Pocket. Abbreviation for the pocket computer.")
doc("G_PLC", "PLC", "Programmable Logic Controller. A device that not only reports data and controls outputs, but can also make decisions on its own.")
doc("G_PPM", "PPM", "Protected Peripheral Manager. This is an abstraction layer created for this project that prevents peripheral calls from crashing applications.")
doc("G_RCP", "RCP", "Reactor Coolant Pump. This is from real-world terminology with water-cooled (boiling water and pressurized water) reactors, but in this system it just reflects to the functioning of reactor coolant flow. See the annunciator page on it for more information.")
doc("G_RCS", "RCS", "Reactor Cooling System. The combination of all machines used to cool the reactor (turbines, boilers, dynamic tanks).")
doc("G_RPS", "RPS", "Reactor Protection System. A component of the reactor PLC responsible for keeping the reactor safe.")
doc("G_RTU", "RT", "co-RouTine. This is used to identify the status of core Lua co-routines on front panels.")
doc("G_RTU", "RTU", "Remote Terminal Unit. Provides monitoring to and basic output from a SCADA system, interfacing with various types of devices/interfaces.")
doc("G_SCADA", "SCADA", "Supervisory Control and Data Acquisition. A control systems architecture used in a wide variety process control applications.")
doc("G_SVR", "SVR", "Supervisor. Abbreviation for the supervisory computer.")
doc("G_UI", "UI", "User Interface.")

target = docs.glossary.terms
doc("G_AssignedUnit", "Assigned Unit", "A unit that is assigned to an automatic control group (not assigned to Manual).")
doc("G_Fault", "Fault", "Something has gone wrong and/or failed to function.")
doc("G_FrontPanel", "Front Panel", "A basic interface on the front of a device for viewing and sometimes modifying its state. This is what you see when looking at a computer running one of the SCADA applications.")
doc("G_HighHigh", "High High", "Very High.")
doc("G_LowLow", "Low Low", "Very Low.")
doc("G_Nominal", "Nominal", "Normal operation. Everything operating as intended.")
doc("G_Ringback", "Ringback", "An indication that an alarm had gone off but is no longer having its trip condition(s) met. This is to make you are aware that it occurred.")
doc("G_SCRAM", "SCRAM", "[Emergency] shut-down of a reactor by stopping the fission. In Mekanism and here, it isn't always for an emergency.")
doc("G_Transient", "Transient", "A temporary change in state from normal operation. Coolant levels dropping or core temperature rising above nominal values are examples of transients.")
doc("G_Trip", "Trip", "A checked condition had occurred, see 'Tripped'.")
doc("G_Tripped", "Tripped", "An alarm condition has been met, and is still met.")
doc("G_Tripping", "Tripping", "Alarm condition(s) is/are met, but has/have not reached the minimum time before the condition(s) is/are deemed a problem.")
doc("G_TurbineTrip", "Turbine Trip", "The turbine stopped, which prevents heated coolant from being cooled. In Mekanism, this would occur when a turbine cannot generate any more energy due to filling its buffer and having no output with any remaining energy capacity.")

return docs
