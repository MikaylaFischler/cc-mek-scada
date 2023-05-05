--
-- Data Bus - Central Communication Linking for Supervisor Front Panel
--

local psil = require("scada-common.psil")

local databus = {}

local dbus_iface = {
    ps = psil.create(),
    session_entries = { rtu = {}, plc = {}, coord = {}, diag = {} }
}

-- call to toggle heartbeat signal
function databus.heartbeat() dbus_iface.ps.toggle("heartbeat") end

-- transmit firmware versions across the bus
---@param plc_v string supervisor version
---@param comms_v string comms version
function databus.tx_versions(plc_v, comms_v)
    dbus_iface.ps.publish("version", plc_v)
    dbus_iface.ps.publish("comms_version", comms_v)
end

-- transmit hardware status for modem connection state
---@param has_modem boolean
function databus.tx_hw_modem(has_modem)
    dbus_iface.ps.publish("has_modem", has_modem)
end

function databus.tx_svs_connection(type, data)
end

function databus.tx_svs_disconnection(type, data)
end

-- link a function to receive data from the bus
---@param field string field name
---@param func function function to link
function databus.rx_field(field, func)
    dbus_iface.ps.subscribe(field, func)
end

return databus
