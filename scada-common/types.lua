--
-- Global Types
--

---@class types
local types = {}

--#region CC: TWEAKED CLASSES https://tweaked.cc

---@class Redirect
---@field write fun(text: string) Write text at the current cursor position, moving the cursor to the end of the text.
---@field scroll fun(y: integer) Move all positions up (or down) by y pixels.
---@field getCursorPos fun() : x: integer, y: integer Get the position of the cursor.
---@field setCursorPos fun(x: integer, y: integer) Set the position of the cursor.
---@field getCursorBlink fun() : boolean Checks if the cursor is currently blinking.
---@field setCursorBlink fun(blink: boolean) Sets whether the cursor should be visible (and blinking) at the current cursor position.
---@field getSize fun() : width: integer, height: integer Get the size of the terminal.
---@field clear fun() Clears the terminal, filling it with the current background color.
---@field clearLine fun() Clears the line the cursor is currently on, filling it with the current background color.
---@field getTextColor fun() : color Return the color that new text will be written as.
---@field setTextColor fun(color: color) Set the colour that new text will be written as.
---@field getBackgroundColor fun() : color Return the current background color.
---@field setBackgroundColor fun(color: color) set the current background color.
---@field isColor fun() Determine if this terminal supports color.
---@field blit fun(text: string, textColor: string, backgroundColor: string) Writes text to the terminal with the specific foreground and background colors.
---@diagnostic disable-next-line: duplicate-doc-field
---@field setPaletteColor fun(index: color, color: integer) Set the palette for a specific color.
---@diagnostic disable-next-line: duplicate-doc-field
---@field setPaletteColor fun(index: color, r: number, g: number, b:number) Set the palette for a specific color. R/G/B are 0 to 1.
---@field getPaletteColor fun(color: color) :  r: number, g: number, b:number Get the current palette for a specific color.

---@class Window:Redirect
---@field getLine fun(y: integer) : content: string, fg: string, bg: string Get the buffered contents of a line in this window.
---@field setVisible fun(visible: boolean) Set whether this window is visible. Invisible windows will not be drawn to the screen until they are made visible again.
---@field isVisible fun() : visible: boolean Get whether this window is visible. Invisible windows will not be drawn to the screen until they are made visible again.
---@field redraw fun() Draw this window. This does nothing if the window is not visible.
---@field restoreCursor fun() Set the current terminal's cursor to where this window's cursor is. This does nothing if the window is not visible.
---@field getPosition fun() : x: integer, y: integer Get the position of the top left corner of this window.
---@field reposition fun(new_x: integer, new_y: integer, new_width?: integer, new_height?: integer, new_parent?: Redirect) Reposition or resize the given window.

---@class Monitor:Redirect
---@field setTextScale fun(scale: number) Set the scale of this monitor.
---@field getTextScale fun() : number Get the monitor's current text scale.

---@class Modem
---@field open fun(channel: integer) Open a channel on a modem.
---@field isOpen fun(channel: integer) : boolean Check if a channel is open.
---@field close fun(channel: integer) Close an open channel, meaning it will no longer receive messages.
---@field closeAll fun() Close all open channels.
---@field transmit fun(channel: integer, replyChannel: integer, payload: any) Sends a modem message on a certain channel.
---@field isWireless fun() : boolean Determine if this is a wired or wireless modem.
---@field getNamesRemote fun() : string[] List all remote peripherals on the wired network.
---@field isPresentRemote fun(name: string) : boolean Determine if a peripheral is available on this wired network.
---@field getTypeRemote fun(name: string) : string|nil Get the type of a peripheral is available on this wired network.
---@field hasTypeRemote fun(name: string, type: string) : boolean|nil Check a peripheral is of a particular .
---@field getMethodsRemote fun(name: string) : string[] Get all available methods for the remote peripheral with the given name.
---@field callRemote fun(remoteName: string, method: string, ...) : table Call a method on a peripheral on this wired network.
---@field getNameLocal fun() : string|nil Returns the network name of the current computer, if the modem is on.

