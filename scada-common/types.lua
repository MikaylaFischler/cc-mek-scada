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

-- STRING TYPES --

---@alias rtu_t string
types.rtu_t = {
    redstone = "redstone",
    boiler = "boiler",
    boiler_valve = "boiler_valve",
    turbine = "turbine",
    turbine_valve = "turbine_valve",
    energy_machine = "emachine",
    induction_matrix = "induction_matrix"
}

---@alias rps_status_t string
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
    manual = "manual"
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
