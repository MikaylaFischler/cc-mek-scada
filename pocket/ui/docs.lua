local const = require("scada-common.constants")

local docs = {}

---@enum DOC_ITEM_TYPE
local DOC_ITEM_TYPE = {
    SECTION = 1,
    SUBSECTION = 2,
    TEXT = 3,
    NOTE = 4,
    TIP = 5,
    LIST = 6
}

---@enum DOC_LIST_TYPE
local DOC_LIST_TYPE = {
    BULLET = 1,
    NUMBERED = 2,
    INDICATOR = 3,
    LED = 4
}

docs.DOC_ITEM_TYPE = DOC_ITEM_TYPE
docs.DOC_LIST_TYPE = DOC_LIST_TYPE

local target

local function sect(name)
    ---@class pocket_doc_sect
    local item = { type = DOC_ITEM_TYPE.SECTION, name = name }
    table.insert(target, item)
end

---@param key string item identifier for linking
---@param name string item name for display
---@param text_a string text body, or the subtitle/note if text_b is specified
---@param text_b? string text body if subtitle/note was specified
local function doc(key, name, text_a, text_b)
    if text_b == nil then
        text_b = text_a
---@diagnostic disable-next-line: cast-local-type
        text_a = nil
    end

    ---@class pocket_doc_subsect
    local item = { type = DOC_ITEM_TYPE.SUBSECTION, key = key, name = name, subtitle = text_a, body = text_b }
    table.insert(target, item)
end

local function text(body)
    ---@class pocket_doc_text
    local item = { type = DOC_ITEM_TYPE.TEXT, text = body }
    table.insert(target, item)
end

local function note(body)
    ---@class pocket_doc_note
    local item = { type = DOC_ITEM_TYPE.NOTE, text = body }
    table.insert(target, item)
end

local function tip(body)
    ---@class pocket_doc_tip
    local item = { type = DOC_ITEM_TYPE.TIP, text = body }
    table.insert(target, item)
end

---@param type DOC_LIST_TYPE
---@param items table
---@param colors table|nil colors for indicators or nil for normal lists
local function list(type, items, colors)
    ---@class pocket_doc_list
    local list_def = { type = DOC_ITEM_TYPE.LIST, list_type = type, items = items, colors = colors }
    table.insert(target, list_def)
end

--#region System Usage

docs.usage = {
    conn = {}, config = {}, manual = {}, auto = {}, waste = {}
}

target = docs.usage.conn
sect("Overview")
tip("For the best setup experience, see the Wiki on GitHub or the YouTube channel! This app does not contain all information.")
text("Mekanism devices are connected to ComputerCraft computers that form the SCADA control system.")
sect("Mekanism Conns")
text("Multiblocks and single block devices are both connected directly to a computer by touching it or via wired modems.")
doc("usage_conn_mb", "Multiblocks", "For multiblocks, a logic adapter is used if it exists for that multiblock, otherwise a valve or port block is used.")
text("A wired modem is only connected to the block when you right click it and it gets a red border and you see a message in the chat with the peripheral name.")
tip("Do not connect all peripherals in the system on the same network cable, since Reactor PLCs will grab the first reactor they find and you may accidentally duplicate RTUs.")
sect("Computer Conns")
tip("It helps to be familiar with how ComputerCraft manages peripherals before using this system, though it is not necessary.")
doc("usage_conn_network", "Network", "All computers in the system communicate with each other via wireless or ender modems. Ender modems are preferred due to the unlimited range.")
text("Five different network channels are used and must have the same value for each name across all devices.")
text("For example, the supervisor channel SVR_CHANNEL must be set to the same channel for all devices in your system. Two different named channels should not share the same value (such as SVR_CHANNEL vs CRD_CHANNEL).")
doc("usage_conn_peri", "Peripherals", "ComputerCraft peripherals like monitors and speakers need to touch the computer or be connected via wired modems.")

