local docs = {}

local target

local function doc(key, name, desc)
    ---@class pocket_doc_item
    local item = { key = key, name = name, desc = desc }
    table.insert(target, item)
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

docs.glossary = {
    abbvs = {}, terms = {}
}

target = docs.glossary.abbvs
doc("G_ACK", "ACK", "Alarm ACKnowledge. Pressing this acknowledges that you understand an alarm occurred and would like to stop the audio tone(s).")
doc("G_CRD", "CRD", "Coordinator. Abbreviation for the coordinator computer.")
doc("G_DBG", "DBG", "Debug. Abbreviation for the debugging sessions from pocket computers found on the supervisor's front panel.")
doc("G_FP", "FP", "Front Panel. See Terminology.")
doc("G_PKT", "PKT", "Pocket. Abbreviation for the pocket computer.")
doc("G_PLC", "PLC", "Programmable Logic Controller. A device that not only reports data and controls outputs, but can also make decisions on its own.")
doc("G_PPM", "PPM", "Protected Peripheral Manager. This is an abstraction layer created for this project that prevents peripheral calls from crashing applications.")
doc("G_RCP", "RCP", "Reactor Coolant Pump. This is from real-world terminology with water-cooled (boiling water and pressurized water) reactors, but in this system it just reflects to the functioning of reactor coolant flow. See the annunciator page on it for more information.")
doc("G_RCS", "RCS", "Reactor Cooling System. The combination of all machines used to cool the reactor (turbines, boilers, dynamic tanks).")
doc("G_RPS", "RPS", "Reactor Protection System. A component of the reactor PLC responsible for keeping the reactor safe.")
doc("G_RTU", "RTU", "Remote Terminal Unit. Provides monitoring to and basic output from a SCADA system, interfacing with various types of devices/interfaces.")
doc("G_SCADA", "SCADA", "Supervisory Control and Data Acquisition. A control systems architecture used in a wide variety process control applications.")
doc("G_SVR", "SVR", "Supervisor. Abbreviation for the supervisory computer.")
doc("G_UI", "UI", "User Interface.")

target = docs.glossary.terms
doc("G_Fault", "Fault", "Something has gone wrong and/or failed to function.")
doc("G_FrontPanel", "Front Panel", "A basic interface on the front of a device for viewing and sometimes modifying its state. This is what you see when looking at a computer running one of the SCADA applications.")
doc("G_Nominal", "Nominal", "Normal operation. Everything operating as intended.")
doc("G_Ringback", "Ringback", "An indication that an alarm had gone off but is no longer having its trip condition(s) met. This is to make you are aware that it occurred.")
doc("G_SCRAM", "SCRAM", "[Emergency] shut-down of a reactor by stopping the fission. In Mekanism and here, it isn't always for an emergency.")
doc("G_Transient", "Transient", "A temporary change in state from normal operation. Coolant levels dropping or core temperature rising above nominal values are examples of transients.")
doc("G_Trip", "Trip", "A checked condition had occurred, see 'Tripped'.")
doc("G_Tripped", "Tripped", "An alarm condition has been met, and is still met.")
doc("G_Tripping", "Tripping", "Alarm condition(s) is/are met, but has/have not reached the minimum time before the condition(s) is/are deemed a problem.")
doc("G_TurbineTrip", "Turbine Trip", "The turbine stopped, which prevents heated coolant from being cooled. In Mekanism, this would occur when a turbine cannot generate any more energy due to filling its buffer and having no output with any remaining energy capacity.")

return docs
