-- #REQUIRES log.lua

--
-- Protected Peripheral Manager
--

function ppm()
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
    local mount_all = function ()
        local ifaces = peripheral.getNames()

        self.mounts = {}

        for i = 1, #ifaces do
            local pm_dev = peripheral.wrap(ifaces[i])
            peri_init(pm_dev)
            self.mounts[ifaces[i]] = { peripheral.getType(ifaces[i]), pm_dev }
        end
    end

    -- mount a particular device
    local mount = function (name)
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
    local unmount_handler = function (iface)
        -- what got disconnected?
        local lost_dev = self.mounts[iface]
        local type = lost_dev.type
        
        log._warning("PMGR: lost device " .. type .. " mounted to " .. iface)

        return self.mounts[iface]
    end

    -- list all available peripherals
    local list_avail = function ()
        return peripheral.getNames()
    end

    -- list mounted peripherals
    local list_mounts = function ()
        return self.mounts
    end

    -- get a mounted peripheral by side/interface
    local get_periph = function (iface)
        return self.mounts[iface].device
    end

    -- get a mounted peripheral by type
    local get_device = function (name)
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
    local list_monitors = function ()
        local monitors = {}

        for side, data in pairs(self.mounts) do
            if data.type == "monitor" then
                monitors[side] = data.device
            end
        end

        return monitors
    end

    return {
        mount_all = mount_all,
        mount = mount,
        umount = unmount_handler,
        list_avail = list_avail,
        list_mounts = list_mounts,
        get_periph = get_periph,
        get_device = get_device,
        list_monitors = list_monitors
    }
end
