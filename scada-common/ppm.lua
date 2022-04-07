-- #REQUIRES log.lua

--
-- Protected Peripheral Manager
--

----------------------------
-- PRIVATE DATA/FUNCTIONS --
----------------------------

local self = {
    mounts = {},
    mute = false
}

-- wrap peripheral calls with lua protected call
-- ex. reason: we don't want a disconnect to crash the program before a SCRAM
local peri_init = function (device)
    for key, func in pairs(device) do
        device[key] = function (...)
            local status, result = pcall(func, ...)

            if status then
                -- assume nil is only for functions with no return, so return status
                if result == nil then
                    return true
                else
                    return result
                end
            else
                -- function failed
                if not mute then
                    log._error("PPM: protected " .. key .. "() -> " .. result)
                end
                return nil
            end
        end
    end
end

----------------------
-- PUBLIC FUNCTIONS --
----------------------

-- REPORTING --

-- silence error prints
function disable_reporting()
    self.mute = true
end

-- allow error prints
function enable_reporting()
    self.mute = false
end

-- MOUNTING --

-- mount all available peripherals (clears mounts first)
function mount_all()
    local ifaces = peripheral.getNames()

    self.mounts = {}

    for i = 1, #ifaces do
        local pm_dev = peripheral.wrap(ifaces[i])
        peri_init(pm_dev)

        self.mounts[ifaces[i]] = {
            type = peripheral.getType(ifaces[i]),
            dev = pm_dev
        }

        log._debug("PPM: found a " .. self.mounts[ifaces[i]].type)
    end

    if #ifaces == 0 then
        log._warning("PPM: mount_all() -> no devices found")
    end
end

-- mount a particular device
function mount(iface)
    local ifaces = peripheral.getNames()
    local pm_dev = nil
    local type = nil

    for i = 1, #ifaces do
        if iface == ifaces[i] then
            log._debug("PPM: mount(" .. iface .. ") -> found a " .. peripheral.getType(iface))

            type = peripheral.getType(iface)
            pm_dev = peripheral.wrap(iface)
            peri_init(pm_dev)

            self.mounts[iface] = {
                type = peripheral.getType(iface),
                dev = pm_dev
            }
            break
        end
    end

    return type, pm_dev
end

-- handle peripheral_detach event
function handle_unmount(iface)
    -- what got disconnected?
    local lost_dev = self.mounts[iface]
    local type = lost_dev.type
    
    log._warning("PPM: lost device " .. type .. " mounted to " .. iface)

    return lost_dev
end

-- GENERAL ACCESSORS --

-- list all available peripherals
function list_avail()
    return peripheral.getNames()
end

-- list mounted peripherals
function list_mounts()
    return self.mounts
end

-- get a mounted peripheral by side/interface
function get_periph(iface)
    return self.mounts[iface].dev
end

-- get a mounted peripheral type by side/interface
function get_type(iface)
    return self.mounts[iface].type
end

-- get all mounted peripherals by type
function get_all_devices(name)
    local devices = {}

    for side, data in pairs(self.mounts) do
        if data.type == name then
            table.insert(devices, data.dev)
        end
    end

    return devices
end

-- get a mounted peripheral by type (if multiple, returns the first)
function get_device(name)
    local device = nil

    for side, data in pairs(self.mounts) do
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

    for side, device in pairs(self.mounts) do
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
