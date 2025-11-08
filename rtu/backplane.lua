--
-- RTU Gateway System Core Peripheral Backplane
--

local log     = require("scada-common.log")
local network = require("scada-common.network")
local ppm     = require("scada-common.ppm")
local util    = require("scada-common.util")

local databus = require("rtu.databus")
local rtu     = require("rtu.rtu")

local println = util.println

---@class rtu_backplane
local backplane = {}

local _bp = {
    smem = nil,     ---@type rtu_shared_memory

    wlan_pref = true,
    lan_iface = "",

    act_nic = nil,  ---@type nic
    wd_nic = nil,   ---@type nic|nil
    wl_nic = nil,   ---@type nic|nil

    sounders = {}   ---@type rtu_speaker_sounder[]
}

-- initialize the system peripheral backplane
---@param config rtu_config
---@param __shared_memory rtu_shared_memory
---@return boolean success
function backplane.init(config, __shared_memory)
    _bp.smem      = __shared_memory
    _bp.wlan_pref = config.PreferWireless
    _bp.lan_iface = config.WiredModem

    -- Modem Init

    -- init wired NIC
    if type(_bp.lan_iface) == "string" then
        local modem  = ppm.get_modem(_bp.lan_iface)
        local wd_nic = network.nic(modem)

        log.info("BKPLN: WIRED PHY_" .. util.trinary(modem, "UP ", "DOWN ") .. _bp.lan_iface)

        _bp.wd_nic  = wd_nic
        _bp.act_nic = wd_nic -- set this as active for now

        wd_nic.closeAll()
        wd_nic.open(config.RTU_Channel)

        databus.tx_hw_wd_modem(modem ~= nil)
    end

    -- init wireless NIC(s)
    if config.WirelessModem then
        local modem, iface = ppm.get_wireless_modem()
        local wl_nic       = network.nic(modem)

        log.info("BKPLN: WIRELESS PHY_" .. util.trinary(modem, "UP ", "DOWN") .. (iface or ""))

        -- set this as active if connected or if both modems are disconnected and this is preferred
        if (modem and _bp.wlan_pref) or not (_bp.act_nic and _bp.act_nic.is_connected()) then
            _bp.act_nic = wl_nic
        end

        _bp.wl_nic = wl_nic

        wl_nic.closeAll()
        wl_nic.open(config.RTU_Channel)

        databus.tx_hw_wl_modem(modem ~= nil)
    end

    -- at least one comms modem is required
    if not ((_bp.wd_nic and _bp.wd_nic.is_connected()) or (_bp.wl_nic and _bp.wl_nic.is_connected())) then
        println("startup> no comms modem found")
        log.warning("BKPLN: no comms modem on startup")
        return false
    end

    -- Speaker Init

    -- find and setup all speakers
    local speakers = ppm.get_all_devices("speaker")
    for _, s in pairs(speakers) do
        log.info("BKPLN: SPEAKER LINK_UP " .. ppm.get_iface(s))

        local sounder = rtu.init_sounder(s)
        table.insert(_bp.sounders, sounder)

        log.debug(util.c("BKPLN: added speaker sounder, attached as ", sounder.name))
    end

    databus.tx_hw_spkr_count(#_bp.sounders)

    return true
end

-- get the active NIC
function backplane.active_nic() return _bp.act_nic end

-- get the sounder interfaces
function backplane.sounders() return _bp.sounders end

-- handle a backplane peripheral attach
---@param type string
---@param device table
---@param iface string
---@param print_no_fp function
function backplane.attach(type, device, iface, print_no_fp)
    local wl_nic, wd_nic = _bp.wl_nic, _bp.wd_nic

    local comms = _bp.smem.rtu_sys.rtu_comms

    if type == "modem" then
        ---@cast device Modem

        local m_is_wl = device.isWireless()

        log.info(util.c("BKPLN: ", util.trinary(m_is_wl, "WIRELESS", "WIRED"), " PHY_ATTACH ", iface))

        if wd_nic and (_bp.lan_iface == iface) then
            -- connect this as the wired NIC
            wd_nic.connect(device)

            log.info("BKPLN: WIRED PHY_UP " .. iface)
            print_no_fp("wired comms modem reconnected")

            databus.tx_hw_wd_modem(true)

            if (_bp.act_nic ~= wd_nic) and not _bp.wlan_pref then
                -- switch back to preferred wired
                _bp.act_nic = wd_nic

                comms.switch_nic(_bp.act_nic)
                log.info("BKPLN: switched comms to wired modem (preferred)")
            end
        elseif wl_nic and (not wl_nic.is_connected()) and m_is_wl then
            -- connect this as the wireless NIC
            wl_nic.connect(device)

            log.info("BKPLN: WIRELESS PHY_UP " .. iface)
            print_no_fp("wireless comms modem reconnected")

            databus.tx_hw_wl_modem(true)

            if (_bp.act_nic ~= wl_nic) and _bp.wlan_pref then
                -- switch back to preferred wireless
                _bp.act_nic = wl_nic

                comms.switch_nic(_bp.act_nic)
                log.info("BKPLN: switched comms to wireless modem (preferred)")
            end
        elseif wl_nic and m_is_wl then
            -- the wireless NIC already has a modem
            print_no_fp("standby wireless modem connected")
            log.info("BKPLN: standby wireless modem connected")
        else
            print_no_fp("unassigned modem connected")
            log.warning("BKPLN: unassigned modem connected")
        end
    elseif type == "speaker" then
        ---@cast device Speaker

        log.info("BKPLN: SPEAKER LINK_UP " .. iface)

        table.insert(_bp.sounders, rtu.init_sounder(device))

        print_no_fp("a speaker was connected")
        log.info("BKPLN: setup speaker sounder for speaker " .. iface)

        databus.tx_hw_spkr_count(#_bp.sounders)
    end
end

-- handle a backplane peripheral detach
---@param type string
---@param device table
---@param iface string
---@param print_no_fp function
function backplane.detach(type, device, iface, print_no_fp)
    local wl_nic, wd_nic = _bp.wl_nic, _bp.wd_nic

    local comms = _bp.smem.rtu_sys.rtu_comms

    if type == "modem" then
        ---@cast device Modem

        local m_is_wl = device.isWireless()

        log.info(util.c("BKPLN: ", util.trinary(m_is_wl, "WIRELESS", "WIRED"), " PHY_DETACH ", iface))

        if wd_nic and wd_nic.is_modem(device) then
            wd_nic.disconnect()
            log.info("BKPLN: WIRED PHY_DOWN " .. iface)

            databus.tx_hw_wd_modem(false)
        elseif wl_nic and wl_nic.is_modem(device) then
            wl_nic.disconnect()
            log.info("BKPLN: WIRELESS PHY_DOWN " .. iface)

            databus.tx_hw_wl_modem(false)
        end

        -- we only care if this is our active comms modem
        if _bp.act_nic.is_modem(device) then
            print_no_fp("active comms modem disconnected")
            log.warning("BKPLN: active comms modem disconnected")

            -- failover and try to find a new comms modem
            if _bp.act_nic == wl_nic then
                -- wireless active disconnected
                -- try to find another wireless modem, otherwise switch to wired
                local modem, m_iface = ppm.get_wireless_modem()
                if wl_nic and modem then
                    log.info("BKPLN: found another wireless modem, using it for comms")

                    wl_nic.connect(modem)

                    log.info("BKPLN: WIRELESS PHY_UP " .. m_iface)

                    databus.tx_hw_wl_modem(true)
                elseif wd_nic and wd_nic.is_connected() then
                    _bp.act_nic = wd_nic

                    comms.switch_nic(_bp.act_nic)
                    log.info("BKPLN: switched comms to wired modem")
                end
            elseif wl_nic and wl_nic.is_connected() then
                -- wired active disconnected, wireless available
                _bp.act_nic = wl_nic

                comms.switch_nic(_bp.act_nic)
                log.info("BKPLN: switched comms to wireless modem")
            else
                -- wired active disconnected, wireless unavailable
            end
        elseif _bp.wl_nic and m_is_wl then
            -- wireless, but not active
            print_no_fp("standby wireless modem disconnected")
            log.info("BKPLN: standby wireless modem disconnected")
        else
            print_no_fp("unassigned modem disconnected")
            log.warning("BKPLN: unassigned modem disconnected")
        end
    elseif type == "speaker" then
        ---@cast device Speaker

        log.info("BKPLN: SPEAKER LINK_DOWN " .. iface)

        for i = 1, #_bp.sounders do
            if _bp.sounders[i].speaker == device then
                table.remove(_bp.sounders, i)

                print_no_fp("a speaker was disconnected")
                log.warning("BKPLN: speaker sounder " .. iface .. " disconnected")

                databus.tx_hw_spkr_count(#_bp.sounders)
                break
            end
        end
    end
end

return backplane
