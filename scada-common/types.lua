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
---@field rsio table|nil

-- ALIASES --

---@alias color integer

-- ENUMERATION TYPES --
--#region

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

-- STRING TYPES --
--#region

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