---@class Speaker
---@field playNote fun(instrument: string, volume?: number, pitch?: number) : success: boolean Plays a note block note through the speaker.
---@field playSound fun(name: string, volume?: number, pitch?: number) : success: boolean Plays a Minecraft sound through the speaker.
---@field playAudio fun(audio: number[], volume?: number) : success: boolean Attempt to stream some audio data to the speaker.
---@field stop fun() Stop all audio being played by this speaker.

--#endregion

--#region CLASSES

---@class tank_fluid
---@field name fluid
---@field amount integer

-- create a new tank fluid
---@nodiscard
---@param n string name
---@param a integer amount
---@return radiation_reading
function types.new_tank_fluid(n, a) return { name = n, amount = a } end

-- create a new empty tank fluid
---@nodiscard
---@return tank_fluid
function types.new_empty_gas() return { type = "mekanism:empty_gas", amount = 0 } end

---@class radiation_reading
---@field radiation number
---@field unit string

-- create a new radiation reading
---@nodiscard
---@param r number radiaiton level
---@param u string radiation unit
---@return radiation_reading
function types.new_radiation_reading(r, u) return { radiation = r, unit = u } end

-- create a new zeroed radiation reading
---@nodiscard
---@return radiation_reading
function types.new_zero_radiation_reading() return { radiation = 0, unit = "nSv" } end

---@class coordinate_2d
---@field x integer
---@field y integer

---@class coordinate
---@field x integer
---@field y integer
---@field z integer

-- create a new coordinate
---@nodiscard
---@param x integer
---@param y integer
---@param z integer
---@return coordinate
function types.new_coordinate(x, y, z) return { x = x, y = y, z = z } end

-- create a new zero coordinate
---@nodiscard
---@return coordinate
function types.new_zero_coordinate() return { x = 0, y = 0, z = 0 } end

---@class rtu_advertisement
---@field type RTU_UNIT_TYPE
---@field index integer|false
---@field reactor integer
---@field rs_conns IO_PORT[][]|nil

-- create a new reactor database
---@nodiscard
function types.new_reactor_db()
    ---@class reactor_db
    local db = {
        auto_ack_token = 0,
        last_status_update = 0,
        control_state = false,
        no_reactor = false,
        formed = false,
        rps_tripped = false,
        rps_trip_cause = "ok",  ---@type rps_trip_cause
        max_op_temp_H2O = 1200,
        max_op_temp_Na = 1200,
        ---@class rps_status
        rps_status = {
            high_dmg = false,
            high_temp = false,
            low_cool = false,
            ex_waste = false,
            ex_hcool = false,
            no_fuel = false,
            fault = false,
            timeout = false,
            manual = false,
            automatic = false,
            sys_fail = false,
            force_dis = false
        },
        ---@class mek_status
        mek_status = {
            heating_rate = 0.0,

            status = false,
            burn_rate = 0.0,
            act_burn_rate = 0.0,
            temp = 0.0,
            damage = 0.0,
            boil_eff = 0.0,
            env_loss = 0.0,

            fuel = 0,
            fuel_need = 0,
            fuel_fill = 0.0,
            waste = 0,
            waste_need = 0,
            waste_fill = 0.0,
            ccool_type = types.FLUID.EMPTY_GAS, ---@type fluid
            ccool_amnt = 0,
            ccool_need = 0,
            ccool_fill = 0.0,
            hcool_type = types.FLUID.EMPTY_GAS, ---@type fluid
            hcool_amnt = 0,
            hcool_need = 0,
            hcool_fill = 0.0
        },
        ---@class mek_struct
        mek_struct = {
            length = 0,
            width = 0,
            height = 0,
            min_pos = types.new_zero_coordinate(),
            max_pos = types.new_zero_coordinate(),
            heat_cap = 0,
            fuel_asm = 0,
            fuel_sa = 0,
            fuel_cap = 0,
            waste_cap = 0,
            ccool_cap = 0,
            hcool_cap = 0,
            max_burn = 0.0
        }
    }

    return db
end

--#endregion

-- ALIASES --

---@alias color integer

--#region ENUMERATION TYPES

---@enum TEMP_SCALE
types.TEMP_SCALE = {
    KELVIN = 1,
    CELSIUS = 2,
    FAHRENHEIT = 3,
    RANKINE = 4
}

