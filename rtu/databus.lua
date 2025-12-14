--
-- Data Bus - Central Communication Linking for RTU Front Panel
--

local psil = require("scada-common.psil")
local util = require("scada-common.util")

local databus = {}

local _dbus = {
    wd_modem = true,
    wl_modem = true,
    coroutines = {}
}

-- evaluate and publish system health status
local function eval_status()
    local ok = _dbus.wd_modem and _dbus.wl_modem
    for _, v in pairs(_dbus.coroutines) do ok = ok and v end

    databus.ps.publish("status", ok)
end

-- databus PSIL
databus.ps = psil.create()

---@enum RTU_HW_STATE
local RTU_HW_STATE = {
    OFFLINE = 1,
    FAULTED = 2,
    UNFORMED = 3,
    OK = 4
}

databus.RTU_HW_STATE = RTU_HW_STATE

-- call to toggle heartbeat signal
function databus.heartbeat() databus.ps.toggle("heartbeat") end

-- transmit firmware versions
---@param rtu_v string RTU version
---@param comms_v string comms version
function databus.tx_versions(rtu_v, comms_v)
    databus.ps.publish("version", rtu_v)
    databus.ps.publish("comms_version", comms_v)
end

-- transmit hardware status for the wired comms modem
---@param has_modem boolean
function databus.tx_hw_wd_modem(has_modem)
    databus.ps.publish("has_wd_modem", has_modem)

    _dbus.wd_modem = has_modem
    eval_status()
end

-- transmit hardware status for the wireless comms modem
---@param has_modem boolean
function databus.tx_hw_wl_modem(has_modem)
    databus.ps.publish("has_wl_modem", has_modem)

    _dbus.wl_modem = has_modem
    eval_status()
end

-- transmit if the wired network is up
---@param up boolean
function databus.tx_wd_net(up)
    databus.ps.publish("has_wd_net", up)
end

-- transmit if the wireless network is up
---@param up boolean
function databus.tx_wl_net(up)
    databus.ps.publish("has_wl_net", up)
end

-- transmit the number of speakers connected
---@param count integer
function databus.tx_hw_spkr_count(count)
    databus.ps.publish("speaker_count", count)
end

-- transmit unit hardware type
---@param uid integer unit ID
---@param type RTU_UNIT_TYPE
function databus.tx_unit_hw_type(uid, type)
    databus.ps.publish("unit_type_" .. uid, type)
end

-- transmit unit hardware status
---@param uid integer unit ID
---@param status RTU_HW_STATE
function databus.tx_unit_hw_status(uid, status)
    databus.ps.publish("unit_hw_" .. uid, status)
end

-- transmit thread (routine) statuses
---@param thread string thread name
---@param ok boolean thread state
function databus.tx_rt_status(thread, ok)
    local name = util.c("routine__", thread)

    databus.ps.publish(name, ok)

    _dbus.coroutines[name] = ok
    eval_status()
end

-- transmit supervisor link state
---@param state integer
function databus.tx_link_state(state)
    databus.ps.publish("link_state", state)
end

return databus