target = docs.usage.config
sect("Overview")
tip("For the best setup experience, see the Wiki on GitHub or the YouTube channel! This app does not contain all information.")
text("All devices have a configurator program you can launch by running the 'configure' command.")
sect("Networking")
doc("usage_cfg_id", "Computer ID", "A computer ID must NEVER be the identical between devices, which can only happen if you duplicate a computer (such as if you middle-click on it and place it again in creative mode).")
doc("usage_cfg_chan", "Channels", "Channels are used for the computer to computer communication, described in the connection guide section. Channels with the same name must have the same value across all devices in your system and channels with different names cannot overlap.")
doc("usage_cfg_to", "Conn Timeout", "After this period of time the device will close the connection assuming the other device is unresponsive.")
doc("usage_cfg_tr", "Trusted Range", "Devices further than this block distance away will have any network traffic rejected by this device.")
doc("usage_cfg_auth", "Authentication", "To provide a level of security, you can enable facility-wide authentication by setting keys, which must be the same (and set) on all your devices. This adds computation time to each network transmission so you should only do this if you need it on multiplayer.")
sect("Logging")
text("Logs are automatically saved to a log.txt file in the root of the computer. You can change the path to it, if it contains verbose debug messages, and if it is appended to or overwritten each time the program runs.")
text("If you intend to be able to share logs, you should leave it to append.")
doc("usage_cfg_log_upload", "Sharing Logs", "To share logs, you would run 'pastebin put log.txt' where your log file is then share the code.")
sect("Reactor PLC")
text("The Reactor PLC must be connected to a single fission reactor that it will manage. Use the configurator to choose if you would like it to operate as networked or not.")
tip("The Reactor PLC should always be in a chunk with the reactor to ensure it can protect it on server start and/or chunk load.")
doc("usage_cfg_plc_nonet", "Non-Networked", "This lets you use this device as an advanced standalone safety system rather than a basic redstone breaker for easier safety protection.")
doc("usage_cfg_plc_net", "Networked", "This is the most commonly used mode. The Reactor PLC will require a connection to the Supervisor to operate and will allow usage through that for more advanced functionality.")
doc("usage_cfg_plc_unit", "Unit ID", "When networked, you can set any unit ID ranging from 1 to 4. Multiple Reactor PLCs cannot share the same unit ID.")
sect("RTU Gateway")
text("The RTU Gateway allows connecting multiple RTU interfaces to the SCADA system. These interfaces may be external peripherals or redstone.")
text("All devices except for fission reactors must be connected via an RTU Gateway.")
sect("Supervisor")
text("The Supervisor configuration is core to the entire system. If you change things about the system, such as the cooling devices or reactor count, it must be updated here.")
text("This configuration contains many settings that are detailed better in the configurator so they will not be covered here.")
doc("usage_cfg_sv_tanks", "Dynamic Tanks", "Dynamic tanks can be used to provide emergency coolant (and/or auxiliary coolant) to the system. Many layouts are supported by using a mix of facility tanks (connect to 1+ units) and unit tanks (connect to only one unit).")
doc("usage_cfg_sv_aux", "Auxiliary Coolant", "This coolant is enabled at the start of reactors to prevent water levels from dropping in the reactor or boiler while the turbine ramps up. This can be connected to a dynamic tank, a sink, or any other water supply.")
sect("Coordinator")
text("The Coordinator configuration is mainly focused around setting up your displays. This is best to do last after everything else. See the wiki on the GitHub for details on monitor sizing.")
tip("When changing the unit count on the Supervisor, you must also update it on the Coordinator.")
doc("usage_cfg_crd_main", "Main Monitor", "The main monitor contains the main interface and overview. It is always 8 block wide with varying height depending on how many units you have.")
doc("usage_cfg_crd_flow", "Flow Monitor", "The flow monitor contains the waste and coolant flow diagram. It is always 8 block wide with varying height depending on how many units you have.")
doc("usage_cfg_crd_unit", "Unit Monitor", "You need one unit monitor per reactor, and it is always a 4x4 monitor.")
text("Monitors can be connected by direct contact or via wired modems.")
text("Various unit and color options are available to customize the display to your liking. Using energy scales other than RF can impact the precision of your power-related auto control setpoints as RF is always used internally.")
sect("Pocket")
text("You're already here, so not much to mention!")
sect("Self-Check")
text("Most application configurators provide a self-check function that will check the validity of your configuration and the network connection. You should run this if you are having issues with that device.")
sect("Config Changes")
text("When an update adds or removes or otherwise modifies configuration requirements, you will be warned that you need to re-configure. You will not lose any prior data as updates will preserve configurations, you just need to step through the instructions again to add or change any new data.")

target = docs.usage.manual
sect("Overview")
text("Manual reactor control still includes safety checks and monitoring, but the burn rate is not automatically controlled.")
text("A unit is under manual control when the AUTO CTRL option Manual is selected on the unit display.")
note("Specific UIs will not be discussed here. If you need help with the UI, refer to Operator UIs > Coordinator UI > Unit Displays.")
sect("Manual Control")
text("The unit display on the Coordinator is used to run manual control. You may also start/stop and set the burn rate via the Mekanism UI on the Fission Reactor.")
tip("If some controls are grayed out on the unit display, that operation isn't currently available, such as due to the reactor being already started or being under auto control.")
text("Manual control is started by the START button and runs at the commanded burn rate next to it, which can be modified before starting or after having started by selecting a value then pressing SET.")
text("The reactor can be stopped via SCRAM, then the RPS needs to be reset via RESET.")

target = docs.usage.auto
sect("Overview")
text("A main feature of this system is automatic reactor control that supports various managed control modes.")
tip("You should first review the Main Display and Unit Display documentation under Operator UIs > Coordinator before proceeding if you are not familiar with the interfaces.")
sect("Configuration")
note("Configurations cannot be modified while auto control is active.")
doc("usage_auto_assign", "Unit Assignments", "Auto control only applies to units set to a mode other than Manual. To prefer certain units or only use the minimum number necessary, priority groups are used to split up the required burn rate.")
text("Primary units will be used first, followed by secondary, etc. If multiple are assigned to a group, burn rate will be assigned evenly between them.")
text("The next priority group will only be used once the previous one cannot keep up with the total required burn rate for auto control at that moment.")
doc("usage_auto_setpoints", "Setpoints", "Three setpoint spinner inputs are available for the three setpoint-based auto control modes. The system will do its best to meet the requested value, with the current value listed below the input.")
doc("usage_auto_limits", "Unit Limits", "Each unit can be limited to a maximum auto control burn rate to prevent exceeding any safe levels that you know of.")
doc("usage_auto_states", "Unit States", "Any assigned units must be shown as Ready and not Degraded to use auto control. See Operator UIs > Coordinator > Main Display for more.")
sect("Operation Modes")
text("Four auto control modes are available that function based on configurations set on the main display. All modes except Monitored Max Burn will try to only use the primary group until it can't keep up, then the secondary, etc.")
note("No units will be set to a burn rate higher than their limit.")
doc("usage_op_mon_max", "Monitored Max Burn", "This mode runs all units assigned to auto control at their unit limit burn rate regardless of priority group.")
doc("usage_op_com_rate", "Combined Burn Rate", "Assigned units will be commanded to meet the Burn Target setpoint.")
doc("usage_op_chg_level", "Charge Level", "Assigned units will be commanded to bring the induction matrix up to the requested Charge Target.")
doc("usage_op_gen_rate", "Generation Rate", "Assigned units will be commanded to maintain the requested Generation Target.")
note("The rate used is the input rate into the induction matrix, so using other power generation sources may disrupt this control mode.")
sect("Start and Stop")
text("A text box is used to indicate the system status. It will also provide information of why the system has paused control or failed to start.")
text("You cannot start auto control until all assigned units have all their devices connected and functional and the reactor's RPS is not tripped.")
doc("usage_op_save", "SAVE", "SAVE will save the configuration without starting control.")
doc("usage_op_start", "START", "START will attempt to start auto control, which includes first saving the configuration.")
doc("usage_op_stop", "STOP", "STOP will stop all reactors assigned to automatic control.")