types.TEMP_SCALE_NAMES = {
    "Kelvin",
    "Celsius",
    "Fahrenheit",
    "Rankine"
}

types.TEMP_SCALE_UNITS = {
    "K",
    "\xb0C",
    "\xb0F",
    "\xb0R"
}

---@enum ENERGY_SCALE
types.ENERGY_SCALE = {
    JOULES = 1,
    FE = 2,
    RF = 3
}

types.ENERGY_SCALE_NAMES = {
    "Joules (J)",
    "Forge Energy (FE)",
    "Redstone Flux (RF)"
}

types.ENERGY_SCALE_UNITS = {
    "J",
    "FE",
    "RF"
}

local GENERIC_STATE = {
    OFFLINE = 1,
    UNFORMED = 2,
    FAULT = 3,
    IDLE = 4,
    ACTIVE = 5
}

---@enum REACTOR_STATE
types.REACTOR_STATE = {
    OFFLINE = 1,
    UNFORMED = 2,
    FAULT = 3,
    DISABLED = 4,
    ACTIVE = 5,
    SCRAMMED = 6,
    FORCE_DISABLED = 7
}

---@enum BOILER_STATE
types.BOILER_STATE = GENERIC_STATE

---@enum TURBINE_STATE
types.TURBINE_STATE = {
    OFFLINE = 1,
    UNFORMED = 2,
    FAULT = 3,
    IDLE = 4,
    ACTIVE = 5,
    TRIPPED = 6
}

---@enum TANK_STATE
types.TANK_STATE = {
    OFFLINE = 1,
    UNFORMED = 2,
    FAULT = 3,
    ONLINE = 4,
    LOW_FILL = 5,
    HIGH_FILL = 6
}

---@enum IMATRIX_STATE
types.IMATRIX_STATE = {
    OFFLINE = 1,
    UNFORMED = 2,
    FAULT = 3,
    ONLINE = 4,
    LOW_CHARGE = 5,
    HIGH_CHARGE = 6
}

---@enum SPS_STATE
types.SPS_STATE = GENERIC_STATE

---@enum PANEL_LINK_STATE
types.PANEL_LINK_STATE = {
    LINKED = 1,
    DENIED = 2,
    COLLISION = 3,
    BAD_VERSION = 4,
    DISCONNECTED = 5
}

---@enum RTU_UNIT_TYPE
types.RTU_UNIT_TYPE = {
    VIRTUAL = 0,        -- virtual device
    REDSTONE = 1,       -- redstone I/O
    BOILER_VALVE = 2,   -- boiler mekanism 10.1+
    TURBINE_VALVE = 3,  -- turbine, mekanism 10.1+
    DYNAMIC_VALVE = 4,  -- dynamic tank, mekanism 10.1+
    IMATRIX = 5,        -- induction matrix
    SPS = 6,            -- SPS
    SNA = 7,            -- SNA
    ENV_DETECTOR = 8    -- environment detector
}

types.RTU_UNIT_NAMES = {
    "redstone",
    "boiler_valve",
    "turbine_valve",
    "dynamic_valve",
    "induction_matrix",
    "sps",
    "sna",
    "environment_detector"
}

-- safe conversion of RTU UNIT TYPE to string
---@nodiscard
---@param utype RTU_UNIT_TYPE
---@return string
function types.rtu_type_to_string(utype)
    if utype == types.RTU_UNIT_TYPE.VIRTUAL then
        return "virtual"
    elseif utype == types.RTU_UNIT_TYPE.REDSTONE or
       utype == types.RTU_UNIT_TYPE.BOILER_VALVE or
       utype == types.RTU_UNIT_TYPE.TURBINE_VALVE or
       utype == types.RTU_UNIT_TYPE.DYNAMIC_VALVE or
       utype == types.RTU_UNIT_TYPE.IMATRIX or
       utype == types.RTU_UNIT_TYPE.SPS or
       utype == types.RTU_UNIT_TYPE.SNA or
       utype == types.RTU_UNIT_TYPE.ENV_DETECTOR then
        return types.RTU_UNIT_NAMES[utype]
    else
        return ""
    end
