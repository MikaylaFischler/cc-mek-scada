--
-- RTU Gateway System Core Peripheral Backplane
--

local log     = require("scada-common.log")
local network = require("scada-common.network")
local ppm     = require("scada-common.ppm")
local util    = require("scada-common.util")

local databus = require("rtu.databus")
local rtu     = require("rtu.rtu")

---@class rtu_backplane
local backplane = {}

local _bp = {
    smem = nil,     ---@type rtu_shared_memory

    wlan_en = true,
    wlan_pref = true,
    lan_en = false,
    lan_iface = "",

    act_nic = nil,  ---@type nic|nil
    wl_act = true,
    wd_nic = nil,   ---@type nic|nil
    wl_nic = nil,   ---@type nic|nil

    sounders = {}   ---@type rtu_speaker_sounder[]
}

-- initialize the system peripheral backplane
---@param config rtu_config
---@param __shared_memory rtu_shared_memory
function backplane.init(config, __shared_memory)
    _bp.smem      = __shared_memory
    _bp.wlan_en   = config.WirelessModem
    _bp.wlan_pref = config.PreferWireless
    _bp.lan_en    = type(config.WiredModem) == "string"
    _bp.lan_iface = config.WiredModem

    -- init wired NIC
    if _bp.lan_en then
        local modem = ppm.get_wired_modem(_bp.lan_iface)

        if modem then
            _bp.wd_nic = network.nic(modem)
            log.info("BKPLN: WIRED PHY_UP " .. _bp.lan_iface)
        end
    end

    -- init wireless NIC(s)
    if _bp.wlan_en then
        local modem, iface = ppm.get_wireless_modem()

        if modem then
            _bp.wl_nic = network.nic(modem)
            log.info("BKPLN: WIRELESS PHY_UP " .. iface)
        end
    end

    -- grab the preferred active NIC
    if _bp.wlan_pref then
        _bp.wl_act = true
        _bp.act_nic = _bp.wl_nics[1]
    else
        _bp.wl_act = false
        _bp.act_nic = _bp.wd_nic
    end

    databus.tx_hw_modem(_bp.act_nic ~= nil)

    -- find and setup all speakers
    local speakers = ppm.get_all_devices("speaker")
    for _, s in pairs(speakers) do
        local sounder = rtu.init_sounder(s)

        table.insert(_bp.sounders, sounder)

        log.debug(util.c("BKPLN: added speaker, attached as ", sounder.name))
    end

    databus.tx_hw_spkr_count(#_bp.sounders)
end

-- get the active NIC
---@return nic|nil
function backplane.active_nic() return _bp.act_nic end

-- get the sounder interfaces
---@return rtu_speaker_sounder[]
function backplane.sounders() return _bp.sounders end

-- handle a backplane peripheral detach
---@param type string
---@param device table
---@param iface string
function backplane.detach(type, device, iface)
    local function println_ts(message) if not _bp.smem.rtu_state.fp_ok then util.println_ts(message) end end

    local wl_nic, wd_nic = _bp.wl_nic, _bp.wd_nic

    local comms = _bp.smem.rtu_sys.rtu_comms

    if type == "modem" then
        ---@cast device Modem

        local was_active = _bp.act_nic and _bp.act_nic.is_modem(device)
        local was_wd     = wd_nic and wd_nic.is_modem(device)
        local was_wl     = wl_nic and wl_nic.is_modem(device)

        if wd_nic and was_wd then
            log.info("BKPLN: WIRED PHY_DOWN " .. iface)
            wd_nic.disconnect()
        elseif wl_nic and was_wl then
            log.info("BKPLN: WIRELESS PHY_DOWN " .. iface)
            wl_nic.disconnect()
        end

        -- we only care if this is our active comms modem
        if was_active then
            println_ts("active comms modem disconnected!")
            log.warning("active comms modem disconnected")

            -- failover and try to find a new comms modem
            if _bp.wl_act then
                -- try to find another wireless modem, otherwise switch to wired
                local other_modem = ppm.get_wireless_modem()
                if other_modem then
                    log.info("found another wireless modem, using it for comms")

                    -- note: must assign to self.wl_nic if creating a nic, otherwise it only changes locally
                    if wl_nic then
                        wl_nic.connect(other_modem)
                    else _bp.wl_nic = network.nic(other_modem) end

                    log.info("BKPLN: WIRELESS PHY_UP " .. iface)

                    _bp.act_nic = wl_nic
                    comms.assign_nic(_bp.act_nic)
                    log.info("BKPLN: switched comms to new wireless modem")
                elseif wd_nic and wd_nic.is_connected() then
                    _bp.wl_act  = false
                    _bp.act_nic = _bp.wd_nic

                    comms.assign_nic(_bp.act_nic)
                    log.info("BKPLN: switched comms to wired modem")
                else
                    _bp.act_nic = nil
                    databus.tx_hw_modem(false)
                    comms.unassign_nic()
                end
            else
                -- switch to wireless if able
                if wl_nic then
                    _bp.wl_act  = true
                    _bp.act_nic = wl_nic

                    comms.assign_nic(_bp.act_nic)
                    log.info("BKPLN: switched comms to wireless modem")
                else
                    _bp.act_nic = nil
                    databus.tx_hw_modem(false)
                    comms.unassign_nic()
                end
            end
        else
            log.warning("modem disconnected")
        end
    elseif type == "speaker" then
        ---@cast device Speaker
        for i = 1, #_bp.sounders do
            if _bp.sounders[i].speaker == device then
                table.remove(_bp.sounders, i)

                log.warning(util.c("speaker ", iface, " disconnected"))
                println_ts("speaker disconnected")

                databus.tx_hw_spkr_count(#_bp.sounders)
                break
            end
        end
    end
end

-- handle a backplane peripheral attach
---@param type string
---@param device table
---@param iface string
function backplane.attach(type, device, iface)
    local function println_ts(message) if not _bp.smem.rtu_state.fp_ok then util.println_ts(message) end end

    local comms = _bp.smem.rtu_sys.rtu_comms

    if type == "modem" then
        ---@cast device Modem

        local is_wd = _bp.lan_iface == iface
        local is_wl = ((not _bp.wl_nic) or (not _bp.wl_nic.is_connected())) and device.isWireless()

        if is_wd then
            -- connect this as the wired NIC
            if _bp.wd_nic then
                _bp.wd_nic.connect(device)
            else _bp.wd_nic = network.nic(device) end

            log.info("BKPLN: WIRED PHY_UP " .. iface)

            if _bp.act_nic == nil then
                -- set as active
                _bp.wl_act  = false
                _bp.act_nic = _bp.wd_nic

                comms.assign_nic(_bp.act_nic)
                databus.tx_hw_modem(true)
                println_ts("comms modem reconnected.")
                log.info("BKPLN: switched comms to wired modem")
            elseif _bp.wl_act and not _bp.wlan_pref then
                -- switch back to preferred wired
                _bp.wl_act  = false
                _bp.act_nic = _bp.wd_nic

                comms.assign_nic(_bp.act_nic)
                log.info("BKPLN: switched comms to wired modem (preferred)")
            end
        elseif is_wl then
            -- connect this as the wireless NIC
            if _bp.wl_nic then
                _bp.wl_nic.connect(device)
            else _bp.wl_nic = network.nic(device) end

            log.info("BKPLN: WIRELESS PHY_UP " .. iface)

            if _bp.act_nic == nil then
                -- set as active
                _bp.wl_act  = true
                _bp.act_nic = _bp.wl_nic

                comms.assign_nic(_bp.act_nic)
                databus.tx_hw_modem(true)
                println_ts("comms modem reconnected.")
                log.info("BKPLN: switched comms to wireless modem")
            elseif (not _bp.wl_act) and _bp.wlan_pref then
                -- switch back to preferred wireless
                _bp.wl_act  = true
                _bp.act_nic = _bp.wl_nic

                comms.assign_nic(_bp.act_nic)
                log.info("BKPLN: switched comms to wireless modem (preferred)")
            end
        elseif device.isWireless() then
            -- the wireless NIC already has a modem
            log.info("standby wireless modem connected")
        else
            log.info("wired modem connected")
        end
    elseif type == "speaker" then
        ---@cast device Speaker
        table.insert(_bp.sounders, rtu.init_sounder(device))

        println_ts("speaker connected")
        log.info(util.c("connected speaker ", iface))

        databus.tx_hw_spkr_count(#_bp.sounders)
    end
end

return backplane
