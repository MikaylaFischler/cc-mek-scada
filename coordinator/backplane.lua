--
-- Coordinator System Core Peripheral Backplane
--

local log     = require("scada-common.log")
local network = require("scada-common.network")
local ppm     = require("scada-common.ppm")
local util    = require("scada-common.util")

local coordinator = require("coordinator.coordinator")
local iocontrol   = require("coordinator.iocontrol")
local sounder     = require("coordinator.sounder")

local println = util.println

local log_sys    = coordinator.log_sys
local log_boot   = coordinator.log_boot
local log_comms  = coordinator.log_comms

---@class crd_backplane
local backplane = {}

local _bp = {
    smem = nil,     ---@type crd_shared_memory

    wlan_pref = true,
    lan_iface = "",

    act_nic = nil,  ---@type nic
    wd_nic = nil,   ---@type nic|nil
    wl_nic = nil,   ---@type nic|nil

    speaker = nil, ---@type Speaker|nil

    ---@class crd_displays
    displays = {
        main = nil,         ---@type Monitor|nil
        main_iface = "",
        flow = nil,         ---@type Monitor|nil
        flow_iface = "",
        unit_displays = {}, ---@type Monitor[]
        unit_ifaces = {}    ---@type string[]
    }
}

-- initialize the display peripheral backplane
---@param config crd_config
---@return boolean success, string error_msg
function backplane.init_displays(config)
    local displays = _bp.displays

    local w, h, _

    log.info("BKPLN: DISPLAY INIT")

    -- monitor configuration verification

    local mon_cfv = util.new_validator()

    mon_cfv.assert_type_str(config.MainDisplay)
    if not config.DisableFlowView then mon_cfv.assert_type_str(config.FlowDisplay) end

    mon_cfv.assert_eq(#config.UnitDisplays, config.UnitCount)
    for i = 1, #config.UnitDisplays do
        mon_cfv.assert_type_str(config.UnitDisplays[i])
    end

    if not mon_cfv.valid() then
        return false, "Monitor configuration invalid."
    end

    -- setup and check display peripherals

    -- main display

    local disp, iface = ppm.get_periph(config.MainDisplay), config.MainDisplay

    displays.main = disp
    displays.main_iface = iface

    log.info("BKPLN: DISPLAY LINK_" .. util.trinary(disp, "UP", "DOWN") .. " MAIN/" .. iface)

    if not disp then
        return false, "Main monitor is not connected."
    end

    disp.setTextScale(0.5)
    w, _ = ppm.monitor_block_size(disp.getSize())
    if w ~= 8 then
        log.info("BKPLN: DISPLAY MAIN/" .. iface .. " BAD RESOLUTION")
        return false, util.c("Main monitor width is incorrect (was ", w, ", must be 8).")
    end

    -- flow display

    if not config.DisableFlowView then
        disp, iface = ppm.get_periph(config.FlowDisplay), config.FlowDisplay

        displays.flow = disp
        displays.flow_iface = iface

        log.info("BKPLN: DISPLAY LINK_" .. util.trinary(disp, "UP", "DOWN") .. " FLOW/" .. iface)

        if not disp then
            return false, "Flow monitor is not connected."
        end

        disp.setTextScale(0.5)
        w, _ = ppm.monitor_block_size(disp.getSize())
        if w ~= 8 then
            log.info("BKPLN: DISPLAY FLOW/" .. iface .. " BAD RESOLUTION")
            return false, util.c("Flow monitor width is incorrect (was ", w, ", must be 8).")
        end
    end

    -- unit display(s)

    for i = 1, config.UnitCount do
        disp, iface = ppm.get_periph(config.UnitDisplays[i]), config.UnitDisplays[i]

        displays.unit_displays[i] = disp
        displays.unit_ifaces[i] = iface

        log.info("BKPLN: DISPLAY LINK_" .. util.trinary(disp, "UP", "DOWN") .. " UNIT_" .. i .. "/" .. iface)

        if not disp then
            return false, "Unit " .. i .. " monitor is not connected."
        end

        disp.setTextScale(0.5)
        w, h = ppm.monitor_block_size(disp.getSize())
        if w ~= 4 or h ~= 4 then
            log.info("BKPLN: DISPLAY UNIT_" .. i .. "/" .. iface .. " BAD RESOLUTION")
            return false, util.c("Unit ", i, " monitor size is incorrect (was ", w, " by ", h,", must be 4 by 4).")
        end
    end

    log.info("BKPLN: DISPLAY INIT OK")

    return true, ""
end

-- initialize the system peripheral backplane
---@param config crd_config
---@param __shared_memory crd_shared_memory
---@return boolean success
function backplane.init(config, __shared_memory)
    _bp.smem      = __shared_memory
    _bp.wlan_pref = config.PreferWireless
    _bp.lan_iface = config.WiredModem

    -- Modem Init

    -- init wired NIC
    if type(config.WiredModem) == "string" then
        local modem  = ppm.get_modem(_bp.lan_iface)
        local wd_nic = network.nic(modem)

        log.info("BKPLN: WIRED PHY_" .. util.trinary(modem, "UP ", "DOWN ") .. _bp.lan_iface)
        log_comms("wired comms modem " .. util.trinary(modem, "connected", "not found"))

        -- set this as active for now
        _bp.act_nic = wd_nic
        _bp.wd_nic  = wd_nic

        iocontrol.fp_has_wd_modem(modem ~= nil)
    end

    -- init wireless NIC(s)
    if config.WirelessModem then
        local modem, iface = ppm.get_wireless_modem()
        local wl_nic       = network.nic(modem)

        log.info("BKPLN: WIRELESS PHY_" .. util.trinary(modem, "UP ", "DOWN ") .. iface)
        log_comms("wireless comms modem " .. util.trinary(modem, "connected", "not found"))

        -- set this as active if connected or if both modems are disconnected and this is preferred
        if (modem and _bp.wlan_pref) or not (_bp.act_nic and _bp.act_nic.is_connected()) then
            _bp.act_nic = wl_nic
        end

        _bp.wl_nic = wl_nic

        iocontrol.fp_has_wl_modem(modem ~= nil)
    end

    -- at least one comms modem is required
    if not ((_bp.wd_nic and _bp.wd_nic.is_connected()) or (_bp.wl_nic and _bp.wl_nic.is_connected())) then
        log_comms("no comms modem found")
        println("startup> no comms modem found")
        log.warning("BKPLN: no comms modem on startup")
        return false
    end

    -- Speaker Init

    _bp.speaker = ppm.get_device("speaker")

    if not _bp.speaker then
        log_boot("annunciator alarm speaker not found")

        println("startup> speaker not found")
        log.fatal("BKPLN: no annunciator alarm speaker found")

        return false
    else
        log.info("BKPLN: SPEAKER LINK_UP " .. ppm.get_iface(_bp.speaker))
        log_boot("annunciator alarm speaker connected")

        local sounder_start = util.time_ms()
        sounder.init(_bp.speaker, config.SpeakerVolume)

        log_boot("tone generation took " .. (util.time_ms() - sounder_start) .. "ms")
        log_sys("annunciator alarm configured")

        iocontrol.fp_has_speaker(true)
    end

    return true
end

-- get the active NIC
---@return nic
function backplane.active_nic() return _bp.act_nic end

function backplane.displays() return _bp.displays end

return backplane