end

---@enum RTU_ID_FAIL
types.RTU_ID_FAIL = {
    OK = 0,
    OUT_OF_RANGE = 1,
    DUPLICATE = 2,
    MAX_DEVICES = 3,
    MISSING = 4
}

---@enum TRI_FAIL
types.TRI_FAIL = {
    OK = 1,
    PARTIAL = 2,
    FULL = 3
}

---@enum PROCESS
types.PROCESS = {
    INACTIVE = 0,
    MAX_BURN = 1,
    BURN_RATE = 2,
    CHARGE = 3,
    GEN_RATE = 4,
    MATRIX_FAULT_IDLE = 5,
    SYSTEM_ALARM_IDLE = 6,
    GEN_RATE_FAULT_IDLE = 7
}

types.PROCESS_NAMES = {
    "INACTIVE",
    "MAX_BURN",
    "BURN_RATE",
    "CHARGE",
    "GEN_RATE",
    "MATRIX_FAULT_IDLE",
    "SYSTEM_ALARM_IDLE",
    "GEN_RATE_FAULT_IDLE"
}

---@enum AUTO_GROUP
types.AUTO_GROUP = {
    MANUAL = 0,
    PRIMARY = 1,
    SECONDARY = 2,
    TERTIARY = 3,
    BACKUP = 4
}

types.AUTO_GROUP_NAMES = {
    "Manual",
    "Primary",
    "Secondary",
    "Tertiary",
    "Backup"
}

---@enum COOLANT_TYPE
types.COOLANT_TYPE = {
    WATER = 1,
    SODIUM = 2
}

---@enum WASTE_MODE
types.WASTE_MODE = {
    AUTO = 1,
    MANUAL_PLUTONIUM = 2,
    MANUAL_POLONIUM = 3,
    MANUAL_ANTI_MATTER = 4
}

types.WASTE_MODE_NAMES = {
    "AUTO",
    "MANUAL_PLUTONIUM",
    "MANUAL_POLONIUM",
    "MANUAL_ANTI_MATTER"
}

---@enum WASTE_PRODUCT
types.WASTE_PRODUCT = {
    PLUTONIUM = 1,
    POLONIUM = 2,
    ANTI_MATTER = 3
}

types.WASTE_PRODUCT_NAMES = {
    "PLUTONIUM",
    "POLONIUM",
    "ANTI_MATTER"
}

---@enum ALARM
types.ALARM = {
    ContainmentBreach = 1,
    ContainmentRadiation = 2,
    ReactorLost = 3,
    CriticalDamage = 4,
    ReactorDamage = 5,
    ReactorOverTemp = 6,
    ReactorHighTemp = 7,
    ReactorWasteLeak = 8,
    ReactorHighWaste = 9,
    RPSTransient = 10,
    RCSTransient = 11,
    TurbineTrip = 12,
    FacilityRadiation = 13
}

types.ALARM_NAMES = {
    "ContainmentBreach",
    "ContainmentRadiation",
    "ReactorLost",
    "CriticalDamage",
    "ReactorDamage",
    "ReactorOverTemp",
    "ReactorHighTemp",
    "ReactorWasteLeak",
    "ReactorHighWaste",
    "RPSTransient",
    "RCSTransient",
    "TurbineTrip",
    "FacilityRadiation"
}

---@enum ALARM_PRIORITY
types.ALARM_PRIORITY = {
    CRITICAL = 1,
    EMERGENCY = 2,
    URGENT = 3,
    TIMELY = 4
}

types.ALARM_PRIORITY_NAMES = {
    "CRITICAL",
    "EMERGENCY",
    "URGENT",
    "TIMELY"
}

---@enum ALARM_STATE
types.ALARM_STATE = {
    INACTIVE = 1,
    TRIPPED = 2,
    ACKED = 3,
    RING_BACK = 4
}

types.ALARM_STATE_NAMES = {
    "INACTIVE",
    "TRIPPED",
    "ACKED",
    "RING_BACK"
}

--#endregion

--#region STRING TYPES

---@alias side
---|"top"
---|"bottom"
---|"left"
---|"right"
---|"front"
---|"back"

