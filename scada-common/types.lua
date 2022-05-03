-- Global Types

rtu_t = {
    redstone = "redstone",
    boiler = "boiler",
    turbine = "turbine",
    energy_machine = "emachine",
    induction_matrix = "imatrix"
}

iss_status_t = {
    ok = "ok",
    dmg_crit = "dmg_crit",
    ex_hcoolant = "heated_coolant_backup",
    ex_waste = "full_waste",
    high_temp = "high_temp",
    no_fuel = "no_fuel",
    no_coolant = "no_coolant",
    timeout = "timeout"
}

-- MODBUS

-- modbus function codes
local MODBUS_FCODE = {
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
local MODBUS_EXCODE = {
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
