--
-- System and Safety Constants
--

---@class scada_constants
local constants = {}

--#region Reactor Protection System (on the PLC) Limits

---@class _rps_constants
local rps = {}

rps.MAX_DAMAGE_PERCENT      = 90    -- damage >= 90%
rps.MAX_DAMAGE_TEMPERATURE  = 1200  -- temp >= 1200K
rps.MIN_COOLANT_FILL        = 0.10  -- fill < 10%
rps.MAX_WASTE_FILL          = 0.95  -- fill > 95%
rps.MAX_HEATED_COLLANT_FILL = 0.95  -- fill > 95%
rps.NO_FUEL_FILL            = 0.0   -- fill <= 0%

constants.RPS_LIMITS = rps

--#endregion

--#region Annunciator Limits

---@class _annunciator_constants
local annunc = {}

annunc.RCSFlowLow_H2O     = -3.2    -- flow < -3.2 mB/s
annunc.RCSFlowLow_NA      = -2.0    -- flow < -2.0 mB/s
annunc.CoolantLevelLow    = 0.4     -- fill < 40%
annunc.OpTempTolerance    = 5       -- high temp if >= operational temp + X
annunc.ReactorHighDeltaT  = 50      -- rate > 50K/s
annunc.FuelLevelLow       = 0.05    -- fill <= 5%
annunc.WasteLevelHigh     = 0.80    -- fill >= 80%
annunc.WaterLevelLow      = 0.4     -- fill < 40%
annunc.SteamFeedMismatch  = 10      -- ±10mB difference between total coolant flow and total steam input rate
annunc.SFM_MaxSteamDT_H20 = 2.0     -- flow > 2.0 mB/s
annunc.SFM_MinWaterDT_H20 = -3.0    -- flow < -3.0 mB/s
annunc.SFM_MaxSteamDT_NA  = 2.0     -- flow > 2.0 mB/s
annunc.SFM_MinWaterDT_NA  = -2.0    -- flow < -2.0 mB/s
annunc.RadiationWarning   = 0.00001 -- 10 uSv/h

constants.ANNUNCIATOR_LIMITS = annunc

--#endregion

--#region Supervisor Alarm Limits

---@class _alarm_constants
local alarms = {}

-- unit alarms

alarms.HIGH_WASTE     = 0.85        -- fill > 85%
alarms.HIGH_RADIATION = 0.00005     -- 50 uSv/h, not yet damaging but this isn't good

-- facility alarms

alarms.CHARGE_HIGH      = 1.0       -- once at or above 100% charge
alarms.CHARGE_RE_ENABLE = 0.95      -- once below 95% charge
alarms.FAC_HIGH_RAD     = 0.00001   -- 10 uSv/h

constants.ALARM_LIMITS = alarms

--#endregion

--#region Supervisor Redstone Activation Thresholds

---@class _rs_threshold_constants
local rs = {}

rs.IMATRIX_CHARGE_LOW  = 0.05   -- activation threshold (less than) for F_MATRIX_LOW
rs.IMATRIX_CHARGE_HIGH = 0.95   -- activation threshold (greater than) for F_MATRIX_HIGH
rs.AUX_COOL_ENABLE     = 0.60   -- actiation threshold (less than or equal) for U_AUX_COOL
rs.AUX_COOL_DISABLE    = 1.00   -- deactivation threshold (greater than or equal) for U_AUX_COOL

constants.RS_THRESHOLDS = rs

--#endregion

--#region Supervisor Constants

-- milliseconds until coolant flow is assumed to be stable enough to enable certain coolant checks
constants.FLOW_STABILITY_DELAY_MS = 10000

-- Notes on Radiation
-- - background radiation 0.0000001 Sv/h (99.99 nSv/h)
-- - "green tint" radiation 0.00001 Sv/h (10 uSv/h)
-- - damaging radiation 0.00006 Sv/h (60 uSv/h)
constants.LOW_RADIATION       = 0.00001
constants.HAZARD_RADIATION    = 0.00006
constants.HIGH_RADIATION      = 0.001
constants.VERY_HIGH_RADIATION = 0.1
constants.SEVERE_RADIATION    = 8.0
constants.EXTREME_RADIATION   = 100.0

--#endregion

--#region Mekanism Configuration Constants

---@class _mek_constants
local mek = {}

mek.BASE_BOIL_TEMP         = 373.15  -- mekanism: HeatUtils.BASE_BOIL_TEMP
mek.JOULES_PER_MB          = 1000000 -- mekanism: energyPerFissionFuel
mek.TURBINE_GAS_PER_TANK   = 64000   -- mekanism: turbineGasPerTank
mek.TURBINE_DISPERSER_FLOW = 1280    -- mekanism: turbineDisperserGasFlow
mek.TURBINE_VENT_FLOW      = 32000   -- mekanism: turbineVentGasFlow

constants.mek = mek

--#endregion

return constants
