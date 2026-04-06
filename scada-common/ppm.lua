--
-- Protected Peripheral Manager
--

local log  = require("scada-common.log")
local util = require("scada-common.util")

---@class ppm
local ppm = {}

local ACCESS_FAULT        = nil                 ---@type nil
local UNDEFINED_FIELD     = "__PPM_UNDEF_FIELD__"
local VIRTUAL_DEVICE_TYPE = "ppm_vdev"

ppm.ACCESS_FAULT          = ACCESS_FAULT
ppm.UNDEFINED_FIELD       = UNDEFINED_FIELD
ppm.VIRTUAL_DEVICE_TYPE   = VIRTUAL_DEVICE_TYPE

----------------------------
-- PRIVATE DATA/FUNCTIONS --
----------------------------

local REPORT_FREQUENCY = 20 -- log every 20 faults per function

local _ppm = {
    mounts = {},    ---@type { [string]: ppm_entry }
    next_vid = 0,
    auto_cf = false,
    faulted = false,
    last_fault = "",
    terminate = false,
    mute = false
}

-- Wrap peripheral calls with lua protected call as we don't want a disconnect to crash a program.
-- Additionally provides peripheral-specific fault checks (auto-clear fault defaults to true).<br>
-- Note: assumes iface is a valid peripheral.
---@param iface string CC peripheral interface
local function peri_init(iface)
    local self = {
        faulted = false,
        last_fault = "",
        fault_counts = {},          ---@type { [string]: integer }
        auto_cf = true,
        type = VIRTUAL_DEVICE_TYPE, ---@type string
        device = {}                 ---@type ppm_generic
    }

    if iface ~= "__virtual__" then
        self.type = peripheral.getType(iface)
        self.device = peripheral.wrap(iface)
    end

    -- create a protected version of a peripheral function call
    ---@nodiscard
    ---@param key string function name
    ---@param func function function
    ---@return function method protected version of the function
    local function protect_peri_function(key, func)
        return function (...)
            local return_table = table.pack(pcall(func, ...))

            local status = return_table[1]
            table.remove(return_table, 1)

            if status then
                -- auto fault clear
                if self.auto_cf then self.faulted = false end
                if _ppm.auto_cf then _ppm.faulted = false end

                self.fault_counts[key] = 0

                return table.unpack(return_table)
            else
                local result = return_table[1]

                -- function failed
                self.faulted = true
                self.last_fault = result

                _ppm.faulted = true
                _ppm.last_fault = result

                if not _ppm.mute and (self.fault_counts[key] % REPORT_FREQUENCY == 0) then
                    local count_str = ""
                    if self.fault_counts[key] > 0 then
                        count_str = " [" .. self.fault_counts[key] .. " total faults]"
                    end

                    log.error(util.c("PPM: [@", iface, "] protected ", key, "() -> ", result, count_str))
                end

                self.fault_counts[key] = self.fault_counts[key] + 1

                if result == "Terminated" then _ppm.terminate = true end

                return ACCESS_FAULT, result
            end
        end
    end

    -- generic fault management & monitoring functions

    local function clear_fault() self.faulted = false end
    local function get_last_fault() return self.last_fault end
    local function is_faulted() return self.faulted end
    local function is_ok() return not self.faulted end

    -- check if a peripheral has any faulted functions<br>
    -- contrasted with is_faulted() and is_ok() as those only check if the last operation failed,
    -- unless auto fault clearing is disabled, at which point faults become sticky faults
    local function is_healthy()
        for _, v in pairs(self.fault_counts) do if v > 0 then return false end end
        return true
    end

    local function enable_afc() self.auto_cf = true end
    local function disable_afc() self.auto_cf = false end

    -- append PPM functions to device functions

    self.device.__p_clear_fault = clear_fault
    self.device.__p_last_fault  = get_last_fault
    self.device.__p_is_faulted  = is_faulted
    self.device.__p_is_ok       = is_ok
    self.device.__p_is_healthy  = is_healthy
    self.device.__p_enable_afc  = enable_afc
    self.device.__p_disable_afc = disable_afc

    ---@class PPMDevice
    local dev = self.device

    dev.__p_clear_fault = clear_fault
    dev.__p_last_fault  = get_last_fault
    dev.__p_is_faulted  = is_faulted
    dev.__p_is_ok       = is_ok
    dev.__p_is_healthy  = is_healthy
    dev.__p_enable_afc  = enable_afc
    dev.__p_disable_afc = disable_afc

    -- peripheral call initialization process (re-map)

    for key, func in pairs(self.device) do
        self.fault_counts[key] = 0
        self.device[key] = protect_peri_function(key, func)
    end

    -- add default index function to catch undefined indicies

    local mt = {
        __index = function (_, key)
            -- try to find the function in case it was added (multiblock formed)
            local funcs = peripheral.wrap(iface)
            if (type(funcs) == "table") and (type(funcs[key]) == "function") then
                -- add this function then return it
                self.fault_counts[key] = 0
                self.device[key] = protect_peri_function(key, funcs[key])

                log.info(util.c("PPM: [@", iface, "] initialized previously undefined field ", key, "()"))

                return self.device[key]
            end

            -- function still missing, return an undefined function handler
            -- note: code should avoid storing functions for multiblocks and instead try to index them again
            return (function ()
                -- this will continuously be counting calls here as faults
                if self.fault_counts[key] == nil then self.fault_counts[key] = 0 end

                -- function failed
                self.faulted = true
                self.last_fault = UNDEFINED_FIELD

                _ppm.faulted = true
                _ppm.last_fault = UNDEFINED_FIELD

                if not _ppm.mute and (self.fault_counts[key] % REPORT_FREQUENCY == 0) then
                    local count_str = ""
                    if self.fault_counts[key] > 0 then
                        count_str = " [" .. self.fault_counts[key] .. " total calls]"
                    end

                    log.error(util.c("PPM: [@", iface, "] caught undefined function ", key, "()", count_str))
                end

                self.fault_counts[key] = self.fault_counts[key] + 1

                return ACCESS_FAULT, UNDEFINED_FIELD
            end)
        end
    }

    setmetatable(self.device, mt)

    ---@class ppm_entry
    local entry = { type = self.type, dev = self.device }

    return entry
