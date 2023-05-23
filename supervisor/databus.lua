--
-- Data Bus - Central Communication Linking for Supervisor Front Panel
--

local psil = require("scada-common.psil")

local databus = {}

-- databus PSIL
databus.ps = psil.create()

local dbus_iface = {
    session_entries = { rtu = {}, diag = {} }
}

-- call to toggle heartbeat signal
function databus.heartbeat() databus.ps.toggle("heartbeat") end

-- transmit firmware versions across the bus
---@param plc_v string supervisor version
---@param comms_v string comms version
function databus.tx_versions(plc_v, comms_v)
    databus.ps.publish("version", plc_v)
    databus.ps.publish("comms_version", comms_v)
end

-- transmit hardware status for modem connection state
---@param has_modem boolean
function databus.tx_hw_modem(has_modem)
    databus.ps.publish("has_modem", has_modem)
end

-- transmit PLC firmware version and session connection state
---@param reactor_id integer reactor unit ID
---@param fw string firmware version
---@param channel integer PLC remote port
function databus.tx_plc_connected(reactor_id, fw, channel)
    databus.ps.publish("plc_" .. reactor_id .. "_fw", fw)
    databus.ps.publish("plc_" .. reactor_id .. "_conn", true)
    databus.ps.publish("plc_" .. reactor_id .. "_chan", tostring(channel))
end

-- transmit PLC session connection state
---@param reactor_id integer reactor unit ID
function databus.tx_plc_disconnected(reactor_id)
    databus.ps.publish("plc_" .. reactor_id .. "_fw", " ------- ")
    databus.ps.publish("plc_" .. reactor_id .. "_conn", false)
    databus.ps.publish("plc_" .. reactor_id .. "_chan", " --- ")
    databus.ps.publish("plc_" .. reactor_id .. "_rtt", 0)
    databus.ps.publish("plc_" .. reactor_id .. "_rtt_color", colors.lightGray)
end

-- transmit PLC session RTT
---@param reactor_id integer reactor unit ID
---@param rtt integer round trip time
function databus.tx_plc_rtt(reactor_id, rtt)
    databus.ps.publish("plc_" .. reactor_id .. "_rtt", rtt)

    if rtt > 700 then
        databus.ps.publish("plc_" .. reactor_id .. "_rtt_color", colors.red)
    elseif rtt > 300 then
        databus.ps.publish("plc_" .. reactor_id .. "_rtt_color", colors.yellow_hc)
    else
        databus.ps.publish("plc_" .. reactor_id .. "_rtt_color", colors.green)
    end
end

-- transmit coordinator firmware version and session connection state
---@param fw string firmware version
---@param channel integer coordinator remote port
function databus.tx_crd_connected(fw, channel)
    databus.ps.publish("crd_fw", fw)
    databus.ps.publish("crd_conn", true)
    databus.ps.publish("crd_chan", tostring(channel))
end

-- transmit coordinator session connection state
function databus.tx_crd_disconnected()
    databus.ps.publish("crd_fw", " ------- ")
    databus.ps.publish("crd_conn", false)
    databus.ps.publish("crd_chan", "---")
    databus.ps.publish("crd_rtt", 0)
    databus.ps.publish("crd_rtt_color", colors.lightGray)
end

-- transmit coordinator session RTT
---@param rtt integer round trip time
function databus.tx_crd_rtt(rtt)
    databus.ps.publish("crd_rtt", rtt)

    if rtt > 700 then
        databus.ps.publish("crd_rtt_color", colors.red)
    elseif rtt > 300 then
        databus.ps.publish("crd_rtt_color", colors.yellow_hc)
    else
        databus.ps.publish("crd_rtt_color", colors.green)
    end
end

-- link a function to receive data from the bus
---@param field string field name
---@param func function function to link
function databus.rx_field(field, func)
    databus.ps.subscribe(field, func)
end

return databus