target = docs.usage.waste
sect("Overview")
text("When 'valves' are connected for routing waste, this system can manage which waste product(s) are made. The flow monitor shows the diagram of how valves are meant to be connected.")
text("There are three waste products, listed below with the colors generally associated with them.")
list(DOC_LIST_TYPE.LED, { "Pu - Plutonium", "Po - Polonium", "AM - Antimatter" }, { colors.cyan, colors.green, colors.purple })
note("The Po and Pu colors are swapped in older versions of Mekanism.")
sect("Unit Waste")
text("Units can be set to specific waste products via buttons at the bottom right of a unit display.")
note("Refer to Operator UIs > Coordinator UI > Unit Displays for details.")
text("If 'Auto' is selected instead of a waste product, that unit's waste will be processed per the facility waste control.")
sect("Facility Waste")
text("Facility waste control adds additional functionality to waste processing through automatic control.")
text("The waste control interface on the main display lets you set a target waste type along with options that can change that based on circumstances.")
note("Refer to Operator UIs > Coordinator UI > Main Display for information on the display and control interface.")
doc("usage_waste_fallback", "Pu Fallback", "This option switches facility waste control to plutonium when the SNAs cannot keep up, such as at night.")
doc("usage_waste_sps_lc", "Low Charge SPS", "This option prevents the facility waste control from stopping antimatter production at low induction matrix charge (< 10%, resumes after reaching 15%).")
text("With that option enabled, antimatter production will continue. With it disabled, it will switch to polonium if set to antimatter while charge is low.")
note("Pu Fallback takes priority and will switch to plutonium when appropriate regardless of the Low Charge SPS setting.")

--#endregion

--#region Operator UIs

--#region Alarms

docs.alarms = {}

target = docs.alarms
doc("ContainmentBreach", "Containment Breach", "Reactor disconnected or indicated unformed while being at or above 100% damage; explosion assumed.")
doc("ContainmentRadiation", "Containment Radiation", "Environment detector(s) assigned to the unit have observed high levels of radiation.")
doc("ReactorLost", "Reactor Lost", "Reactor PLC has stopped communicating with the Supervisor.")
doc("CriticalDamage", "Damage Critical", "Reactor damage has reached or exceeded 100%, so it will explode at any moment.")
doc("ReactorDamage", "Reactor Damage", "Reactor temperature causing increasing damage to the reactor casing.")
doc("ReactorOverTemp", "Reactor Over Temp", "Reactor temperature is at or above maximum safe temperature, so it is now taking damage.")
doc("ReactorHighTemp", "Reactor High Temp", "Reactor temperature is above expected operating levels and may exceed maximum safe temperature soon.")
doc("ReactorWasteLeak", "Reactor Waste Leak", "The reactor is full of spent waste so it will now emit radiation if additional waste is generated.")
doc("ReactorHighWaste", "Reactor High Waste", "Reactor waste levels are high and may leak soon.")
doc("RPSTransient", "RPS Transient", "Reactor protection system was activated.")
doc("RCSTransient", "RCS Transient", "Something is wrong with the reactor coolant system, check RCS indicators for details.")
doc("TurbineTripAlarm", "Turbine Trip", "A turbine stopped rotating, likely due to having full energy storage. This will prevent cooling, so it needs to be resolved before using that unit.")

--#endregion

--#region Annunciators

docs.annunc = {
    unit = {
        main_section = {}, rps_section = {}, rcs_section = {}
    },
    facility = {
        main_section = {}
    }
}

