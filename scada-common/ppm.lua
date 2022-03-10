-- #REQUIRES log.lua

--
-- Protected Peripheral Manager
--

local self = {
    mounts = {}
}

-- wrap peripheral calls with lua protected call
-- ex. reason: we don't want a disconnect to crash the program before a SCRAM
local peri_init = function (device)
    for key, func in pairs(device) do
        device[key] = function (...)
            local status, result = pcall(func, ...)

            if status then
                return result
            else
                -- function failed
                log._error("protected " .. key .. "() -> " .. result)
                return nil
            end
        end
    end
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
function unmount_handler(iface)
    -- what got disconnected?
    local lost_dev = self.mounts[iface]
    local type = lost_dev.type
    
    log._warning("PMGR: lost device " .. type .. " mounted to " .. iface)

    return self.mounts[iface]
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
