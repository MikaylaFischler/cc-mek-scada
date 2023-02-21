--
-- Global Types
--

---@class types
local types = {}

-- CLASSES --

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
---@field index integer
---@field reactor integer
---@field rsio table|nil

-- ALIASES --

---@alias color integer

-- ENUMERATION TYPES --
--#region

---@enum TRI_FAIL
types.TRI_FAIL = {
    OK = 0,
    PARTIAL = 1,
    FULL = 2
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

---@enum WASTE_MODE
types.WASTE_MODE = {
    AUTO = 1,
    PLUTONIUM = 2,
    POLONIUM = 3,
    ANTI_MATTER = 4
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
    TurbineTrip = 12
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
    "TurbineTrip"
}

---@enum ALARM_PRIORITY
types.ALARM_PRIORITY = {
    CRITICAL = 0,
    EMERGENCY = 1,
    URGENT = 2,
    TIMELY = 3
}

types.ALARM_PRIORITY_NAMES = {
    "CRITICAL",
    "EMERGENCY",
    "URGENT",
    "TIMELY"
}

---@enum ALARM_STATE
types.ALARM_STATE = {
    INACTIVE = 0,
    TRIPPED = 1,
    ACKED = 2,
    RING_BACK = 3
}

--#endregion

-- STRING TYPES --
--#region

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
---| "clock_start"          custom, added for reactor PLC

---@alias fluid
---| "mekanism:empty_gas"
---| "minecraft:water"
---| "mekanism:sodium"
---| "mekanism:superheated_sodium"

types.fluid = {
    empty_gas = "mekanism:empty_gas",
    water = "minecraft:water",
    sodium = "mekanism:sodium",
    superheated_sodium = "mekanism:superheated_sodium"
}

---@alias rtu_t string
types.rtu_t = {
    redstone = "redstone",
    boiler_valve = "boiler_valve",
    turbine_valve = "turbine_valve",
    induction_matrix = "induction_matrix",
    sps = "sps",
    sna = "sna",
    env_detector = "environment_detector"
}

---@alias rps_trip_cause
---| "ok"
---| "dmg_crit"
---| "high_temp"
---| "no_coolant"
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
    DMG_CRIT = "dmg_crit",
    HIGH_TEMP = "high_temp",
    NO_COOLANT = "no_coolant",
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

---@alias DUMPING_MODE
---| "IDLE"
---| "DUMPING"
---| "DUMPING_EXCESS"

types.DUMPING_MODE = {
    IDLE = "IDLE",
    DUMPING = "DUMPING",
    DUMPING_EXCESS = "DUMPING_EXCESS"
}

--#endregion

-- MODBUS --
--#region

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