target = docs.annunc.unit.main_section
sect("Unit Status")
doc("PLCOnline", "PLC Online", "Indicates if the fission Reactor PLC is connected. If it isn't, check that your PLC is on and configured properly.")
doc("PLCHeartbeat", "PLC Heartbeat", "An indicator of status data being live. As status messages are received from the PLC, this light will turn on and off. If it gets stuck, the Supervisor has stopped receiving data or a screen has frozen.")
doc("RadiationMonitor", "Radiation Monitor", "On if at least one environment detector is connected and assigned to this unit.")
doc("AutoControl", "Automatic Control", "On if the reactor is under the control of one of the automatic control modes.")
sect("Safety Status")
doc("ReactorSCRAM", "Reactor SCRAM", "On if the reactor protection system is holding the reactor SCRAM'd.")
doc("ManualReactorSCRAM", "Manual Reactor SCRAM", "On if the operator (you) initiated a SCRAM.")
doc("AutoReactorSCRAM", "Auto Reactor SCRAM", "On if the automatic control system initiated a SCRAM. The main view screen annunciator will have an indication as to why.")
doc("RadiationWarning", "Radiation Warning", "On if radiation levels are above normal. There is likely a leak somewhere, so that should be identified and fixed. Hazmat suit recommended.")
doc("RCPTrip", "RCP Trip", "Reactor coolant pump tripped. This is a technical concept not directly mapping to Mekanism. Here, it indicates if there is either high heated coolant or low cooled coolant that caused an RPS trip. Check the coolant system if this occurs.")
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
doc("timeout", "Connection Timeout", "Indicates if the RPS tripped due to losing connection with the supervisory computer. Check that your PLC and Supervisor remain chunk loaded.")
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
doc("SteamDumpOpen", "Steam Relief Valve Open", "This turns yellow if the turbine is set to dumping excess and red if it is set to dumping [all]. 'Relief Valve' in this case is that setting allowing the venting of steam. You should never have this set to dumping [all]. Emergency coolant activation from the Supervisor will automatically set it to dumping excess to ensure there is no backup of steam as water is added.")
doc("TurbineOverSpeed", "Turbine Over Speed", "The turbine is at steam capacity, but not tripped. You may need more turbines if they can't keep up.")
doc("GeneratorTrip", "Generator Trip", "The turbine is no longer outputting power due to it having nowhere to go. Likely due to full power storage. This will lead to a Turbine Trip if not addressed.")
doc("TurbineTrip", "Turbine Trip", "The turbine has reached its maximum power charge and has stopped rotating, and as a result stopped cooling steam to water. Ensure the turbine has somewhere to output power, as this is the most common cause of reactor meltdowns. However, the likelihood of a meltdown with this system in place is much lower, especially with emergency coolant helping during turbine trips.")

target = docs.annunc.facility.main_section
sect("Connectivity")
doc("all_sys_ok", "Unit Systems Online", "All unit systems (reactors, boilers, and turbines) are connected.")
doc("rad_computed_status", "Radiation Monitor", "At least one facility radiation monitor is connected")
doc("im_computed_status", "Induction Matrix", "The induction matrix is connected.")
doc("sps_computed_status", "SPS Connected", "Indicates if the super-critical phase shifter is connected.")
sect("Automatic Control")
doc("auto_ready", "Configured Units Ready", "All units assigned to automatic control are ready to run automatic control.")
doc("auto_active", "Process Active", "Automatic process control is active.")
doc("auto_ramping", "Process Ramping", "Automatic process control is performing an initial ramp-up of the reactors for later PID control (generation and charge mode).")
doc("auto_saturated", "Min/Max Burn Rate", "Auto control has either commanded 0 mB/t or the maximum total burn rate available (from assigned units).")
sect("Automatic SCRAM")
doc("auto_scram", "Automatic SCRAM", "Automatic control system SCRAM'ed the assigned reactors due to a safety hazard, shown by the below indicators.")
doc("as_matrix_fault", "Matrix Fault", "Automatic SCRAM occurred due to the loss of the induction matrix connection, or the matrix being unformed or faulted.")
doc("as_matrix_fill", "Matrix Charge High", "Automatic SCRAM occurred due to induction matrix charge exceeding acceptable limit.")
doc("as_crit_alarm", "Unit Critical Alarm", "Automatic SCRAM occurred due to critical level unit alarm(s).")
doc("as_radiation", "Facility Radiation High", "Automatic SCRAM occurred due to high facility radiation levels.")
doc("as_gen_fault", "Gen. Control Fault", "Automatic SCRAM occurred due to assigned units being degraded/no longer ready during generation mode. The system will automatically resume (starting with initial ramp) once the problem is resolved.")

--#endregion

--#region Coordinator UI

docs.c_ui = {
    main = {}, flow = {}, unit = {}
}

