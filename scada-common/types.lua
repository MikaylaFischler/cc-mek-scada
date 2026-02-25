--
-- Global Types
-- note: for development, refer to the types/ directory for global comment-only @class and @alias definitions
--

---@class types
local types = {}

--#region CLASSES

-- create a new tank fluid
---@nodiscard
---@param n string name
---@param a integer amount
---@return radiation_reading
function types.new_tank_fluid(n, a) return { name = n, amount = a } end

-- create a new empty tank fluid
---@see tank_fluid
---@nodiscard
---@return tank_fluid
function types.new_empty_gas() return { type = "mekanism:empty_gas", amount = 0 } end

-- create a new radiation reading
---@see radiation_reading
---@nodiscard
---@param r number radiaiton level
---@param u string radiation unit
---@return radiation_reading
function types.new_radiation_reading(r, u) return { radiation = r, unit = u } end

-- create a new zeroed radiation reading
---@see radiation_reading
---@nodiscard
---@return radiation_reading
function types.new_zero_radiation_reading() return { radiation = 0, unit = "nSv" } end

-- create a new coordinate
---@see coordinate
---@nodiscard
---@param x integer
---@param y integer
---@param z integer
---@return coordinate
function types.new_coordinate(x, y, z) return { x = x, y = y, z = z } end

-- create a new zero coordinate
---@see coordinate
---@nodiscard
---@return coordinate
function types.new_zero_coordinate() return { x = 0, y = 0, z = 0 } end

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

--#region ENUMERATION TYPES

---@enum LISTEN_MODE
types.LISTEN_MODE = {
    WIRELESS = 1,
    WIRED = 2,
    ALL = 3
}

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
    RANGE_CONTROL = 5,
    MATRIX_FAULT_IDLE = 6,
    SYSTEM_ALARM_IDLE = 7,
    GEN_RATE_FAULT_IDLE = 8
}

types.PROCESS_NAMES = {
    "INACTIVE",
    "MAX_BURN",
    "BURN_RATE",
    "CHARGE",
    "GEN_RATE",
    "RANGE_CONTROL",
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

---@see fluid
types.FLUID = {
    EMPTY_GAS = "mekanism:empty_gas",
    WATER = "minecraft:water",
    SODIUM = "mekanism:sodium",
    SUPERHEATED_SODIUM = "mekanism:superheated_sodium"
}

---@see rps_trip_cause
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

---@see container_mode
types.CONTAINER_MODE = {
    BOTH = "BOTH",
    FILL = "FILL",
    EMPTY = "EMPTY"
}

---@see dumping_mode
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
