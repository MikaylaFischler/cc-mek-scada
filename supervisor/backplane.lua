--
-- Supervisor System Core Peripheral Backplane
--

local log     = require("scada-common.log")
local network = require("scada-common.network")
local ppm     = require("scada-common.ppm")
local types   = require("scada-common.types")
local util    = require("scada-common.util")

local databus = require("supervisor.databus")

local LISTEN_MODE = types.LISTEN_MODE

---@class supervisor_backplane
local backplane = {}

local _bp = {
    config = nil,       ---@type svr_config
    lan_iface = false,  ---@type string|false wired comms modem name

    wd_nic = nil,       ---@type nic|nil wired nic
    wl_nic = nil,       ---@type nic|nil wireless nic
    nic_map = {}        ---@type nic[] connected nics
}

backplane.nics = _bp.nic_map

-- initialize the system peripheral backplane
---@param config svr_config
---@param println function
---@return boolean success
function backplane.init(config, println)
    -- setup the wired modem, if configured
    if type(config.WiredModem) == "string" then
        _bp.lan_iface = config.WiredModem

        local modem = ppm.get_modem(_bp.lan_iface)
        if not (modem and _bp.lan_iface) then
            println("startup> wired comms modem not found")
            log.fatal("no wired comms modem on startup")
            return false
        end

        local nic = network.nic(modem)
        _bp.wd_nic = nic
        _bp.nic_map[_bp.lan_iface] = nic

        nic.closeAll()

        if config.PLC_Listen ~= LISTEN_MODE.WIRELESS then nic.open(config.PLC_Channel) end
        if config.RTU_Listen ~= LISTEN_MODE.WIRELESS then nic.open(config.RTU_Channel) end
        if config.CRD_Listen ~= LISTEN_MODE.WIRELESS then nic.open(config.CRD_Channel) end

        databus.tx_hw_wd_modem(true)
    end

    -- setup the wireless modem, if configured
    if config.WirelessModem then
        local modem, iface = ppm.get_wireless_modem()
        if not (modem and iface) then
            println("startup> wireless comms modem not found")
            log.fatal("no wireless comms modem on startup")
            return false
        end

        local nic = network.nic(modem)
        _bp.wl_nic = nic
        _bp.nic_map[iface] = nic

        nic.closeAll()

        if config.PLC_Listen ~= LISTEN_MODE.WIRED then nic.open(config.PLC_Channel) end
        if config.RTU_Listen ~= LISTEN_MODE.WIRED then nic.open(config.RTU_Channel) end
        if config.CRD_Listen ~= LISTEN_MODE.WIRED then nic.open(config.CRD_Channel) end
        if config.PocketEnabled then nic.open(config.PKT_Channel) end

        databus.tx_hw_wl_modem(true)
    end

    if not ((type(config.WiredModem) == "string" or config.WirelessModem)) then
        println("startup> no modems configured")
        log.fatal("no modems configured")
        return false
    end

    return true
end

-- handle a backplane peripheral attach
---@param iface string
---@param type string
---@param device table
---@param println function
function backplane.attach(iface, type, device, println)
    if type == "modem" then
        ---@cast device Modem

        local m_is_wl = device.isWireless()

        log.info(util.c("BKPLN: ", util.trinary(m_is_wl, "WIRELESS", "WIRED"), " PHY_ATTACH ", iface))

        local is_wd = _bp.wd_nic and (_bp.lan_iface == iface)
        local is_wl = _bp.wl_nic and (not _bp.wl_nic.is_connected()) and m_is_wl

        if is_wd then
            -- connect this as the wired NIC
            _bp.wd_nic.connect(device)

            log.info("BKPLN: WIRED PHY_UP " .. iface)
            println("wired comms modem reconnected")

            databus.tx_hw_wd_modem(true)
        elseif is_wl then
            -- connect this as the wireless NIC
            _bp.wl_nic.connect(device)
            _bp.nic_map[iface] = _bp.wl_nic

            log.info("BKPLN: WIRELESS PHY_UP " .. iface)
            println("wireless comms modem reconnected")

            databus.tx_hw_wl_modem(true)
        elseif _bp.wl_nic and m_is_wl then
            -- the wireless NIC already has a modem
            println("standby wireless modem connected")
            log.info("BKPLN: standby wireless modem connected")
        else
            println("unassigned modem connected")
            log.warning("BKPLN: unassigned modem connected")
        end
    end
end

-- handle a backplane peripheral detach
---@param iface string
---@param type string
---@param device table
---@param println function
function backplane.detach(iface, type, device, println)
    if type == "modem" then
        ---@cast device Modem

        local m_is_wl = device.isWireless()
        local was_wd  = _bp.wd_nic and _bp.wd_nic.is_modem(device)
        local was_wl  = _bp.wl_nic and _bp.wl_nic.is_modem(device)

        log.info(util.c("BKPLN: ", util.trinary(m_is_wl, "WIRELESS", "WIRED"), " PHY_DETACH ", iface))

        _bp.nic_map[iface] = nil

        if _bp.wd_nic and was_wd then
            _bp.wd_nic.disconnect()
            log.info("BKPLN: WIRED PHY_DOWN " .. iface)

            println("wired modem disconnected")
            log.warning("BKPLN: wired comms modem disconnected")

            databus.tx_hw_wd_modem(false)
        elseif _bp.wl_nic and was_wl then
            _bp.wl_nic.disconnect()
            log.info("BKPLN: WIRELESS PHY_DOWN " .. iface)

            println("wireless comms modem disconnected")
            log.warning("BKPLN: wireless comms modem disconnected")

            local modem, m_iface = ppm.get_wireless_modem()
            if modem then
                log.info("BKPLN: found another wireless modem, using it for comms")

                _bp.wl_nic.connect(modem)
                log.info("BKPLN: WIRELESS PHY_UP " .. m_iface)
            else
                databus.tx_hw_wl_modem(false)
            end
        elseif _bp.wl_nic and m_is_wl then
            -- wireless, but not active
            println("standby wireless modem disconnected")
            log.info("BKPLN: standby wireless modem disconnected")
        else
            println("unassigned modem disconnected")
            log.warning("BKPLN: unassigned modem disconnected")
        end
    end
end

return backplane
