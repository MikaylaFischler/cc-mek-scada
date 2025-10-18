--
-- PCIe - Borrowed the name of that protocol for fun (this manages physical peripherals)
--

local log     = require("scada-common.log")
local network = require("scada-common.network")
local ppm     = require("scada-common.ppm")

local databus = require("supervisor.databus")

local pcie_bus = {}

local bus = {
    wired_modem = false, ---@type string|false wired comms modem name
    wl_nic = nil,        ---@type nic|nil wireless nic
    wd_nic = nil         ---@type nic|nil wired nic
}

-- network cards
---@class _svr_pcie_nic
---@field wl nic|nil the wireless comms NIC
---@field wd nic|nil the wired comms NIC
pcie_bus.nic = {
    -- close all channels and then open the configured channels on the appropriate nic(s)
    ---@param config svr_config
    reset_open = function (config)
        if bus.wl_nic then
            bus.wl_nic.closeAll()

            if config.PLC_Listen % 2 == 0 then bus.wl_nic.open(config.PLC_Channel) end
            if config.RTU_Listen % 2 == 0 then bus.wl_nic.open(config.RTU_Channel) end
            if config.CRD_Listen % 2 == 0 then bus.wl_nic.open(config.CRD_Channel) end
            if config.PocketEnabled then bus.wl_nic.open(config.PKT_Channel) end
        end

        if bus.wd_nic then
            bus.wd_nic.closeAll()

            if config.PLC_Listen > 0 then bus.wd_nic.open(config.PLC_Channel) end
            if config.RTU_Listen > 0 then bus.wd_nic.open(config.RTU_Channel) end
            if config.CRD_Listen > 0 then bus.wd_nic.open(config.CRD_Channel) end
        end
    end,
    -- get the requested nic by interface
    ---@param iface string
    ---@return nic|nil
    get = function(iface)
        local dev = ppm.get_device(iface)

        if dev then
            if bus.wl_nic and bus.wl_nic.is_modem(dev) then return bus.wl_nic end
            if bus.wd_nic and bus.wd_nic.is_modem(dev) then return bus.wd_nic end
        end

        return nil
    end,
    -- cards by interface
    ---@type { string: nic }
    cards = {}
}

-- initialize peripherals
---@param config svr_config
---@param println function
---@return boolean success
function pcie_bus.init(config, println)
    -- setup networking peripheral(s)
    if type(config.WiredModem) == "string" then
        bus.wired_modem = config.WiredModem

        local wired_modem = ppm.get_modem(bus.wired_modem)

        if not (wired_modem and bus.wired_modem) then
            println("startup> wired comms modem not found")
            log.fatal("no wired comms modem on startup")
            return false
        end

        bus.wd_nic = network.nic(wired_modem)
        pcie_bus.nic.cards[bus.wired_modem] = bus.wd_nic
    end

    if config.WirelessModem then
        local wireless_modem, wireless_iface = ppm.get_wireless_modem()

        if not (wireless_modem and wireless_iface) then
            println("startup> wireless comms modem not found")
            log.fatal("no wireless comms modem on startup")
            return false
        end

        bus.wl_nic = network.nic(wireless_modem)
        pcie_bus.nic.cards[wireless_iface] = bus.wl_nic
    end

    pcie_bus.nic.wl = bus.wl_nic
    pcie_bus.nic.wd = bus.wd_nic

    databus.tx_hw_wl_modem(true)
    databus.tx_hw_wd_modem(config.WirelessModem)

    return true
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
            if bus.wl_nic and not bus.wl_nic.is_connected() then
                -- reconnected wireless comms modem
                bus.wl_nic.connect(device)
                pcie_bus.nic.cards[iface] = bus.wl_nic

                println("wireless comms modem reconnected")
                log.info("wireless comms modem reconnected")

                databus.tx_hw_wl_modem(true)
            else
                log.info("unused wireless modem reconnected")
            end
        elseif bus.wd_nic and (iface == bus.wired_modem) then
            -- reconnected wired comms modem
            bus.wd_nic.connect(device)
            pcie_bus.nic.cards[iface] = bus.wd_nic

            println("wired comms modem reconnected")
            log.info("wired comms modem reconnected")

            databus.tx_hw_wl_modem(true)
        else
            log.info("wired modem reconnected")
        end
    end
end

-- handle the removal of a device
---@param iface string
---@param type string
---@param device table
---@param println function
function pcie_bus.remove(iface, type, device, println)
    if type == "modem" then
        pcie_bus.nic.cards[iface] = nil

        ---@cast device Modem
        if bus.wl_nic and bus.wl_nic.is_modem(device) then
            bus.wl_nic.disconnect()

            println("wireless comms modem disconnected")
            log.warning("wireless comms modem disconnected")

            local other_modem = ppm.get_wireless_modem()
            if other_modem then
                log.info("found another wireless modem, using it for comms")
                bus.wl_nic.connect(other_modem)
            else
                databus.tx_hw_wl_modem(false)
            end
        elseif bus.wd_nic and bus.wd_nic.is_modem(device) then
            bus.wd_nic.disconnect()

            println("wired modem disconnected")
            log.warning("wired modem disconnected")

            databus.tx_hw_wd_modem(false)
        else
            log.warning("non-comms modem disconnected")
        end
    end
end

return pcie_bus