target = docs.c_ui.main
sect("Facility Diagram")
text("The facility overview diagram is made up of unit diagrams showing the reactor, boiler(s) if present, and turbine(s). This includes values of various key statistics such as temperatures along with bars showing the fill percentage of the tanks in each multiblock.")
text("Boilers are shown under the reactor, listed in order of index (#1 then #2 below). Turbines are shown to the right, also listed in order of index (indexes are per unit and set in the RTU Gateway configuration).")
text("Pipe connections are visualized with color-coded lines, which are primarily to indicate connections, as not all facilities may use pipes.")
note("If a component you have is not showing up, ensure the Supervisor is configured for your actual cooling configuration.")
sect("Facility Status")
note("The annunciator here is described in Operator UIs > Annunciators.")
doc("ui_fac_scram", "FAC SCRAM", "This SCRAMs all units in the facility.")
doc("ui_fac_ack", "ACK \x13", "This acknowledges (mutes) all alarms for all units in the facility.")
doc("ui_fac_rad", "Radiation", "The facility radiation, which is the current maximum of all connected facility radiation monitors (excludes unit monitors).")
doc("ui_fac_linked", "Linked RTUs", "The number of RTU Gateways connected.")
sect("Automatic Control")
text("This interface is used for managing automatic facility control, which only applies to units set via the unit display to be under auto control. This includes setpoints, status, configuration, and control.")
doc("ui_fac_auto_bt", "Burn Target", "When set to Combined Burn Rate mode, assigned units will ramp up to meet this combined target.")
doc("ui_fac_auto_ct", "Charge Target", "When set to Charge Level mode, assigned units will run to reach and maintain this induction matrix charge level.")
doc("ui_fac_auto_gt", "Gen. Target", "When set to Generation Rate mode, assigned units will run to reach and maintain this continuous power output, using the induction matrix input rate.")
doc("ui_fac_save", "SAVE", "This saves your configuration without starting control.")
doc("ui_fac_start", "START", "This starts the configured automatic control.")
tip("START also includes the SAVE operation.")
doc("ui_fac_stop", "STOP", "This terminates automatic control, stopping assigned units.")
text("There are four automatic control modes, detailed further in System Usage > Automatic Control")
doc("ui_fac_auto_mmb", "Monitored Max Burn", "This runs all assigned units at the maximum configured rate.")
doc("ui_fac_auto_cbr", "Combined Burn Rate", "This runs assigned units to meet the target combined rate.")
doc("ui_fac_auto_cl", "Charge Level", "This runs assigned units to maintain an induction matrix charge level.")
doc("ui_fac_auto_gr", "Generation Rate", "This runs assigned units to meet a target induction matrix power input rate.")
doc("ui_fac_auto_lim", "Unit Limit", "Each unit can have a limit set that auto control will never exceed.")
doc("ui_fac_unit_ready", "Unit Status Ready", "A unit is only ready for auto control if all multiblocks are formed, online with data received, and there is no RPS trip.")
doc("ui_fac_unit_degraded", "Unit Status Degraded", "A unit is degraded if the reactor, boiler(s), and/or turbine(s) are faulted or not connected.")
sect("Waste Control")
text("Above unit statuses are the unit waste statuses, showing which are set to the auto waste mode and the actual current waste production of that unit.")
text("The facility automatic waste control interface is surrounded by a brown border and lets you configure that system, starting with the requested waste product.")
doc("ui_fac_waste_pu_fall_act", "Fallback Active", "When the system is falling back to plutonium production while SNAs cannot keep up.")
doc("ui_fac_waste_sps_lc_act", "SPS Disabled LC", "When the system is falling back to polonium production to prevent draining all power with the SPS while the induction matrix charge has dropped below 10% and not yet reached 15%.")
doc("ui_fac_waste_pu_fall", "Pu Fallback", "Switch from Po or Antimatter when the SNAs can't keep up (like at night).")
doc("ui_fac_waste_sps_lc", "Low Charge SPS", "Continue running antimatter production even at low induction matrix charge levels (<10%).")
sect("Induction Matrix")
text("The induction matrix statistics are shown at the bottom right, including fill bars for the FILL, I (input rate), and O (output rate).")
text("Averages are computed by the system while other data is directly from the device.")
doc("ui_fac_im_charge", "Charging", "Charge is increasing (more input than output).")
doc("ui_fac_im_charge", "Discharging", "Charge is draining (more output than input).")
doc("ui_fac_im_charge", "Max I/O Rate", "The induction providers are at their maximum rate.")
doc("ui_fac_eta", "ETA", "The ETA is based off a longer average so it may take a minute to stabilize, but will give a rough estimate of time to charge/discharge.")

target = docs.c_ui.flow
sect("Flow Diagram")
text("The coolant and waste flow monitor is one large P&ID (process and instrumentation diagram) showing an overview of those flows.")
text("Color-coded pipes are used to show the connections, and valve symbols \x10\x11 are used to show valves (redstone controlled pipes).")
doc("ui_flow_rates", "Flow Rates", "Flow rates are always shown below their respective pipes and sourced from devices when possible. The waste flow is based on the reactor burn rate, then everything downstream of the SNAs are based on the SNA production rate.")
doc("ui_flow_valves", "Standard Valves", "Valve naming (PV00-XX) is based on P&ID naming conventions. These count up across the whole facility, and use tags at the end to add clarity.")
note("The indicator next to the label turns on when the associated redstone RTU is connected.")
list(DOC_LIST_TYPE.BULLET, { "PU: Plutonium", "PO: Polonium", "PL: Po Pellets", "AM: Antimatter", "EMC: Emer. Coolant", "AUX: Aux. Coolant" })
doc("ui_flow_valve_open", "OPEN", "This indicates if the respective valve is commanded open.")
doc("ui_flow_prv", "PRVs", "Pressure Relief Valves (PRVs) are used to show the turbine steam dumping states of each turbine.")
list(DOC_LIST_TYPE.LED, { "Not Dumping", "Dumping Excess", "Dumping" }, { colors.gray, colors.yellow, colors.red })
sect("SNAs")
text("Solar Neutron Activators are shown on the flow diagram as a combined block due to the large variable count supported.")
tip("SNAs consume 10x the waste as they produce in antimatter, so take that into account before connecting too many SNAs.")
doc("ui_flow_sna_act", "ACTIVE", "The SNAs have a non-zero total flow.")
doc("ui_flow_sna_cnt", "CNT", "The count of SNAs assigned to the unit.")
doc("ui_flow_sna_peak_o", "PEAK\x1a", "The combined theoretical peak output the SNAs can achieve under full sunlight.")
doc("ui_flow_sna_max_o", "MAX \x1a", "The current combined maximum output rate of the SNAs (based on current sunlight).")
doc("ui_flow_sna_max_i", "\x1aMAX", "The computed combined maximum input rate (10x the output rate).")
doc("ui_flow_sna_in", "\x1aIN", "The current input rate into the SNAs.")
sect("Dynamic Tanks")
text("Dynamic tanks configured for the system are listed to the left. The title may start with U for unit tanks or F for facility tanks.")
text("The fill information and water level are shown below the status label.")
doc("ui_flow_dyn_fill", "FILL", "If filling is enabled by the tank mode (via Mekanism UI).")
doc("ui_flow_dyn_empty", "EMPTY", "If emptying is enabled by the tank mode (via Mekanism UI).")
sect("SPS")
doc("ui_flow_sps_in", "Input Rate", "The rate of polonium into the SPS.")
doc("ui_flow_sps_prod", "Production Rate", "The rate of antimatter produced by the SPS.")
sect("Statistics")
text("The sum of all unit's waste rate statistics are shown under the SPS block. These are combined current rates, not long-term sums.")
doc("ui_flow_stat_raw", "RAW WASTE", "The combined rate of raw waste generated by the reactors before processing.")
doc("ui_flow_stat_proc", "PROC. WASTE", "The combined rates of different waste product production. Pu is plutonium, Po is polonium, and PoPl is polonium pellets. Antimatter is shown in the SPS block.")
doc("ui_flow_stat_spent", "SPENT WASTE", "The combined rate of spent waste generated after processing.")
sect("Other Blocks")
text("Other blocks, such as CENTRIFUGE, correspond to devices that are not intended to be connected and/or serve as labels.")