---@alias os_event
---| "alarm"
---| "char"
---| "computer_command"
---| "disk"
---| "disk_eject"
---| "http_check"
---| "http_failure"
---| "http_success"
---| "key"
---| "key_up"
---| "modem_message"
---| "monitor_resize"
---| "monitor_touch"
---| "mouse_click"
---| "mouse_drag"
---| "mouse_scroll"
---| "mouse_up"
---| "double_click" (custom)
---| "paste"
---| "peripheral"
---| "peripheral_detach"
---| "rednet_message"
---| "redstone"
---| "speaker_audio_empty"
---| "task_complete"
---| "term_resize"
---| "terminate"
---| "timer"
---| "turtle_inventory"
---| "websocket_closed"
---| "websocket_failure"
---| "websocket_message"
---| "websocket_success"
---| "clock_start" (custom)

---@alias fluid
---| "mekanism:empty_gas"
---| "minecraft:water"
---| "mekanism:sodium"
---| "mekanism:superheated_sodium"

types.FLUID = {
    EMPTY_GAS = "mekanism:empty_gas",
    WATER = "minecraft:water",
    SODIUM = "mekanism:sodium",
    SUPERHEATED_SODIUM = "mekanism:superheated_sodium"
}

---@alias rps_trip_cause
---| "ok"
---| "high_dmg"
---| "high_temp"
---| "low_coolant"
---| "ex_waste"
---| "ex_heated_coolant"
---| "no_fuel"
---| "fault"
---| "timeout"
---| "manual"
---| "automatic"
---| "sys_fail"
---| "force_disabled"

types.RPS_TRIP_CAUSE = {
    OK = "ok",
    HIGH_DMG = "high_dmg",
    HIGH_TEMP = "high_temp",
    LOW_COOLANT = "low_coolant",
    EX_WASTE = "ex_waste",
    EX_HCOOLANT = "ex_heated_coolant",
    NO_FUEL = "no_fuel",
    FAULT = "fault",
    TIMEOUT = "timeout",
    MANUAL = "manual",
    AUTOMATIC = "automatic",
    SYS_FAIL = "sys_fail",
    FORCE_DISABLED = "force_disabled"
}

---@alias container_mode
---| "BOTH"
---| "FILL"
---| "EMPTY"

types.CONTAINER_MODE = {
    BOTH = "BOTH",
    FILL = "FILL",
    EMPTY = "EMPTY"
}

---@alias dumping_mode
---| "IDLE"
---| "DUMPING"
---| "DUMPING_EXCESS"

types.DUMPING_MODE = {
    IDLE = "IDLE",
    DUMPING = "DUMPING",
    DUMPING_EXCESS = "DUMPING_EXCESS"
}

--#endregion

--#region MODBUS

-- MODBUS function codes
---@enum MODBUS_FCODE
types.MODBUS_FCODE = {
    READ_COILS = 0x01,
    READ_DISCRETE_INPUTS = 0x02,
    READ_MUL_HOLD_REGS = 0x03,
    READ_INPUT_REGS = 0x04,
    WRITE_SINGLE_COIL = 0x05,
    WRITE_SINGLE_HOLD_REG = 0x06,
    WRITE_MUL_COILS = 0x0F,
    WRITE_MUL_HOLD_REGS = 0x10,
    ERROR_FLAG = 0x80
}

-- MODBUS exception codes
---@enum MODBUS_EXCODE
types.MODBUS_EXCODE = {
    OK = 0x00,
    ILLEGAL_FUNCTION = 0x01,
    ILLEGAL_DATA_ADDR = 0x02,
    ILLEGAL_DATA_VALUE = 0x03,
    SERVER_DEVICE_FAIL = 0x04,
    ACKNOWLEDGE = 0x05,
    SERVER_DEVICE_BUSY = 0x06,
    NEG_ACKNOWLEDGE = 0x07,
    MEMORY_PARITY_ERROR = 0x08,
    GATEWAY_PATH_UNAVAILABLE = 0x0A,
    GATEWAY_TARGET_TIMEOUT = 0x0B
}

--#endregion

return types
