--
-- Data Bus - Central Communication Linking for RTU Front Panel
--

local psil = require("scada-common.psil")
local util = require("scada-common.util")

local databus = {}

-- databus PSIL
databus.ps = psil.create()

---@enum RTU_UNIT_HW_STATE
local RTU_UNIT_HW_STATE = {
    OFFLINE = 1,
    FAULTED = 2,
    UNFORMED = 3,
    OK = 4
}

databus.RTU_UNIT_HW_STATE = RTU_UNIT_HW_STATE

-- call to toggle heartbeat signal
function databus.heartbeat() databus.ps.toggle("heartbeat") end

-- transmit firmware versions across the bus
---@param rtu_v string RTU version
---@param comms_v string comms version
function databus.tx_versions(rtu_v, comms_v)
    databus.ps.publish("version", rtu_v)
    databus.ps.publish("comms_version", comms_v)
end

-- transmit hardware status for modem connection state
---@param has_modem boolean
function databus.tx_hw_modem(has_modem)
    databus.ps.publish("has_modem", has_modem)
end

-- transmit the number of speakers connected
---@param count integer
function databus.tx_hw_spkr_count(count)
    databus.ps.publish("speaker_count", count)
end

-- transmit unit hardware type across the bus
---@param uid integer unit ID
---@param type RTU_UNIT_TYPE
function databus.tx_unit_hw_type(uid, type)
    databus.ps.publish("unit_type_" .. uid, type)
end

-- transmit unit hardware status across the bus
---@param uid integer unit ID
---@param status RTU_UNIT_HW_STATE
function databus.tx_unit_hw_status(uid, status)
    databus.ps.publish("unit_hw_" .. uid, status)
end

-- transmit thread (routine) statuses
---@param thread string thread name
---@param ok boolean thread state
function databus.tx_rt_status(thread, ok)
    databus.ps.publish(util.c("routine__", thread), ok)
end

-- transmit supervisor link state across the bus
---@param state integer
function databus.tx_link_state(state)
    databus.ps.publish("link_state", state)
end

-- link a function to receive data from the bus
---@param field string field name
---@param func function function to link
function databus.rx_field(field, func)
    databus.ps.subscribe(field, func)
end

return databus