target = docs.c_ui.unit
sect("Data Display")
text("The unit monitor contains extensive data information, including annunciator and alarm displays described in the associated sections in the Operator UIs section.")
doc("ui_unit_core", "Core Map", "A core map diagram is shown at the top right, colored by core temperature. The layout is based off of the multiblock dimensions.")
list(DOC_LIST_TYPE.BULLET, { "Gray <= 300\xb0C", "Blue <= 350\xb0C", "Green < 600\xb0C", "Yellow < 100\xb0C", "Orange < 1200\xb0C", "Red < 1300\xb0C", "Pink >= 1300\xb0C" })
text("Internal tanks (fuel, cooled coolant, heated coolant, and waste) are displayed below the core map, labeled F, C, H, and W, respectively.")
doc("ui_unit_rad", "Radiation", "The unit radiation, which is the current maximum of all connected radiation monitors assigned to this unit.")
text("Multiple other data values are shown but should be self-explanatory.")
sect("Controls")
text("A set of buttons and the burn rate input are used for manual reactor control. When in auto mode, unavailable controls are disabled. The burn rate is only applied after SET is pressed.")
doc("ui_unit_start", "START", "This starts the reactor at the requested burn rate.")
doc("ui_unit_scram", "SCRAM", "This SCRAMs the reactor.")
doc("ui_unit_ack", "ACK \x13", "This acknowledges alarms on this unit.")
doc("ui_unit_reset", "RESET", "This resets the RPS for this unit.")
sect("Auto Control")
text("To put this unit under auto control, select an option other than Manual. You must press SET to apply this, but cannot change this while auto control is active. The priorities available are described in System Usage > Automatic Control.")
doc("ui_unit_prio", "Prio. Group", "This displays the unit's auto control priority group.")
doc("ui_unit_ready", "READY", "This indicates if the unit is ready for auto control. A unit is only ready for auto control if all multiblocks are formed, online with data received, and there is no RPS trip.")
doc("ui_unit_standby", "STANDBY", "This indicates if the unit is set to auto control and that is active, but the auto control does not currently need this reactor to run at the moment, so it is idle.")
sect("Waste Processing")
text("The unit's waste output configuration can be set via these buttons. Auto will put this unit under control of the facility waste control, otherwise the system will always command the requested option for this unit.")

--#endregion

--#endregion

--#region Front Panels

docs.fp = {
    common = {}, r_plc = {}, rtu_gw = {}, supervisor = {}, coordinator = {}
}

target = docs.fp.common
sect("Core Status")
doc("fp_status", "STATUS", "This is always lit, except on the Reactor PLC (see Reactor PLC section).")
doc("fp_heartbeat", "HEARTBEAT", "This alternates between lit and unlit as the main loop on the device runs. If this freezes, something is wrong and the logs will indicate why.")
sect("Hardware & Network")
doc("fp_modem", "MODEM", "This lights up if the wireless/ender modem is connected. In parentheses is the unique computer ID of this device, which will show up in places such as the Supervisor's connection lists.")
doc("fp_modem", "NETWORK", "This is present when in standard color modes and indicates the network status using multiple colors.")
list(DOC_LIST_TYPE.LED, { "not linked", "linked", "link denied", "bad comms version", "duplicate PLC" }, { colors.gray, colors.green, colors.red, colors.orange, colors.yellow })
text("You can fix \"bad comms version\" by ensuring all devices are up-to-date, as this indicates a communications protocol version mismatch. Note that yellow is Reactor PLC-specific, indicating duplicate unit IDs in use.")
doc("fp_nt_linked", "NT LINKED", "(color accessibility modes only)", "This indicates the device is linked to the Supervisor.")
doc("fp_nt_version", "NT VERSION", "(color accessibility modes only)", "This indicates the communications versions of the Supervisor and this device do not match. Make sure everything is up-to-date.")
sect("Versions")
doc("fp_fw", "FW", "Firmware application version of this device.")
doc("fp_nt", "NT", "Network (comms) version this device has. These must match between devices in order for them to connect.")

