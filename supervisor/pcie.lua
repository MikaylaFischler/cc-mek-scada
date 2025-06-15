--
-- PCIe - Borrowed the name of that protocol for fun (this manages physical peripherals)
--

local log     = require("scada-common.log")
local network = require("scada-common.network")
local ppm     = require("scada-common.ppm")

local databus = require("supervisor.databus")

local pcie_bus = {}

local bus = {
    c_wired = false, ---@type string|false wired comms modem
    c_nic = nil,     ---@type nic core nic
    p_nic = nil      ---@type nic|nil pocket nic
}

-- network cards
---@class _svr_pcie_nic
---@field core nic the core comms NIC
---@field pocket nic the pocket NIC
pcie_bus.nic = {
    -- close all channels then open a specified one on all nics
    ---@param channel integer
    reset_open = function (channel)
        bus.c_nic.closeAll()
        bus.c_nic.open(channel)

        if bus.p_nic then
            bus.p_nic.closeAll()
            bus.p_nic.open(channel)
        end
    end
}

-- initialize peripherals
---@param config svr_config
---@param println function
function pcie_bus.init(config, println)
    -- setup networking peripheral(s)
    local core_modem, core_iface = ppm.get_wireless_modem()
    if type(config.WiredModem) == "string" then
        bus.c_wired = config.WiredModem
        core_modem = ppm.get_wired_modem(config.WiredModem)
    end

    if not (core_modem and core_iface) then
        println("startup> core comms modem not found")
        log.fatal("no core comms modem on startup")
        return
    end

    bus.c_nic = network.nic(core_iface, core_modem)

    if config.WirelessModem and config.WiredModem then
        local pocket_modem, pocket_iface = ppm.get_wireless_modem()

        if not (pocket_modem and pocket_iface) then
            println("startup> pocket wireless modem not found")
            log.fatal("no pocket wireless modem on startup")
            return
        end

        bus.p_nic = network.nic(pocket_iface, pocket_modem)
    end

    pcie_bus.nic.core = bus.c_nic
    pcie_bus.nic.pocket = bus.p_nic or bus.c_nic

    databus.tx_hw_c_modem(true)
    databus.tx_hw_p_modem(config.WirelessModem)
end

-- handle the connecting of a device
---@param iface string
---@param type string
---@param device table
---@param println function
function pcie_bus.connect(iface, type, device, println)
    if type == "modem" then
        ---@cast device Modem
        if device.isWireless() then
            if not (bus.c_wired or bus.c_nic.is_connected()) then
                -- reconnected comms modem
                bus.c_nic.connect(device)

                println("core comms modem reconnected")
                log.info("core comms modem reconnected")

                databus.tx_hw_c_modem(true)
            elseif bus.p_nic and not bus.p_nic.is_connected() then
                -- reconnected pocket modem
                bus.p_nic.connect(device)

                println("pocket modem reconnected")
                log.info("pocket modem reconnected")

                databus.tx_hw_p_modem(true)
            else
                log.info("unused wireless modem reconnected")
            end
        elseif iface == bus.c_wired then
            -- reconnected wired comms modem
            bus.c_nic.connect(device)

            println("core comms modem reconnected")
            log.info("core comms modem reconnected")

            databus.tx_hw_c_modem(true)
        else
            log.info("wired modem reconnected")
        end
    end
end

-- handle the removal of a device
---@param type string
---@param device table
---@param println function
function pcie_bus.remove(type, device, println)
    if type == "modem" then
        ---@cast device Modem
        if bus.c_nic.is_modem(device) then
            bus.c_nic.disconnect()

            println("core comms modem disconnected")
            log.warning("core comms modem disconnected")

            local other_modem = ppm.get_wireless_modem()
            if other_modem and not bus.c_wired then
                log.info("found another wireless modem, using it for comms")
                bus.c_nic.connect(other_modem)
            else
                databus.tx_hw_c_modem(false)
            end
        elseif bus.p_nic and bus.p_nic.is_modem(device) then
            bus.p_nic.disconnect()

            println("pocket modem disconnected")
            log.warning("pocket modem disconnected")

            local other_modem = ppm.get_wireless_modem()
            if other_modem then
                log.info("found another wireless modem, using it for pocket comms")
                bus.p_nic.connect(other_modem)
            else
                databus.tx_hw_p_modem(false)
            end
        else
            log.warning("non-comms modem disconnected")
        end
    end
end

-- check if a dedicated pocket nic is in use
function pcie_bus.has_pocket_nic() return bus.p_nic ~= nil end

return pcie_bus
