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
        main_section = {},
        rps_section = {},
        rcs_section = {}
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

docs.glossary = {}

target = docs.glossary
doc("G_Nominal", "Nominal", "")
doc("G_RCS", "RCS", "Reactor Cooling System: the combination of all machines used to cool the reactor.")
doc("G_RPS", "RPS", "Reactor Protection System: a component of the reactor PLC responsible for keeping the reactor safe.")
doc("G_Transient", "Transient", "")
doc("G_Trip", "Trip", "A checked condition has occurred, also known as 'tripped'.")

target = docs.annunc.unit.main_section

return docs