target = docs.fp.r_plc
sect("Overview")
text("Documentation for Reactor PLC-specific front panel items are below. Refer to 'Common Items' for the items not covered in this section.")
sect("Core Status")
doc("fp_status", "STATUS", "This is green once the PLC is initialized and OK (has all its peripherals) and red if something is wrong, in which case you should refer to the other indicator lights (REACTOR & MODEM).")
sect("Hardware & Network")
doc("fp_rplc_reactor", "REACTOR", "This indicates the status of the connected reactor peripheral.")
list(DOC_LIST_TYPE.LED, { "disconnected", "unformed", "ok" }, { colors.red, colors.yellow, colors.green })
doc("fp_nt_collision", "NT COLLISION", "(color accessibility modes only)", "This indicates the Reactor PLC unit ID is a duplicate of another already connected Reactor PLC.")
sect("Co-Routine States")
doc("fp_rplc_rt_main", "RT MAIN", "This lights up as long as the device's main loop co-routine is running, which it should be as long as STATUS is green.")
doc("fp_rplc_rt_rps", "RT RPS", "This should always be lit up if a reactor is connected as it indicates the RPS co-routine is running, otherwise safety checks will not be running.")
doc("fp_rplc_rt_ctx", "RT COMMS TX", "This should always be lit if the Reactor PLC is not running in standalone mode, as it indicates the communications transmission co-routine is running.")
doc("fp_rplc_rt_crx", "RT COMMS RX", "This should always be lit if the Reactor PLC is not running in standalone mode, as it indicates the communications receiver/handler co-routine is running.")
doc("fp_rplc_rt_spctl", "RT SPCTL", "This should always be lit if the Reactor PLC is not running in standalone mode, as it indicates the process setpoint controller co-routine is running.")
sect("Status")
doc("fp_rct_active", "RCT ACTIVE", "The reactor is active (running).")
doc("fp_emer_cool", "EMER COOLANT", "This is only present if PLC-controlled emergency coolant is configured on that device. When lit, it indicates that it has been activated.")
doc("fp_rps_trip", "RPS TRIP", "Flashes when the RPS has SCRAM'd the reactor due to a safety trip.")
sect("RPS Conditions")
doc("fp_rps_man", "MANUAL", "The RPS was tripped manually (SCRAM by user, not via the Mekanism Reactor UI).")
doc("fp_rps_auto", "AUTOMATIC", "The RPS was tripped by the Supervisor automatically.")
doc("fp_rps_to", "TIMEOUT", "The RPS tripped due to losing the Supervisor connection.")
doc("fp_rps_pflt", "PLC FAULT", "The RPS tripped due to a peripheral error.")
doc("fp_rps_rflt", "RCT FAULT", "The RPS tripped due to the reactor not being formed.")
doc("fp_rps_temp", "HI DAMAGE", "The RPS tripped due to being >=" .. const.RPS_LIMITS.MAX_DAMAGE_PERCENT .. "% damaged.")
doc("fp_rps_temp", "HI TEMP", "The RPS tripped due to high reactor temperature (>=" .. const.RPS_LIMITS.MAX_DAMAGE_TEMPERATURE .. "K).")
doc("fp_rps_fuel", "LO FUEL", "The RPS tripped due to having no fuel.")
doc("fp_rps_waste", "HI WASTE", "The RPS tripped due to having high levels of waste (>" .. (const.RPS_LIMITS.MAX_WASTE_FILL * 100) .. "%).")
doc("fp_rps_ccool", "LO CCOOLANT", "The RPS tripped due to having low levels of cooled coolant (<" .. (const.RPS_LIMITS.MIN_COOLANT_FILL * 100) .. "%).")
doc("fp_rps_ccool", "HI HCOOLANT", "The RPS tripped due to having high levels of heated coolant (>" .. (const.RPS_LIMITS.MAX_HEATED_COLLANT_FILL * 100) .. "%).")

target = docs.fp.rtu_gw
sect("Overview")
text("Documentation for RTU Gateway-specific front panel items are below. Refer to 'Common Items' for the items not covered in this section.")
doc("fp_rtu_spkr", "SPEAKERS", "This is the count of speaker peripherals connected to this RTU Gateway.")
sect("Co-Routine States")
doc("fp_rtu_rt_main", "RT MAIN", "This indicates if the device's main loop co-routine is running.")
doc("fp_rtu_rt_comms", "RT COMMS", "This indicates if the communications handler co-routine is running.")
sect("Device List")
doc("fp_rtu_rt", "RT", "In each RTU entry row, an RT light indicates if the co-routine for that RTU unit is running. This is never lit for redstone units.")
doc("fp_rtu_rt", "Device Status", "In each RTU entry row, the light to the left of the device name indicates its peripheral status.")
list(DOC_LIST_TYPE.LED, { "disconnected", "faulted", "unformed", "ok" }, { colors.red, colors.orange, colors.yellow, colors.green })
text("Note that disconnected devices lack detailed information and will not be modifiable in configuration until re-connected.")
doc("fp_rtu_rt", "Device Assignment", "In each RTU entry row, the device identification is to the right of the status light. This begins with the device type and its index followed by its assignment after the \x1a, which is a unit or the facility (FACIL). Unit 1's 3rd turbine would show up as 'TURBINE 3 \x1a UNIT 1'.")

