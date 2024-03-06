--
-- Data Bus - Central Communication Linking for PLC Front Panel
--

local log  = require("scada-common.log")
local psil = require("scada-common.psil")
local util = require("scada-common.util")

local databus = {}

-- databus PSIL
databus.ps = psil.create()

local dbus_iface = {
    rps_scram = function () log.debug("DBUS: unset rps_scram() called") end,
    rps_reset = function () log.debug("DBUS: unset rps_reset() called") end
}

-- call to toggle heartbeat signal
function databus.heartbeat() databus.ps.toggle("heartbeat") end

-- link RPS command functions
---@param scram function reactor SCRAM function
---@param reset function RPS reset function
function databus.link_rps(scram, reset)
    dbus_iface.rps_scram = scram
    dbus_iface.rps_reset = reset
end

-- transmit a command to the RPS to SCRAM
function databus.rps_scram() dbus_iface.rps_scram() end

-- transmit a command to the RPS to reset
function databus.rps_reset() dbus_iface.rps_reset() end

-- transmit firmware versions across the bus
---@param plc_v string PLC version
---@param comms_v string comms version
function databus.tx_versions(plc_v, comms_v)
    databus.ps.publish("version", plc_v)
    databus.ps.publish("comms_version", comms_v)
end

-- transmit unit ID across the bus
---@param id integer unit ID
function databus.tx_id(id)
    databus.ps.publish("unit_id", id)
end

-- transmit hardware status across the bus
---@param plc_state plc_state
function databus.tx_hw_status(plc_state)
    databus.ps.publish("reactor_dev_state", util.trinary(plc_state.no_reactor, 1, util.trinary(plc_state.reactor_formed, 3, 2)))
    databus.ps.publish("has_modem", not plc_state.no_modem)
    databus.ps.publish("degraded", plc_state.degraded)
    databus.ps.publish("init_ok", plc_state.init_ok)
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

-- transmit reactor enable state across the bus
---@param active any reactor active
function databus.tx_reactor_state(active)
    databus.ps.publish("reactor_active", active == true)
end

-- transmit RPS data across the bus
---@param tripped boolean RPS tripped
---@param status table RPS status
---@param emer_cool_active boolean RPS activated the emergency coolant
function databus.tx_rps(tripped, status, emer_cool_active)
    databus.ps.publish("rps_scram", tripped)
    databus.ps.publish("rps_damage", status[1])
    databus.ps.publish("rps_high_temp", status[2])
    databus.ps.publish("rps_low_ccool", status[3])
    databus.ps.publish("rps_high_waste", status[4])
    databus.ps.publish("rps_high_hcool", status[5])
    databus.ps.publish("rps_no_fuel", status[6])
    databus.ps.publish("rps_fault", status[7])
    databus.ps.publish("rps_timeout", status[8])
    databus.ps.publish("rps_manual", status[9])
    databus.ps.publish("rps_automatic", status[10])
    databus.ps.publish("rps_sysfail", status[11])
    databus.ps.publish("emer_cool", emer_cool_active)
end

-- link a function to receive data from the bus
---@param field string field name
---@param func function function to link
function databus.rx_field(field, func)
    databus.ps.subscribe(field, func)
end

return databus
