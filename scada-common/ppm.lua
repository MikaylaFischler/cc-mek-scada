-- #REQUIRES log.lua

--
-- Protected Peripheral Manager
--

ACCESS_FAULT = nil

----------------------------
-- PRIVATE DATA/FUNCTIONS --
----------------------------

local _ppm_sys = {
    mounts = {},
    auto_cf = false,
    faulted = false,
    terminate = false,
    mute = false
}

-- wrap peripheral calls with lua protected call
-- we don't want a disconnect to crash a program
-- also provides peripheral-specific fault checks (auto-clear fault defaults to true)
local peri_init = function (iface)
    local self = {
        faulted = false,
        auto_cf = true,
        type = peripheral.getType(iface),
        device = peripheral.wrap(iface)
    }

    -- initialization process (re-map)

    for key, func in pairs(self.device) do
        self.device[key] = function (...)
            local status, result = pcall(func, ...)

            if status then
                -- auto fault clear
                if self.auto_cf then self.faulted = false end
                if _ppm_sys.auto_cf then _ppm_sys.faulted = false end
                return result
            else
                -- function failed
                self.faulted = true
                _ppm_sys.faulted = true

                if not _ppm_sys.mute then
                    log._error("PPM: protected " .. key .. "() -> " .. result)
                end

                if result == "Terminated" then
                    _ppm_sys.terminate = true
                end

                return ACCESS_FAULT
            end
        end
    end

    -- fault management functions

    local clear_fault = function () self.faulted = false end
    local is_faulted = function () return self.faulted end
    local is_ok = function () return not self.faulted end

    local enable_afc = function () self.auto_cf = true end
    local disable_afc = function () self.auto_cf = false end

    -- append to device functions

    self.device.__p_clear_fault = clear_fault
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
function disable_reporting()
    _ppm_sys.mute = true
end

-- allow error prints
function enable_reporting()
    _ppm_sys.mute = false
end

-- FAULT MEMORY --

-- enable automatically clearing fault flag
function enable_afc()
    _ppm_sys.auto_cf = true
end

-- disable automatically clearing fault flag
function disable_afc()
    _ppm_sys.auto_cf = false
end

-- check fault flag
function is_faulted()
    return _ppm_sys.faulted
end

-- clear fault flag
function clear_fault()
    _ppm_sys.faulted = false
end

-- TERMINATION --

-- if a caught error was a termination request
function should_terminate()
    return _ppm_sys.terminate
end

-- MOUNTING --

-- mount all available peripherals (clears mounts first)
function mount_all()
    local ifaces = peripheral.getNames()

    _ppm_sys.mounts = {}

    for i = 1, #ifaces do
        _ppm_sys.mounts[ifaces[i]] = peri_init(ifaces[i])

        log._info("PPM: found a " .. _ppm_sys.mounts[ifaces[i]].type .. " (" .. ifaces[i] .. ")")
    end

    if #ifaces == 0 then
        log._warning("PPM: mount_all() -> no devices found")
    end
end

-- mount a particular device
function mount(iface)
    local ifaces = peripheral.getNames()
    local pm_dev = nil
    local pm_type = nil

    for i = 1, #ifaces do
        if iface == ifaces[i] then
            log._info("PPM: mount(" .. iface .. ") -> found a " .. peripheral.getType(iface))

            _ppm_sys.mounts[iface] = peri_init(iface)

            pm_type = _ppm_sys.mounts[iface].type
            pm_dev = _ppm_sys.mounts[iface].dev
            break
        end
    end

    return pm_type, pm_dev
end

-- handle peripheral_detach event
function handle_unmount(iface)
    -- what got disconnected?
    local lost_dev = _ppm_sys.mounts[iface]

    if lost_dev then
        local type = lost_dev.type
        log._warning("PPM: lost device " .. type .. " mounted to " .. iface)
    else
        log._error("PPM: lost device unknown to the PPM mounted to " .. iface)
    end

    return lost_dev
end

-- GENERAL ACCESSORS --

-- list all available peripherals
function list_avail()
    return peripheral.getNames()
end

-- list mounted peripherals
function list_mounts()
    return _ppm_sys.mounts
end

-- get a mounted peripheral by side/interface
function get_periph(iface)
    if _ppm_sys.mounts[iface] then
        return _ppm_sys.mounts[iface].dev
    else return nil end
end

-- get a mounted peripheral type by side/interface
function get_type(iface)
    if _ppm_sys.mounts[iface] then
        return _ppm_sys.mounts[iface].type
    else return nil end
end

-- get all mounted peripherals by type
function get_all_devices(name)
    local devices = {}

    for side, data in pairs(_ppm_sys.mounts) do
        if data.type == name then
            table.insert(devices, data.dev)
        end
    end

    return devices
end

-- get a mounted peripheral by type (if multiple, returns the first)
function get_device(name)
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
function get_fission_reactor()
    return get_device("fissionReactor")
end

-- get the wireless modem (if multiple, returns the first)
function get_wireless_modem()
    local w_modem = nil

    for side, device in pairs(_ppm_sys.mounts) do
        if device.type == "modem" and device.dev.isWireless() then
            w_modem = device.dev
            break
        end
    end

    return w_modem
end

-- list all connected monitors
function list_monitors()
    return get_all_devices("monitor")
end
