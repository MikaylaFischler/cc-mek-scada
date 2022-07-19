--
-- Protected Peripheral Manager
--

local log  = require("scada-common.log")
local util = require("scada-common.util")

---@class ppm
local ppm = {}

local ACCESS_FAULT = nil    ---@type nil

ppm.ACCESS_FAULT = ACCESS_FAULT

----------------------------
-- PRIVATE DATA/FUNCTIONS --
----------------------------

local REPORT_FREQUENCY = 20 -- log every 20 faults per function

local _ppm_sys = {
    mounts = {},
    auto_cf = false,
    faulted = false,
    last_fault = "",
    terminate = false,
    mute = false
}

-- wrap peripheral calls with lua protected call as we don't want a disconnect to crash a program
---
---also provides peripheral-specific fault checks (auto-clear fault defaults to true)
---
---assumes iface is a valid peripheral
---@param iface string CC peripheral interface
local function peri_init(iface)
    local self = {
        faulted = false,
        last_fault = "",
        fault_counts = {},
        auto_cf = true,
        type = peripheral.getType(iface),
        device = peripheral.wrap(iface)
    }

    -- initialization process (re-map)

    for key, func in pairs(self.device) do
        self.fault_counts[key] = 0
        self.device[key] = function (...)
            local return_table = table.pack(pcall(func, ...))

            local status = return_table[1]
            table.remove(return_table, 1)

            if status then
                -- auto fault clear
                if self.auto_cf then self.faulted = false end
                if _ppm_sys.auto_cf then _ppm_sys.faulted = false end

                self.fault_counts[key] = 0

                return table.unpack(return_table)
            else
                local result = return_table[1]

                -- function failed
                self.faulted = true
                self.last_fault = result

                _ppm_sys.faulted = true
                _ppm_sys.last_fault = result

                if not _ppm_sys.mute and (self.fault_counts[key] % REPORT_FREQUENCY == 0) then
                    local count_str = ""
                    if self.fault_counts[key] > 0 then
                        count_str = " [" .. self.fault_counts[key] .. " total faults]"
                    end

                    log.error(util.c("PPM: protected ", key, "() -> ", result, count_str))
                end

                self.fault_counts[key] = self.fault_counts[key] + 1

                if result == "Terminated" then
                    _ppm_sys.terminate = true
                end

                return ACCESS_FAULT
            end
        end
    end

    -- fault management functions

    local function clear_fault() self.faulted = false end
    local function get_last_fault() return self.last_fault end
    local function is_faulted() return self.faulted end
    local function is_ok() return not self.faulted end

    local function enable_afc() self.auto_cf = true end
    local function disable_afc() self.auto_cf = false end

    -- append to device functions

    self.device.__p_clear_fault = clear_fault
    self.device.__p_last_fault  = get_last_fault
    self.device.__p_is_faulted  = is_faulted
    self.device.__p_is_ok       = is_ok
    self.device.__p_enable_afc  = enable_afc
    self.device.__p_disable_afc = disable_afc

    return {
        type = self.type,
        dev = self.device
    }
end

----------------------
-- PUBLIC FUNCTIONS --
----------------------

-- REPORTING --

-- silence error prints
function ppm.disable_reporting()
    _ppm_sys.mute = true
end

-- allow error prints
function ppm.enable_reporting()
    _ppm_sys.mute = false
end

-- FAULT MEMORY --

-- enable automatically clearing fault flag
function ppm.enable_afc()
    _ppm_sys.auto_cf = true
end

-- disable automatically clearing fault flag
function ppm.disable_afc()
    _ppm_sys.auto_cf = false
end

-- clear fault flag
function ppm.clear_fault()
    _ppm_sys.faulted = false
end

-- check fault flag
function ppm.is_faulted()
    return _ppm_sys.faulted
end

-- get the last fault message
function ppm.get_last_fault()
    return _ppm_sys.last_fault
end

-- TERMINATION --

-- if a caught error was a termination request
function ppm.should_terminate()
    return _ppm_sys.terminate
end

-- MOUNTING --

