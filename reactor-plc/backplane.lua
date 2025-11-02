--
-- Reactor PLC System Core Peripheral Backplane
--

local log     = require("scada-common.log")
local network = require("scada-common.network")
local ppm     = require("scada-common.ppm")
local util    = require("scada-common.util")

local println = util.println

---@class plc_backplane
local backplane = {}

local _bp = {
    smem = nil,     ---@type plc_shared_memory

    wlan_pref = true,
    lan_iface = "",

    act_nic = nil,  ---@type nic
    wd_nic = nil,   ---@type nic|nil
    wl_nic = nil    ---@type nic|nil
}

-- initialize the system peripheral backplane<br>
---@param config plc_config
---@param __shared_memory plc_shared_memory
--- EVENT_CONSUMER: this function consumes events
function backplane.init(config, __shared_memory)
    _bp.smem      = __shared_memory
    _bp.wlan_pref = config.PreferWireless
    _bp.lan_iface = config.WiredModem

    local plc_dev   = __shared_memory.plc_dev
    local plc_state = __shared_memory.plc_state

    -- Modem Init

    if _bp.smem.networked then
        -- init wired NIC
        if type(config.WiredModem) == "string" then
            local modem  = ppm.get_modem(_bp.lan_iface)
            local wd_nic = network.nic(modem)

            log.info("BKPLN: WIRED PHY_" .. util.trinary(modem, "UP ", "DOWN ") .. _bp.lan_iface)

            plc_state.wd_modem = wd_nic.is_connected()

            -- set this as active for now
            _bp.act_nic = wd_nic
            _bp.wd_nic  = wd_nic
        end

        -- init wireless NIC(s)
        if config.WirelessModem then
            local modem, iface = ppm.get_wireless_modem()
            local wl_nic       = network.nic(modem)

            log.info("BKPLN: WIRELESS PHY_" .. util.trinary(modem, "UP ", "DOWN ") .. iface)

            plc_state.wl_modem = wl_nic.is_connected()

            -- set this as active if connected or if both modems are disconnected and this is preferred
            if (modem and _bp.wlan_pref) or not (_bp.act_nic and _bp.act_nic.is_connected()) then
                _bp.act_nic = wl_nic
            end

            _bp.wl_nic = wl_nic
        end

        -- comms modem is required if networked
        if not (plc_state.wd_modem or plc_state.wl_modem) then
            println("startup> comms modem not found")
            log.warning("BKPLN: no comms modem on startup")

            plc_state.degraded = true
        end
    end

    -- Reactor Init

---@diagnostic disable-next-line: assign-type-mismatch
    plc_dev.reactor      = ppm.get_fission_reactor()
    plc_state.no_reactor = plc_dev.reactor == nil

    -- we need a reactor, can at least do some things even if it isn't formed though
    if plc_state.no_reactor then
        println("startup> fission reactor not found")
        log.warning("BKPLN: no reactor on startup")

        plc_state.degraded = true
        plc_state.reactor_formed = false

        -- mount a virtual peripheral to init the RPS with
        local _, dev = ppm.mount_virtual()
        plc_dev.reactor = dev

        log.info("BKPLN: mounted virtual device as reactor")
    elseif not plc_dev.reactor.isFormed() then
        println("startup> fission reactor is not formed")
        log.warning("BKPLN: reactor logic adapter present, but reactor is not formed")

        plc_state.degraded = true
        plc_state.reactor_formed = false
    else
        log.info("BKPLN: reactor detected")
    end
end

-- get the active NIC
---@return nic
function backplane.active_nic() return _bp.act_nic end