end

----------------------
-- PUBLIC FUNCTIONS --
----------------------

-- REPORTING --

-- silence error prints
function ppm.disable_reporting() _ppm.mute = true end

-- allow error prints
function ppm.enable_reporting() _ppm.mute = false end

-- FAULT MEMORY --

-- enable automatically clearing fault flag
function ppm.enable_afc() _ppm.auto_cf = true end

-- disable automatically clearing fault flag
function ppm.disable_afc() _ppm.auto_cf = false end

-- clear fault flag
function ppm.clear_fault() _ppm.faulted = false end

-- check fault flag
---@nodiscard
function ppm.is_faulted() return _ppm.faulted end

-- get the last fault message
---@nodiscard
function ppm.get_last_fault() return _ppm.last_fault end

-- TERMINATION --

-- if a caught error was a termination request
---@nodiscard
function ppm.should_terminate() return _ppm.terminate end

-- MOUNTING --

-- mount all available peripherals (clears mounts first)
function ppm.mount_all()
    local ifaces = peripheral.getNames()

    _ppm.mounts = {}

    for i = 1, #ifaces do
        _ppm.mounts[ifaces[i]] = peri_init(ifaces[i])

        log.info(util.c("PPM: found a ", _ppm.mounts[ifaces[i]].type, " (", ifaces[i], ")"))
    end

    if #ifaces == 0 then
        log.warning("PPM: mount_all() -> no devices found")
    end
end

-- mount a specified device
---@nodiscard
---@param iface string CC peripheral interface
---@return string|nil type, ppm_generic|nil device
function ppm.mount(iface)
    local ifaces = peripheral.getNames()
    local pm_dev = nil
    local pm_type = nil

    for i = 1, #ifaces do
        if iface == ifaces[i] then
            _ppm.mounts[iface] = peri_init(iface)

            pm_type = _ppm.mounts[iface].type
            pm_dev = _ppm.mounts[iface].dev

            log.info(util.c("PPM: mount(", iface, ") -> found a ", pm_type))
            break
        end
    end

    return pm_type, pm_dev
end

-- unmount and remount a specified device
---@nodiscard
---@param iface string CC peripheral interface
---@return string|nil type, ppm_generic|nil device
function ppm.remount(iface)
    local ifaces = peripheral.getNames()
    local pm_dev = nil
    local pm_type = nil

    for i = 1, #ifaces do
        if iface == ifaces[i] then
            log.info(util.c("PPM: remount(", iface, ") -> is a ", pm_type))
            ppm.unmount(_ppm.mounts[iface].dev)

            _ppm.mounts[iface] = peri_init(iface)

            pm_type = _ppm.mounts[iface].type
            pm_dev = _ppm.mounts[iface].dev

            log.info(util.c("PPM: remount(", iface, ") -> remounted a ", pm_type))
            break
        end
    end

    return pm_type, pm_dev
end

-- mount a virtual placeholder device
---@nodiscard
---@return string type, ppm_generic device
function ppm.mount_virtual()
    local iface = "ppm_vdev_" .. _ppm.next_vid

    _ppm.mounts[iface] = peri_init("__virtual__")
    _ppm.next_vid = _ppm.next_vid + 1

    log.info(util.c("PPM: mount_virtual() -> allocated new virtual device ", iface))

    return _ppm.mounts[iface].type, _ppm.mounts[iface].dev
end

-- manually unmount a peripheral from the PPM
---@param device ppm_generic device table
function ppm.unmount(device)
    if device then
        for iface, data in pairs(_ppm.mounts) do
            if data.dev == device then
                log.warning(util.c("PPM: manually unmounted ", data.type, " mounted to ", iface))
                _ppm.mounts[iface] = nil
                break
            end
        end
    end
end

