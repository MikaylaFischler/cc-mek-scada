local docs = {}

local target

local function doc(key, name, desc)
    ---@class pocket_doc_item
    local item = { key = key, name = name, desc = desc }
    table.insert(target, item)
end

docs.alarms = {}

target = docs.alarms
doc("ContainmentBreach", "Containment Breach", "Reactor disconnected or indicated unformed while being at or above 100% damage; explosion likely occurred.")
doc("ContainmentRadiation", "Containment Radiation", "Environment detector(s) assigned to the unit have observed high levels of radiation.")
doc("ReactorLost", "Reactor Lost", "Reactor PLC has stopped communicating with the supervisor.")
doc("CriticalDamage", "Damage Critical", "Reactor damage has reached or exceeded 100%, so it may explode at any moment.")
doc("ReactorDamage", "Reactor Damage", "Reactor temperature causing increasing damage to reactor casing.")
doc("ReactorOverTemp", "Reactor Over Temp", "Reactor temperature is at or above maximum safe temperature and is now taking damage.")
doc("ReactorHighTemp", "Reactor High Temp", "Reactor temperature is above expected operating levels and may exceed maximum safe temperature soon.")
doc("ReactorWasteLeak", "Reactor Waste Leak", "The reactor is full of spent waste and will now emit radiation if additional waste is generated.")
doc("ReactorHighWaste", "Reactor High Waste", "Reactor waste levels are high and may leak soon.")
doc("RPSTransient", "RPS Transient", "Reactor protection system was activated.")
doc("RCSTransient", "RCS Transient", "Something is wrong with the reactor coolant system, check RCS indicators.")
doc("TurbineTripAlarm", "Turbine Trip", "A turbine stopped rotating, likely due to having full energy storage.")

docs.annunc = {
    unit = {
        main_section = {}, rps_section = {}, rcs_section = {}
    }
}

target = docs.annunc.unit.main_section
doc("PLCOnline", "PLC Online", "Indicates if the fission reactor PLC is connected.")
doc("PLCHeartbeat", "PLC Heartbeat", "An indicator of status data being live. As status messages are received from the PLC, this light will turn on and off. If it gets stuck, the supervisor has stopped receiving data.")
doc("RadiationMonitor", "Radiation Monitor", "Indicates if at least once environment detector is connected and assigned to this unit.")
doc("AutoControl", "Automatic Control", "Indicates if the reactor is under the control of one of the automatic control modes.")
doc("ReactorSCRAM", "Reactor SCRAM", "Indicates if the reactor protection system is holding the reactor SCRAM'd.")
doc("ManualReactorSCRAM", "Manual Reactor SCRAM", "Indicates if the operator (you) initiated a SCRAM.")
doc("AutoReactorSCRAM", "Auto Reactor SCRAM", "Indicates if the automatic control system initiated a SCRAM. The main view screen will have an indicator as to why.")
doc("RadiationWarning", "Radiation Warning", "Indicates if radiation levels are above normal. There is likely a leak somewhere, so that should be identified and fixed.")
doc("RCPTrip", "RCP Trip", "Reactor coolant pump tripped. This is a technical concept not directly mapping to mekansim, so in this case it indicates if there is either high heated coolant or low cooled coolant causing an RPS trip. Check the coolant system if this occurs.")
doc("RCSFlowLow", "RCS Flow Low", "Indicates if the reactor coolant system flow is low. This is observed when the cooled coolant level in the reactor is dropping. This can occur while a turbine spins up, but if it persists, check that the cooling system is operating properly.")
doc("CoolantLevelLow", "Coolant Level Low", "Indicates if the reactor coolant level is lower than it should be. Check the coolant system.")
doc("ReactorTempHigh", "Reactor Temp. High", "Indicates if the reactor temperature is above expected maximum operating temperature. This is not yet damaging, but should be attended to. Check coolant system.")
doc("ReactorHighDeltaT", "Reactor High Delta T", "Indicates if the reactor temperature is climbing rapidly. This can occur when a reactor is starting up, but it is a concern if it happens uncontrolled while the burn rate is not increasing.")
doc("FuelInputRateLow", "Fuel Input Rate Low", "Indicates if the fissile fuel levels in the reactor are dropping or are very low. Ensure a steady supply of fuel is entering the reactor.")
doc("WasteLineOcclusion", "Waste Line Occlusion", "Waste levels in the reactor are increasing. Ensure your waste processing system is operating at a sufficient rate for your burn rate.")
doc("HighStartupRate", "Startup Rate High", "This is a rough calculation of if your burn rate is high enough to cause a loss of coolant. A burn rate above this is likely to cause that, but it could occur at even higher or even lower rates depending on your setup (such as pipes, water supplies, and boiler tanks).")