-- mount all available peripherals (clears mounts first)
function ppm.mount_all()
    local ifaces = peripheral.getNames()

    _ppm_sys.mounts = {}

    for i = 1, #ifaces do
        _ppm_sys.mounts[ifaces[i]] = peri_init(ifaces[i])

        log.info(util.c("PPM: found a ", _ppm_sys.mounts[ifaces[i]].type, " (", ifaces[i], ")"))
    end

    if #ifaces == 0 then
        log.warning("PPM: mount_all() -> no devices found")
    end
end

-- mount a particular device
---@param iface string CC peripheral interface
---@return string|nil type, table|nil device
function ppm.mount(iface)
    local ifaces = peripheral.getNames()
    local pm_dev = nil
    local pm_type = nil

    for i = 1, #ifaces do
        if iface == ifaces[i] then
            _ppm_sys.mounts[iface] = peri_init(iface)

            pm_type = _ppm_sys.mounts[iface].type
            pm_dev = _ppm_sys.mounts[iface].dev

            log.info(util.c("PPM: mount(", iface, ") -> found a ", pm_type))
            break
        end
    end

    return pm_type, pm_dev
end

-- handle peripheral_detach event
---@param iface string CC peripheral interface
---@return string|nil type, table|nil device
function ppm.handle_unmount(iface)
    local pm_dev = nil
    local pm_type = nil

    -- what got disconnected?
    local lost_dev = _ppm_sys.mounts[iface]

    if lost_dev then
        pm_type = lost_dev.type
        pm_dev = lost_dev.dev

        log.warning(util.c("PPM: lost device ", pm_type, " mounted to ", iface))
    else
        log.error(util.c("PPM: lost device unknown to the PPM mounted to ", iface))
    end

    return pm_type, pm_dev
end

-- GENERAL ACCESSORS --

-- list all available peripherals
---@return table names
function ppm.list_avail()
    return peripheral.getNames()
end

-- list mounted peripherals
---@return table mounts
function ppm.list_mounts()
    return _ppm_sys.mounts
end

-- get a mounted peripheral by side/interface
---@param iface string CC peripheral interface
---@return table|nil device function table
function ppm.get_periph(iface)
    if _ppm_sys.mounts[iface] then
        return _ppm_sys.mounts[iface].dev
    else return nil end
end

-- get a mounted peripheral type by side/interface
---@param iface string CC peripheral interface
---@return string|nil type
function ppm.get_type(iface)
    if _ppm_sys.mounts[iface] then
        return _ppm_sys.mounts[iface].type
    else return nil end
end

-- get all mounted peripherals by type
---@param name string type name
---@return table devices device function tables
function ppm.get_all_devices(name)
    local devices = {}

    for _, data in pairs(_ppm_sys.mounts) do
        if data.type == name then
            table.insert(devices, data.dev)
        end
    end

    return devices
end

-- get a mounted peripheral by type (if multiple, returns the first)
---@param name string type name
---@return table|nil device function table
function ppm.get_device(name)
    local device = nil

    for side, data in pairs(_ppm_sys.mounts) do
        if data.type == name then
            device = data.dev
            break
        end
    end

    return device
end

-- SPECIFIC DEVICE ACCESSORS --

-- get the fission reactor (if multiple, returns the first)
---@return table|nil reactor function table
function ppm.get_fission_reactor()
    return ppm.get_device("fissionReactor") or ppm.get_device("fissionReactorLogicAdapter")
end

-- get the wireless modem (if multiple, returns the first)
--
-- if this is in a CraftOS emulated environment, wired modems will be used instead
---@return table|nil modem function table
function ppm.get_wireless_modem()
    local w_modem = nil
    local emulated_env = periphemu ~= nil

    for _, device in pairs(_ppm_sys.mounts) do
        if device.type == "modem" and (emulated_env or device.dev.isWireless()) then
            w_modem = device.dev
            break
        end
    end

    return w_modem
end

-- list all connected monitors
---@return table monitors
function ppm.get_monitor_list()
    local list = {}

    for iface, device in pairs(_ppm_sys.mounts) do
        if device.type == "monitor" then
            list[iface] = device
        end
    end

    return list
end

return ppm