-- handle a backplane peripheral attach
---@param iface string
---@param type string
---@param device table
---@param print_no_fp function
function backplane.attach(iface, type, device, print_no_fp)
    local MQ__RPS_CMD = _bp.smem.q_cmds.MQ__RPS_CMD

    local wl_nic, wd_nic = _bp.wl_nic, _bp.wd_nic

    local networked = _bp.smem.networked
    local state     = _bp.smem.plc_state
    local dev       = _bp.smem.plc_dev
    local sys       = _bp.smem.plc_sys

    if type ~= nil and device ~= nil then
        if state.no_reactor and (type == "fissionReactorLogicAdapter") then
            -- reconnected reactor
            dev.reactor = device
            state.no_reactor = false

            print_no_fp("reactor reconnected")
            log.info("BKPLN: reactor reconnected")

            -- we need to assume formed here as we cannot check in this main loop
            -- RPS will identify if it isn't and this will get set false later
            state.reactor_formed = true

            -- determine if we are still in a degraded state
            if ((not networked) or (state.wd_modem or state.wl_modem)) and state.reactor_formed then
                state.degraded = false
            end

            _bp.smem.q.mq_rps.push_command(MQ__RPS_CMD.SCRAM)

            sys.rps.reconnect_reactor(dev.reactor)
            if networked then
                sys.plc_comms.reconnect_reactor(dev.reactor)
            end

            -- partial reset of RPS, specific to becoming formed/reconnected
            -- without this, auto control can't resume on chunk load
            sys.rps.reset_reattach()
        elseif networked and type == "modem" then
            ---@cast device Modem

            local m_is_wl = device.isWireless()

            log.info(util.c("BKPLN: ", util.trinary(m_is_wl, "WIRELESS", "WIRED"), " PHY_ATTACH ", iface))

            if wd_nic and (_bp.lan_iface == iface) then
                -- connect this as the wired NIC
                wd_nic.connect(device)

                log.info("BKPLN: WIRED PHY_UP " .. iface)
                print_no_fp("wired comms modem reconnected")

                state.wd_modem = true

                if (_bp.act_nic ~= wd_nic) and not _bp.wlan_pref then
                    -- switch back to preferred wired
                    _bp.act_nic = wd_nic

                    sys.plc_comms.switch_nic(_bp.act_nic)
                    log.info("BKPLN: switched comms to wired modem (preferred)")
                end
            elseif wl_nic and (not wl_nic.is_connected()) and m_is_wl then
                -- connect this as the wireless NIC
                wl_nic.connect(device)

                log.info("BKPLN: WIRELESS PHY_UP " .. iface)
                print_no_fp("wireless comms modem reconnected")

                state.wl_modem = true

                if (_bp.act_nic ~= wl_nic) and _bp.wlan_pref then
                    -- switch back to preferred wireless
                    _bp.act_nic = wl_nic

                    sys.plc_comms.switch_nic(_bp.act_nic)
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

            -- determine if we are still in a degraded state
            if (state.wd_modem or state.wl_modem) and state.reactor_formed and not state.no_reactor then
                state.degraded = false
            end
        end
    end
end

-- handle a backplane peripheral detach
---@param iface string
---@param type string
---@param device table
---@param print_no_fp function
function backplane.detach(iface, type, device, print_no_fp)
    local MQ__RPS_CMD = _bp.smem.q_cmds.MQ__RPS_CMD

    local wl_nic, wd_nic = _bp.wl_nic, _bp.wd_nic

    local state = _bp.smem.plc_state
    local dev   = _bp.smem.plc_dev
    local sys   = _bp.smem.plc_sys

    if device == dev.reactor then
        print_no_fp("reactor disconnected")
        log.warning("BKPLN: reactor disconnected")

        state.no_reactor = true
        state.degraded = true
    elseif _bp.smem.networked and type == "modem" then
        ---@cast device Modem

        local m_is_wl = device.isWireless()

        log.info(util.c("BKPLN: ", util.trinary(m_is_wl, "WIRELESS", "WIRED"), " PHY_DETACH ", iface))

        if wd_nic and wd_nic.is_modem(device) then
            wd_nic.disconnect()
            log.info("BKPLN: WIRED PHY_DOWN " .. iface)

            state.wd_modem = false
        elseif wl_nic and wl_nic.is_modem(device) then
            wl_nic.disconnect()
            log.info("BKPLN: WIRELESS PHY_DOWN " .. iface)

            state.wl_modem = false
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
                elseif wd_nic and wd_nic.is_connected() then
                    _bp.act_nic = wd_nic

                    sys.plc_comms.switch_nic(_bp.act_nic)
                    log.info("BKPLN: switched comms to wired modem")
                else
                    -- no other wireless modems, wired unavailable
                    state.degraded = true
                    _bp.smem.q.mq_rps.push_command(MQ__RPS_CMD.DEGRADED_SCRAM)
                end
            elseif wl_nic and wl_nic.is_connected() then
                -- wired active disconnected, wireless available
                _bp.act_nic = wl_nic

                sys.plc_comms.switch_nic(_bp.act_nic)
                log.info("BKPLN: switched comms to wireless modem")
            else
                -- wired active disconnected, wireless unavailable
                state.degraded = true
                _bp.smem.q.mq_rps.push_command(MQ__RPS_CMD.DEGRADED_SCRAM)
            end
        elseif wl_nic and m_is_wl then
            -- wireless, but not active
            print_no_fp("standby wireless modem disconnected")
            log.info("BKPLN: standby wireless modem disconnected")
        else
            print_no_fp("unassigned modem disconnected")
            log.warning("BKPLN: unassigned modem disconnected")
        end
    end
end

return backplane