target = docs.annunc.unit.rps_section
doc("rps_tripped", "RPS Trip", "Indicates if the reactor protection system has caused a SCRAM.")
doc("high_dmg", "Damage Level High", "Indicates if the RPS tripped due to significant reactor damage.")

target = docs.annunc.unit.main_section

docs.glossary = {
    abbvs = {}, terms = {}
}

target = docs.glossary.abbvs
doc("G_ACK", "ACK", "Alarm ACKnowledge. This indicates you understand an alarm occured and would like to stop the audio tone(s).")
doc("G_CRD", "CRD", "Coordinator. Abbreviation for the coordinator computer.")
doc("G_DBG", "DBG", "Debug. Abbreviation for the debugging sessions from pocket computers found on the supervisor's front panel.")
doc("G_PKT", "PKT", "Pocket. Abbreviation for the pocket computer.")
doc("G_PLC", "PLC", "Programmable Logic Controller. A device that not only reports data and controls outputs, but also can make decisions on its own.")
doc("G_PPM", "PPM", "Protected Peripheral Manager. This is an abstraction layer created for this project that prevents peripheral calls from crashing applications.")
doc("G_RCP", "RCP", "Reactor Coolant Pump. This is from real-world terminology with water-cooled reactors, but in this system it just relates to the functioning of reactor coolant flow.")
doc("G_RCS", "RCS", "Reactor Cooling System. The combination of all machines used to cool the reactor.")
doc("G_RPS", "RPS", "Reactor Protection System. A component of the reactor PLC responsible for keeping the reactor safe.")
doc("G_RTU", "RTU", "Remote Terminal Unit. Provides monitoring to and basic output from a SCADA system, interfacing with various types of devices/controls.")
doc("G_SCADA", "SCADA", "Supervisory Control and Data Acquisition. A control systems architecture used in many different process control applications.")
doc("G_SVR", "SVR", "Supervisor. Abbreviation for the supervisory computer.")

target = docs.glossary.terms
doc("G_Fault", "Fault", "Something has gone wrong and/or failed to function.")
doc("G_FrontPanel", "Front Panel", "A basic interface on the front of a device for viewing and sometimes modifying its state. This is what you see when looking at a computer running one of the SCADA applications.")
doc("G_Nominal", "Nominal", "Normal operation. Everything operating as intended.")
doc("G_Ringback", "Ringback", "An indication that an alarm had gone off so that you are aware, even if the alarm condition is no longer met.")
doc("G_SCRAM", "SCRAM", "[Emergency] shut-down of a reactor by stopping the fission reactor. In Mekanism and here, it isn't always for an emergency.")
doc("G_Transient", "Transient", "A temporary change in state from normal operation. Coolant levels dropping or core temperature rising above nominal values would be examples of transients.")
doc("G_Trip", "Trip", "A checked condition has occurred, also known as 'tripped'.")
doc("G_Tripped", "Tripped", "An alarm condition has been met and is still met.")
doc("G_Tripping", "Tripping", "An alarm condition is met but has not met the minimum time before a condition is deemed a problem.")
doc("G_TurbineTrip", "Turbine Trip", "The turbine stopped, which prevents heated coolant from being properly cooled. In Mekanism, this would occur when a turbine cannot generate any more energy due to filling its buffer and having no output with any storage for energy left.")

return docs
