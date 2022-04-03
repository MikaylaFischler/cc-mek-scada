-- #REQUIRES log.lua

--
-- Protected Peripheral Manager
--

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

-- silence error prints
function disable_reporting()
    self.mute = true
end

-- allow error prints
function enable_reporting()
    self.mute = false
end

-- mount all available peripherals (clears mounts first)
function mount_all()
    local ifaces = peripheral.getNames()

    self.mounts = {}

    for i = 1, #ifaces do
        local pm_dev = peripheral.wrap(ifaces[i])
        peri_init(pm_dev)
        self.mounts[ifaces[i]] = { peripheral.getType(ifaces[i]), pm_dev }
    end

    if #ifaces == 0 then
        log._warning("PPM: mount_all() -> no devices found")
    end
end

-- mount a particular device
function mount(name)
    local ifaces = peripheral.getNames()
    local pm_dev = nil

    for i = 1, #ifaces do
        if name == peripheral.getType(ifaces[i]) then
            pm_dev = peripheral.wrap(ifaces[i])
            peri_init(pm_dev)

            self.mounts[ifaces[i]] = { 
                type = peripheral.getType(ifaces[i]), 
                device = pm_dev 
            }
            break
        end
    end

    return pm_dev
end

-- handle peripheral_detach event
function handle_unmount(iface)
    -- what got disconnected?
    local lost_dev = self.mounts[iface]
    local type = lost_dev.type
    
    log._warning("PPM: lost device " .. type .. " mounted to " .. iface)

    return lost_dev
end

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
    return self.mounts[iface].device
end

-- get a mounted peripheral type by side/interface
function get_type(iface)
    return self.mounts[iface].type
end

-- get a mounted peripheral by type
function get_device(name)
    local device = nil

    for side, data in pairs(self.mounts) do
        if data.type == name then
            device = data.device
            break
        end
    end
    
    return device
end

-- list all connected monitors
function list_monitors()
    local monitors = {}

    for side, data in pairs(self.mounts) do
        if data.type == "monitor" then
            monitors[side] = data.device
        end
    end

    return monitors
end
