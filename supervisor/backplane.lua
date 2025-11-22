--
-- Supervisor System Core Peripheral Backplane
--

local log     = require("scada-common.log")
local network = require("scada-common.network")
local ppm     = require("scada-common.ppm")
local util    = require("scada-common.util")

local databus = require("supervisor.databus")

local println = util.println

---@class supervisor_backplane
local backplane = {}

local _bp = {
    config = nil,       ---@type svr_config
    lan_iface = false,  ---@type string|false wired comms modem name

    wd_nic = nil,       ---@type nic|nil wired nic
    wl_nic = nil,       ---@type nic|nil wireless nic
    nic_map = {}        ---@type nic[] connected nics
}

-- network interfaces indexed by peripheral names
backplane.nics = _bp.nic_map

-- initialize the system peripheral backplane
---@param config svr_config
---@return boolean success
function backplane.init(config)
    _bp.lan_iface = config.WiredModem

    -- setup the wired modem, if configured
    if type(_bp.lan_iface) == "string" then
        local modem  = ppm.get_modem(_bp.lan_iface)
        local wd_nic = network.nic(modem)

        log.info("BKPLN: WIRED PHY_" .. util.trinary(modem, "UP ", "DOWN ") .. _bp.lan_iface)

        if not (modem and _bp.lan_iface) then
            println("startup> wired comms modem not found")
            log.fatal("BKPLN: no wired comms modem on startup")
            return false
        end

        _bp.wd_nic = wd_nic
        _bp.nic_map[_bp.lan_iface] = wd_nic

        wd_nic.closeAll()
        wd_nic.open(config.SVR_Channel)

        databus.tx_hw_wd_modem(true)
    end

    -- setup the wireless modem, if configured
    if config.WirelessModem then
        local modem, iface = ppm.get_wireless_modem()
        local wl_nic       = network.nic(modem)

        log.info("BKPLN: WIRELESS PHY_" .. util.trinary(modem, "UP ", "DOWN") .. (iface or ""))

        if not (modem and iface) then
            println("startup> wireless comms modem not found")
            log.fatal("BKPLN: no wireless comms modem on startup")
            return false
        end

        _bp.wl_nic = wl_nic
        _bp.nic_map[iface] = wl_nic

        wl_nic.closeAll()
        wl_nic.open(config.SVR_Channel)

        databus.tx_hw_wl_modem(true)
    end

    return true
end

-- handle a backplane peripheral attach
---@param iface string
---@param type string
---@param device table
---@param print_no_fp function
function backplane.attach(iface, type, device, print_no_fp)
    if type == "modem" then
        ---@cast device Modem

        local m_is_wl = device.isWireless()

        log.info(util.c("BKPLN: ", util.trinary(m_is_wl, "WIRELESS", "WIRED"), " PHY_ATTACH ", iface))

        if _bp.wd_nic and (_bp.lan_iface == iface) then
            -- connect this as the wired NIC
            _bp.wd_nic.connect(device)
            _bp.nic_map[iface] = _bp.wd_nic

            log.info("BKPLN: WIRED PHY_UP " .. iface)
            print_no_fp("wired comms modem reconnected")

            databus.tx_hw_wd_modem(true)
        elseif _bp.wl_nic and (not _bp.wl_nic.is_connected()) and m_is_wl then
            -- connect this as the wireless NIC
            _bp.wl_nic.connect(device)
            _bp.nic_map[iface] = _bp.wl_nic

            log.info("BKPLN: WIRELESS PHY_UP " .. iface)
            print_no_fp("wireless comms modem reconnected")

            databus.tx_hw_wl_modem(true)
        elseif _bp.wl_nic and m_is_wl then
            -- the wireless NIC already has a modem
            device.closeAll()

            print_no_fp("standby wireless modem connected")
            log.info("BKPLN: standby wireless modem connected")
        else
            device.closeAll()

            print_no_fp("unassigned modem connected")
            log.warning("BKPLN: unassigned modem connected")
        end
    end
end

-- handle a backplane peripheral detach
---@param iface string
---@param type string
---@param device table
---@param print_no_fp function
function backplane.detach(iface, type, device, print_no_fp)
    if type == "modem" then
        ---@cast device Modem

        log.info(util.c("BKPLN: PHY_DETACH ", iface))

        _bp.nic_map[iface] = nil

        if _bp.wd_nic and _bp.wd_nic.is_modem(device) then
            _bp.wd_nic.disconnect()
            log.info("BKPLN: WIRED PHY_DOWN " .. iface)

            print_no_fp("wired modem disconnected")
            log.warning("BKPLN: wired comms modem disconnected")

            databus.tx_hw_wd_modem(false)
        elseif _bp.wl_nic and _bp.wl_nic.is_modem(device) then
            _bp.wl_nic.disconnect()
            log.info("BKPLN: WIRELESS PHY_DOWN " .. iface)

            print_no_fp("wireless comms modem disconnected")
            log.warning("BKPLN: wireless comms modem disconnected")

            local modem, m_iface = ppm.get_wireless_modem()
            if modem then
                log.info("BKPLN: found another wireless modem, using it for comms")

                _bp.wl_nic.connect(modem)
                log.info("BKPLN: WIRELESS PHY_UP " .. m_iface)
            else
                databus.tx_hw_wl_modem(false)
            end
        else
            print_no_fp("unassigned modem disconnected")
            log.warning("BKPLN: unassigned modem disconnected")
        end
    end
end

return backplane
