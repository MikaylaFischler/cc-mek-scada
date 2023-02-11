--
-- Global Types
--

---@class types
local types = {}

-- CLASSES --

---@class tank_fluid
---@field name string
---@field amount integer

---@class coordinate
---@field x integer
---@field y integer
---@field z integer

---@class rtu_advertisement
---@field type integer
---@field index integer
---@field reactor integer
---@field rsio table|nil

-- ALIASES --

---@alias color integer

-- ENUMERATION TYPES --

---@alias TRI_FAIL integer
types.TRI_FAIL = {
    OK = 0,
    PARTIAL = 1,
    FULL = 2
}

---@alias PROCESS integer
types.PROCESS = {
    INACTIVE = 0,
    MAX_BURN = 1,
    BURN_RATE = 2,
    CHARGE = 3,
    GEN_RATE = 4,
    MATRIX_FAULT_IDLE = 5,
    UNIT_ALARM_IDLE = 6,
    GEN_RATE_FAULT_IDLE = 7
}

types.PROCESS_NAMES = {
    "INACTIVE",
    "MAX_BURN",
    "BURN_RATE",
    "CHARGE",
    "GEN_RATE",
    "MATRIX_FAULT_IDLE",
    "UNIT_ALARM_IDLE",
    "GEN_RATE_FAULT_IDLE"
}

---@alias WASTE_MODE integer
types.WASTE_MODE = {
    AUTO = 1,
    PLUTONIUM = 2,
    POLONIUM = 3,
    ANTI_MATTER = 4
}

---@alias ALARM integer
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

types.alarm_string = {
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

---@alias ALARM_PRIORITY integer
types.ALARM_PRIORITY = {
    CRITICAL = 0,
    EMERGENCY = 1,
    URGENT = 2,
    TIMELY = 3
}

types.alarm_prio_string = {
    "CRITICAL",
    "EMERGENCY",
    "URGENT",
    "TIMELY"
}

-- map alarms to alarm priority
types.ALARM_PRIO_MAP = {
    types.ALARM_PRIORITY.CRITICAL,
    types.ALARM_PRIORITY.CRITICAL,
    types.ALARM_PRIORITY.URGENT,
    types.ALARM_PRIORITY.CRITICAL,
    types.ALARM_PRIORITY.EMERGENCY,
    types.ALARM_PRIORITY.EMERGENCY,
    types.ALARM_PRIORITY.TIMELY,
    types.ALARM_PRIORITY.EMERGENCY,
    types.ALARM_PRIORITY.TIMELY,
    types.ALARM_PRIORITY.URGENT,
    types.ALARM_PRIORITY.TIMELY,
    types.ALARM_PRIORITY.URGENT
}

---@alias ALARM_STATE integer
types.ALARM_STATE = {
    INACTIVE = 0,
    TRIPPED = 1,
    ACKED = 2,
    RING_BACK = 3
}

-- STRING TYPES --

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

---@alias rps_trip_cause
---| "ok"
---| "dmg_crit"
---| "high_temp"
---| "no_coolant"
---| "full_waste"
---| "heated_coolant_backup"
---| "no_fuel"
---| "fault"
---| "timeout"
---| "manual"
---| "automatic"
---| "sys_fail"
---| "force_disabled"

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

---@alias rps_status_t rps_trip_cause
types.rps_status_t = {
    ok = "ok",
    dmg_crit = "dmg_crit",
    high_temp = "high_temp",
    no_coolant = "no_coolant",
    ex_waste = "full_waste",
    ex_hcoolant = "heated_coolant_backup",
    no_fuel = "no_fuel",
    fault = "fault",
    timeout = "timeout",
    manual = "manual",
    automatic = "automatic",
    sys_fail = "sys_fail",
    force_disabled = "force_disabled"
}

-- turbine steam dumping modes
---@alias DUMPING_MODE string
types.DUMPING_MODE = {
    IDLE = "IDLE",
    DUMPING = "DUMPING",
    DUMPING_EXCESS = "DUMPING_EXCESS"
}

-- MODBUS

-- modbus function codes
---@alias MODBUS_FCODE integer
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

-- modbus exception codes
---@alias MODBUS_EXCODE integer
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

return types