target = docs.fp.supervisor
sect("Round Trip Times")
doc("fp_sv_rtt", "RTT", "Each connection has a round trip time, or RTT. Since the Supervisor updates at a rate of 150ms, RTTs from ~150ms to ~300ms are typical. Higher RTTs indicate lag, and if they end up in the thousands there will be performance problems.")
list(DOC_LIST_TYPE.BULLET, { "green: <=300ms", "yellow: <=500ms ", "red: >500ms" })
sect("SVR Tab")
text("This tab includes information about the Supervisor, covered by 'Common Items'.")
sect("PLC Tab")
text("This tab lists the expected PLC connections based on the number of configured units. Status information about each connection is shown when linked.")
doc("fp_sv_link", "LINK", "This indicates if the Reactor PLC is linked.")
doc("fp_sv_p_cmpid", "PLC Computer ID", "This shows the computer ID of the Reactor PLC, or --- if disconnected.")
doc("fp_sv_p_fw", "PLC FW", "This shows the firmware version of the Reactor PLC.")
sect("RTU Tab")
text("As RTU gateways connect to the Supervisor, they will show up here along with some information.")
doc("fp_sv_r_cmpid", "RTU Computer ID", "At the start of the entry is an @ sign followed by the computer ID of the RTU Gateway.")
doc("fp_sv_r_units", "UNITS", "This is a count of the number of RTUs configured on the RTU Gateway (each line on the RTU Gateway's front panel).")
doc("fp_sv_r_fw", "RTU FW", "This shows the firmware version of the RTU Gateway.")
sect("PKT Tab")
text("As pocket computers connect to the Supervisor, they will show up here along with some information. The properties listed are the same as with RTU gateways (except for UNITS), so they will not be further described here.")
sect("DEV Tab")
text("If nothing is connected, this will list all the expected RTU devices that aren't found. This page should be blank if everything is connected and configured correctly. If not, it will list certain types of detectable problems.")
doc("fp_sv_d_miss", "MISSING", "These items list missing devices, with the details that should be used in the RTU's configuration.")
doc("fp_sv_d_oor", "BAD INDEX", "If you have a configuration entry that has an index outside of the maximum number of devices configured on the Supervisor, this will show up indicating what entry is incorrect. For example, if you specified a unit has 2 turbines and a #3 connected, it would show up here as out of range.")
doc("fp_sv_d_dupe", "DUPLICATE", "If a device tries to connect that is configured the same as another, it will be rejected and show up here. If you try to connect two #1 turbines for a unit, that would fail and one would appear here.")
sect("INF Tab")
text("This tab gives information about the other tabs, along with extra details on the DEV tab.")

target = docs.fp.coordinator
sect("Round Trip Times")
doc("fp_crd_rtt", "RTT", "Each connection has a round trip time, or RTT. Since the Coordinator updates at a rate of 500ms, RTTs ~500ms - ~1000ms are typical. Higher RTTs indicate lag, which results in performance problems.")
list(DOC_LIST_TYPE.BULLET, { "green: <=1000ms", "yellow: <=1500ms ", "red: >1500ms" })
sect("CRD Tab")
text("This tab includes information about the Coordinator, partially covered by 'Common Items'.")
doc("fp_crd_spkr", "SPEAKER", "This indicates if the speaker is connected.")
doc("fp_crd_rt_main", "RT MAIN", "This indicates that the device's main loop co-routine is running.")
doc("fp_crd_rt_render", "RT RENDER", "This indicates that the Coordinator graphics renderer co-routine is running.")
doc("fp_crd_mon_main", "MAIN MONITOR", "The connection status of the main display monitor.")
doc("fp_crd_mon_flow", "FLOW MONITOR", "The connection status of the coolant and waste flow display monitor.")
doc("fp_crd_mon_unit", "UNIT X MONITOR", "The connection status of the monitor associated with a given unit.")
sect("API Tab")
text("This tab lists connected pocket computers. Refer to the Supervisor PKT tab documentation for details on fields.")

--#endregion

--#region Glossary

docs.glossary = {
    abbvs = {}, terms = {}
}

target = docs.glossary.abbvs
doc("G_ACK", "ACK", "Alarm ACKnowledge. Pressing this acknowledges that you understand an alarm occurred and would like to stop the audio tone(s).")
doc("G_Auto", "Auto", "Automatic.")
doc("G_CRD", "CRD", "Coordinator. Abbreviation for the Coordinator computer.")
doc("G_FP", "FP", "Front Panel. See Terminology.")
doc("G_Hi", "Hi", "High.")
doc("G_Lo", "Lo", "Low.")
doc("G_PID", "PID", "A Proportional Integral Derivative closed-loop controller.")
doc("G_PKT", "PKT", "Pocket. Abbreviation for the pocket computer.")
doc("G_PLC", "PLC", "Programmable Logic Controller. A device that not only reports data and controls outputs, but can also make decisions on its own.")
doc("G_PPM", "PPM", "Protected Peripheral Manager. This is an abstraction layer created for this project that prevents peripheral calls from crashing applications.")
doc("G_RCP", "RCP", "Reactor Coolant Pump. This is from real-world terminology with water-cooled (boiling water and pressurized water) reactors, but in this system it just reflects to the functioning of reactor coolant flow. See the annunciator page on it for more information.")
doc("G_RCS", "RCS", "Reactor Cooling System. The combination of all machines used to cool the reactor (turbines, boilers, dynamic tanks).")
doc("G_RPS", "RPS", "Reactor Protection System. A component of the Reactor PLC responsible for keeping the reactor safe.")
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

--#endregion

return docs
