--
-- Data Bus - Central Communication Linking for Supervisor Front Panel
--

local psil = require("scada-common.psil")
local util = require("scada-common.util")

local pgi  = require("supervisor.panel.pgi")

-- nominal RTT is ping (0ms to 10ms usually) + 150ms for SV main loop tick
local WARN_RTT = 300    -- 2x as long as expected w/ 0 ping
local HIGH_RTT = 500    -- 3.33x as long as expected w/ 0 ping

local databus = {}

-- databus PSIL
databus.ps = psil.create()

-- call to toggle heartbeat signal
function databus.heartbeat() databus.ps.toggle("heartbeat") end

-- transmit firmware versions across the bus
---@param sv_v string supervisor version
---@param comms_v string comms version
function databus.tx_versions(sv_v, comms_v)
    databus.ps.publish("version", sv_v)
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
---@param s_addr integer PLC computer ID
function databus.tx_plc_connected(reactor_id, fw, s_addr)
    databus.ps.publish("plc_" .. reactor_id .. "_fw", fw)
    databus.ps.publish("plc_" .. reactor_id .. "_conn", true)
    databus.ps.publish("plc_" .. reactor_id .. "_addr", util.sprintf("@% 4d", s_addr))
end

-- transmit PLC disconnected
---@param reactor_id integer reactor unit ID
function databus.tx_plc_disconnected(reactor_id)
    databus.ps.publish("plc_" .. reactor_id .. "_fw", " ------- ")
    databus.ps.publish("plc_" .. reactor_id .. "_conn", false)
    databus.ps.publish("plc_" .. reactor_id .. "_addr", " --- ")
    databus.ps.publish("plc_" .. reactor_id .. "_rtt", 0)
    databus.ps.publish("plc_" .. reactor_id .. "_rtt_color", colors.lightGray)
end

-- transmit PLC session RTT
---@param reactor_id integer reactor unit ID
---@param rtt integer round trip time
function databus.tx_plc_rtt(reactor_id, rtt)
    databus.ps.publish("plc_" .. reactor_id .. "_rtt", rtt)

    if rtt > HIGH_RTT then
        databus.ps.publish("plc_" .. reactor_id .. "_rtt_color", colors.red)
    elseif rtt > WARN_RTT then
        databus.ps.publish("plc_" .. reactor_id .. "_rtt_color", colors.yellow_hc)
    else
        databus.ps.publish("plc_" .. reactor_id .. "_rtt_color", colors.green_hc)
    end
end

-- transmit RTU firmware version and session connection state
---@param session_id integer RTU session
---@param fw string firmware version
---@param s_addr integer RTU computer ID
function databus.tx_rtu_connected(session_id, fw, s_addr)
    databus.ps.publish("rtu_" .. session_id .. "_fw", fw)
    databus.ps.publish("rtu_" .. session_id .. "_addr", util.sprintf("@ C% 3d", s_addr))
    pgi.create_rtu_entry(session_id)
end

-- transmit RTU disconnected
---@param session_id integer RTU session
function databus.tx_rtu_disconnected(session_id)
    pgi.delete_rtu_entry(session_id)
end

-- transmit RTU session RTT
---@param session_id integer RTU session
---@param rtt integer round trip time
function databus.tx_rtu_rtt(session_id, rtt)
    databus.ps.publish("rtu_" .. session_id .. "_rtt", rtt)

    if rtt > HIGH_RTT then
        databus.ps.publish("rtu_" .. session_id .. "_rtt_color", colors.red)
    elseif rtt > WARN_RTT then
        databus.ps.publish("rtu_" .. session_id .. "_rtt_color", colors.yellow_hc)
    else
        databus.ps.publish("rtu_" .. session_id .. "_rtt_color", colors.green_hc)
    end
end

-- transmit RTU session unit count
---@param session_id integer RTU session
---@param units integer unit count
function databus.tx_rtu_units(session_id, units)
    databus.ps.publish("rtu_" .. session_id .. "_units", units)
end

-- transmit coordinator firmware version and session connection state
---@param fw string firmware version
---@param s_addr integer coordinator computer ID
function databus.tx_crd_connected(fw, s_addr)
    databus.ps.publish("crd_fw", fw)
    databus.ps.publish("crd_conn", true)
    databus.ps.publish("crd_addr", tostring(s_addr))
end

-- transmit coordinator disconnected
function databus.tx_crd_disconnected()
    databus.ps.publish("crd_fw", " ------- ")
    databus.ps.publish("crd_conn", false)
    databus.ps.publish("crd_addr", "---")
    databus.ps.publish("crd_rtt", 0)
    databus.ps.publish("crd_rtt_color", colors.lightGray)
end

-- transmit coordinator session RTT
---@param rtt integer round trip time
function databus.tx_crd_rtt(rtt)
    databus.ps.publish("crd_rtt", rtt)

    if rtt > HIGH_RTT then
        databus.ps.publish("crd_rtt_color", colors.red)
    elseif rtt > WARN_RTT then
        databus.ps.publish("crd_rtt_color", colors.yellow_hc)
    else
        databus.ps.publish("crd_rtt_color", colors.green_hc)
    end
end

-- transmit PKT firmware version and PDG session connection state
---@param session_id integer PDG session
---@param fw string firmware version
---@param s_addr integer PDG computer ID
function databus.tx_pdg_connected(session_id, fw, s_addr)
    databus.ps.publish("pdg_" .. session_id .. "_fw", fw)
    databus.ps.publish("pdg_" .. session_id .. "_addr", util.sprintf("@ C% 3d", s_addr))
    pgi.create_pdg_entry(session_id)
end

-- transmit PDG session disconnected
---@param session_id integer PDG session
function databus.tx_pdg_disconnected(session_id)
    pgi.delete_pdg_entry(session_id)
end

-- transmit PDG session RTT
---@param session_id integer PDG session
---@param rtt integer round trip time
function databus.tx_pdg_rtt(session_id, rtt)
    databus.ps.publish("pdg_" .. session_id .. "_rtt", rtt)

    if rtt > HIGH_RTT then
        databus.ps.publish("pdg_" .. session_id .. "_rtt_color", colors.red)
    elseif rtt > WARN_RTT then
        databus.ps.publish("pdg_" .. session_id .. "_rtt_color", colors.yellow_hc)
    else
        databus.ps.publish("pdg_" .. session_id .. "_rtt_color", colors.green_hc)
    end
end

-- link a function to receive data from the bus
---@param field string field name
---@param func function function to link
function databus.rx_field(field, func)
    databus.ps.subscribe(field, func)
end

return databus