-- handle peripheral_detach event
---@nodiscard
---@param iface string CC peripheral interface
---@return string|nil type, ppm_generic|nil device
function ppm.handle_unmount(iface)
    local pm_dev = nil
    local pm_type = nil

    -- what got disconnected?
    local lost_dev = _ppm.mounts[iface]

    if lost_dev then
        pm_type = lost_dev.type
        pm_dev = lost_dev.dev

        log.warning(util.c("PPM: lost device ", pm_type, " mounted to ", iface))
    else
        log.error(util.c("PPM: lost device unknown to the PPM mounted to ", iface))
    end

    _ppm.mounts[iface] = nil

    return pm_type, pm_dev
end

-- log all mounts, to be used if `ppm.mount_all` is called before logging is ready
function ppm.log_mounts()
    for iface, mount in pairs(_ppm.mounts) do
        log.info(util.c("PPM: had found a ", mount.type, " (", iface, ")"))
    end

    if util.table_len(_ppm.mounts) == 0 then
        log.warning("PPM: no devices had been found")
    end
end

-- GENERAL ACCESSORS --

-- list all available peripherals
---@nodiscard
---@return string[] names
function ppm.list_avail() return peripheral.getNames() end

-- list mounted peripherals
---@nodiscard
---@return { [string]: ppm_entry } mounts
function ppm.list_mounts()
    local list = {}
    for k, v in pairs(_ppm.mounts) do list[k] = v end
    return list
end

-- get a mounted peripheral side/interface by device table
---@nodiscard
---@param device ppm_generic device table
---@return string|nil iface CC peripheral interface
function ppm.get_iface(device)
    if device then
        for iface, data in pairs(_ppm.mounts) do
            if data.dev == device then return iface end
        end
    end

    return nil
end

-- get a mounted peripheral by side/interface
---@nodiscard
---@param iface string CC peripheral interface
---@return ppm_generic|nil device function table
function ppm.get_periph(iface)
    if _ppm.mounts[iface] then
        return _ppm.mounts[iface].dev
    else return nil end
end

-- get a mounted peripheral type by side/interface
---@nodiscard
---@param iface string CC peripheral interface
---@return string|nil type
function ppm.get_type(iface)
    if _ppm.mounts[iface] then
        return _ppm.mounts[iface].type
    else return nil end
end

-- get all mounted peripherals by type
---@nodiscard
---@param type string type name
---@return ppm_generic[] devices device function tables
function ppm.get_all_devices(type)
    local devices = {}

    for _, data in pairs(_ppm.mounts) do
        if data.type == type then
            table.insert(devices, data.dev)
        end
    end

    return devices
end

-- get a mounted peripheral by type (if multiple, returns the first)
---@nodiscard
---@param type string type name
---@return ppm_generic|nil device, string|nil iface device and interface
function ppm.get_device(type)
    local device, d_iface = nil, nil

    for iface, data in pairs(_ppm.mounts) do
        if data.type == type then
            device = data.dev
            d_iface = iface
            break
        end
    end

    return device, d_iface
end

-- SPECIFIC DEVICE ACCESSORS --

-- get the fission reactor (if multiple, returns the first)
---@nodiscard
---@return FissionReactor|nil reactor, string|nil iface reactor and interface
function ppm.get_fission_reactor()
    local dev, iface = ppm.get_device("fissionReactorLogicAdapter")

    ---@cast dev FissionReactor|nil

    return dev, iface
end

-- get a modem by name
---@nodiscard
---@param iface string CC peripheral interface
---@return Modem|nil modem function table
function ppm.get_modem(iface)
    local modem  = nil
    local device = _ppm.mounts[iface]

    if device and device.type == "modem" then modem = device.dev end

    ---@cast modem Modem|nil

    return modem
end

-- get the wireless modem (if multiple, returns the first)<br>
-- if this is in a CraftOS emulated environment, wired modems will be used instead
---@nodiscard
---@return Modem|nil modem, string|nil iface
function ppm.get_wireless_modem()
    local w_modem, w_iface = nil, nil
    local emulated_env = periphemu ~= nil

    for iface, device in pairs(_ppm.mounts) do
        if device.type == "modem" and (emulated_env or device.dev.isWireless()) then
            w_modem = device.dev
            w_iface = iface
            break
        end
    end

    return w_modem, w_iface
end

-- list all connected wired modems
---@nodiscard
---@return { [string]: ppm_entry } modems
function ppm.get_wired_modem_list()
    local list = {}

    for iface, device in pairs(_ppm.mounts) do
        if device.type == "modem" and not device.dev.isWireless() then list[iface] = device end
    end

    return list
end

-- list all connected monitors
---@nodiscard
---@return { [string]: ppm_entry } monitors
function ppm.get_monitor_list()
    local list = {}

    for iface, device in pairs(_ppm.mounts) do
        if device.type == "monitor" then list[iface] = device end
    end

    return list
end

-- HELPER FUNCTIONS

-- get the block size of a monitor given its width and height <b>at a text scale of 0.5</b>
---@nodiscard
---@param width integer character width
---@param height integer character height
---@return integer block_width, integer block_height
function ppm.monitor_block_size(width, height)
    return math.floor((width - 15) / 21) + 1, math.floor((height - 10) / 14) + 1
end

return ppm
