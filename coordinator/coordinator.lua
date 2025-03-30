local comms       = require("scada-common.comms")
local log         = require("scada-common.log")
local ppm         = require("scada-common.ppm")
local util        = require("scada-common.util")
local types       = require("scada-common.types")

local themes      = require("graphics.themes")

local iocontrol   = require("coordinator.iocontrol")
local process     = require("coordinator.process")

local apisessions = require("coordinator.session.apisessions")

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE = comms.MGMT_TYPE
local CRDN_TYPE = comms.CRDN_TYPE
local UNIT_COMMAND = comms.UNIT_COMMAND
local FAC_COMMAND = comms.FAC_COMMAND

local LINK_TIMEOUT = 60.0

local coordinator = {}

---@type crd_config
local config = {}

coordinator.config = config

-- load the coordinator configuration<br>
-- status of 0 is OK, 1 is bad config, 2 is bad monitor config
---@return 0|1|2 status, nil|monitors_struct|string monitors (or error message)
function coordinator.load_config()
    if not settings.load("/coordinator.settings") then return 1 end

    config.UnitCount = settings.get("UnitCount")
    config.SpeakerVolume = settings.get("SpeakerVolume")
    config.Time24Hour = settings.get("Time24Hour")
    config.TempScale = settings.get("TempScale")
    config.EnergyScale = settings.get("EnergyScale")

    config.DisableFlowView = settings.get("DisableFlowView")
    config.MainDisplay = settings.get("MainDisplay")
    config.FlowDisplay = settings.get("FlowDisplay")
    config.UnitDisplays = settings.get("UnitDisplays")

    config.SVR_Channel = settings.get("SVR_Channel")
    config.CRD_Channel = settings.get("CRD_Channel")
    config.PKT_Channel = settings.get("PKT_Channel")
    config.SVR_Timeout = settings.get("SVR_Timeout")
    config.API_Timeout = settings.get("API_Timeout")
    config.TrustedRange = settings.get("TrustedRange")
    config.AuthKey = settings.get("AuthKey")

    config.LogMode = settings.get("LogMode")
    config.LogPath = settings.get("LogPath")
    config.LogDebug = settings.get("LogDebug")

    config.MainTheme = settings.get("MainTheme")
    config.FrontPanelTheme = settings.get("FrontPanelTheme")
    config.ColorMode = settings.get("ColorMode")

    local cfv = util.new_validator()

    cfv.assert_type_int(config.UnitCount)
    cfv.assert_range(config.UnitCount, 1, 4)
    cfv.assert_type_bool(config.Time24Hour)
    cfv.assert_type_int(config.TempScale)
    cfv.assert_range(config.TempScale, 1, 4)
    cfv.assert_type_int(config.EnergyScale)
    cfv.assert_range(config.EnergyScale, 1, 3)

    cfv.assert_type_bool(config.DisableFlowView)
    cfv.assert_type_table(config.UnitDisplays)

    cfv.assert_type_num(config.SpeakerVolume)
    cfv.assert_range(config.SpeakerVolume, 0, 3)

    cfv.assert_channel(config.SVR_Channel)
    cfv.assert_channel(config.CRD_Channel)
    cfv.assert_channel(config.PKT_Channel)

    cfv.assert_type_num(config.SVR_Timeout)
    cfv.assert_min(config.SVR_Timeout, 2)
    cfv.assert_type_num(config.API_Timeout)
    cfv.assert_min(config.API_Timeout, 2)

    cfv.assert_type_num(config.TrustedRange)
    cfv.assert_min(config.TrustedRange, 0)
    cfv.assert_type_str(config.AuthKey)

    if type(config.AuthKey) == "string" then
        local len = string.len(config.AuthKey)
        cfv.assert(len == 0 or len >= 8)
    end

    cfv.assert_type_int(config.LogMode)
    cfv.assert_range(config.LogMode, 0, 1)
    cfv.assert_type_str(config.LogPath)
    cfv.assert_type_bool(config.LogDebug)

    cfv.assert_type_int(config.MainTheme)
    cfv.assert_range(config.MainTheme, 1, 2)
    cfv.assert_type_int(config.FrontPanelTheme)
    cfv.assert_range(config.FrontPanelTheme, 1, 2)
    cfv.assert_type_int(config.ColorMode)
    cfv.assert_range(config.ColorMode, 1, themes.COLOR_MODE.NUM_MODES)

    -- Monitor Setup

    ---@class monitors_struct
    local monitors = {
        main = nil,         ---@type Monitor|nil
        main_name = "",
        flow = nil,         ---@type Monitor|nil
        flow_name = "",
        unit_displays = {}, ---@type Monitor[]
        unit_name_map = {}  ---@type string[]
    }

    local mon_cfv = util.new_validator()

    -- get all interface names
    local names = {}
    for iface, _ in pairs(ppm.get_monitor_list()) do table.insert(names, iface) end

    local function setup_monitors()
        mon_cfv.assert_type_str(config.MainDisplay)
        if not config.DisableFlowView then mon_cfv.assert_type_str(config.FlowDisplay) end
        mon_cfv.assert_eq(#config.UnitDisplays, config.UnitCount)

        if mon_cfv.valid() then
            local w, h, _

            if not util.table_contains(names, config.MainDisplay) then
                return 2, "Tela Primaria desconectada."
            end

            monitors.main = ppm.get_periph(config.MainDisplay)
            monitors.main_name = config.MainDisplay

            monitors.main.setTextScale(0.5)
            w, _ = ppm.monitor_block_size(monitors.main.getSize())
            if w ~= 8 then
                return 2, util.c("Largura da Tela Prim incorreta (era ", w, ", exige 8).")
            end

            if not config.DisableFlowView then
                if not util.table_contains(names, config.FlowDisplay) then
                    return 2, "Tela de Fluxo desconectada."
                end

                monitors.flow = ppm.get_periph(config.FlowDisplay)
                monitors.flow_name = config.FlowDisplay

                monitors.flow.setTextScale(0.5)
                w, _ = ppm.monitor_block_size(monitors.flow.getSize())
                if w ~= 8 then
                    return 2, util.c("Largura da Tela de Fluxo incorreta (era ", w, ", exige 8).")
                end
            end

            for i = 1, config.UnitCount do
                local display = config.UnitDisplays[i]
                if type(display) ~= "string" or not util.table_contains(names, display) then
                    return 2, "Unidade " .. i .. " monitor disconectado."
                end

                monitors.unit_displays[i] = ppm.get_periph(display)
                monitors.unit_name_map[i] = display

                monitors.unit_displays[i].setTextScale(0.5)
                w, h = ppm.monitor_block_size(monitors.unit_displays[i].getSize())
                if w ~= 4 or h ~= 4 then
                    return 2, util.c("Unidade ", i, " largura da tela incorreta (era ", w, " por ", h,", exige ser 4 x 4).")
                end
            end
        else return 2, "Configura\xe7\xe3o da tela invalida." end
    end

    if cfv.valid() then
        local ok, result, message = pcall(setup_monitors)
        assert(ok, util.c("erro fatal enquanto verificava telas:", result))
        if result == 2 then return 2, message end
    else return 1 end

    return 0, monitors
end

-- dmesg print wrapper
---@param message string message
---@param dmesg_tag string tag
---@param working? boolean to use dmesg_working
---@return function? update, function? done
local function log_dmesg(message, dmesg_tag, working)
    local colors = {
        RENDER = colors.green,
        SYSTEM = colors.cyan,
        BOOT = colors.blue,
        COMMS = colors.purple,
        CRYPTO = colors.yellow
    }

    if working then
        return log.dmesg_working(message, dmesg_tag, colors[dmesg_tag])
    else
        log.dmesg(message, dmesg_tag, colors[dmesg_tag])
    end
end

function coordinator.log_render(message) log_dmesg(message, "RENDER") end
function coordinator.log_sys(message) log_dmesg(message, "SYSTEM") end
function coordinator.log_boot(message) log_dmesg(message, "BOOT") end
function coordinator.log_comms(message) log_dmesg(message, "COMMS") end
function coordinator.log_crypto(message) log_dmesg(message, "CRYPTO") end

-- log a message for communications connecting, providing access to progress indication control functions
---@nodiscard
---@param message string
---@return function update, function done
function coordinator.log_comms_connecting(message)
    local update, done = log_dmesg(message, "COMMS", true)
    ---@cast update function
    ---@cast done function
    return update, done
end

-- coordinator communications
---@nodiscard
---@param version string coordinator version
---@param nic nic network interface device
---@param sv_watchdog watchdog
function coordinator.comms(version, nic, sv_watchdog)
    local self = {
        sv_linked = false,
        sv_addr = comms.BROADCAST,
        sv_seq_num = util.time_ms() * 10, -- unique per peer, restarting will not re-use seq nums due to message rate
        sv_r_seq_num = nil,               ---@type nil|integer
        sv_config_err = false,
        last_est_ack = ESTABLISH_ACK.ALLOW,
        last_api_est_acks = {},
        est_start = 0,
        est_last = 0,
        est_tick_waiting = nil,
        est_task_done = nil
    }

    comms.set_trusted_range(config.TrustedRange)

    -- configure network channels
    nic.closeAll()
    nic.open(config.CRD_Channel)

    -- pass config to apisessions
    apisessions.init(nic, config)

    -- PRIVATE FUNCTIONS --

    -- send a packet to the supervisor
    ---@param msg_type MGMT_TYPE|CRDN_TYPE
    ---@param msg table
    local function _send_sv(protocol, msg_type, msg)
        local s_pkt = comms.scada_packet()
        local pkt   ---@type mgmt_packet|crdn_packet

        if protocol == PROTOCOL.SCADA_MGMT then
            pkt = comms.mgmt_packet()
        elseif protocol == PROTOCOL.SCADA_CRDN then
            pkt = comms.crdn_packet()
        else
            return
        end

        pkt.make(msg_type, msg)
        s_pkt.make(self.sv_addr, self.sv_seq_num, protocol, pkt.raw_sendable())

        nic.transmit(config.SVR_Channel, config.CRD_Channel, s_pkt)
        self.sv_seq_num = self.sv_seq_num + 1
    end

    -- send an API establish request response
    ---@param packet scada_packet
    ---@param ack ESTABLISH_ACK
    ---@param data any?
    local function _send_api_establish_ack(packet, ack, data)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(MGMT_TYPE.ESTABLISH, { ack, data })
        s_pkt.make(packet.src_addr(), packet.seq_num() + 1, PROTOCOL.SCADA_MGMT, m_pkt.raw_sendable())

        nic.transmit(config.PKT_Channel, config.CRD_Channel, s_pkt)
        self.last_api_est_acks[packet.src_addr()] = ack
    end

    -- attempt connection establishment
    local function _send_establish()
        self.sv_r_seq_num = nil
        _send_sv(PROTOCOL.SCADA_MGMT, MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.CRD })
    end

    -- keep alive ack
    ---@param srv_time integer
    local function _send_keep_alive_ack(srv_time)
        _send_sv(PROTOCOL.SCADA_MGMT, MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- PUBLIC FUNCTIONS --

    ---@class coord_comms
    local public = {}

    -- try to connect to the supervisor if not already linked
    ---@param abort boolean? true to print out cancel info if not linked (use on program terminate)
    ---@return boolean ok, boolean start_ui
    function public.try_connect(abort)
        local ok = true
        local start_ui = false

        if not self.sv_linked then
            if self.est_tick_waiting == nil then
                self.est_start = os.clock()
                self.est_last = self.est_start

                self.est_tick_waiting, self.est_task_done =
                    coordinator.log_comms_connecting("tentando conectar em um supervisor configurado no canal " .. config.SVR_Channel)

                _send_establish()
            else
                self.est_tick_waiting(math.max(0, LINK_TIMEOUT - (os.clock() - self.est_start)))
            end

            if abort or (os.clock() - self.est_start) >= LINK_TIMEOUT then
                self.est_task_done(false)

                if abort then
                    coordinator.log_comms("tentativa de conex\xe3o com supervisor cancelado por usuario")
                elseif self.sv_config_err then
                    coordinator.log_comms("contador de unidade do supervisor n\xe3o corresponde com as do coordenador, cheque as configura\xe7\xd5es")
                elseif not self.sv_linked then
                    if self.last_est_ack == ESTABLISH_ACK.DENY then
                        coordinator.log_comms("conex\xe3o com supervisor negado")
                    elseif self.last_est_ack == ESTABLISH_ACK.COLLISION then
                        coordinator.log_comms("conex\xe3o com supervisor falha por colis\xe3o")
                    elseif self.last_est_ack == ESTABLISH_ACK.BAD_VERSION then
                        coordinator.log_comms("conex\xe3o com supervisor falha por vers\xe3o incompatível")
                    else
                        coordinator.log_comms("conex\xe3o com supervisor falha por n\xe3o ter resposta valida")
                    end
                end

                ok = false
            elseif self.sv_config_err then
                self.est_task_done(false)
                coordinator.log_comms("contador de unidade do supervisor n\xe3o corresponde com as do coordenador, cheque as configura\xe7\xd5es")
                ok = false
            elseif (os.clock() - self.est_last) > 1.0 then
                _send_establish()
                self.est_last = os.clock()
            end
        elseif self.est_tick_waiting ~= nil then
            self.est_task_done(true)
            self.est_tick_waiting = nil
            self.est_task_done = nil
            start_ui = true
        end

        return ok, start_ui
    end

    -- close the connection to the server
    function public.close()
        sv_watchdog.cancel()
        self.sv_addr = comms.BROADCAST
        self.sv_linked = false
        self.sv_r_seq_num = nil
        iocontrol.fp_link_state(types.PANEL_LINK_STATE.DISCONNECTED)
        _send_sv(PROTOCOL.SCADA_MGMT, MGMT_TYPE.CLOSE, {})
    end

    -- send the resume ready state to the supervisor
    ---@param mode PROCESS process control mode
    ---@param burn_target number burn rate target
    ---@param charge_target number charge level target
    ---@param gen_target number generation rate target
    ---@param limits number[] unit burn rate limits
    function public.send_ready(mode, burn_target, charge_target, gen_target, limits)
        _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.PROCESS_READY, {
            mode, burn_target, charge_target, gen_target, limits
        })
    end

    -- send a facility command
    ---@param cmd FAC_COMMAND command
    ---@param option any? optional option options for the optional options (like waste mode)
    function public.send_fac_command(cmd, option)
        _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.FAC_CMD, { cmd, option })
    end

    -- send the auto process control configuration with a start command
    ---@param mode PROCESS process control mode
    ---@param burn_target number burn rate target
    ---@param charge_target number charge level target
    ---@param gen_target number generation rate target
    ---@param limits number[] unit burn rate limits
    function public.send_auto_start(mode, burn_target, charge_target, gen_target, limits)
        _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.FAC_CMD, {
            FAC_COMMAND.START, mode, burn_target, charge_target, gen_target, limits
        })
    end

    -- send a unit command
    ---@param cmd UNIT_COMMAND command
    ---@param unit integer unit ID
    ---@param option any? optional option options for the optional options (like burn rate)
    function public.send_unit_command(cmd, unit, option)
        _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.UNIT_CMD, { cmd, unit, option })
    end

    -- parse a packet
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return mgmt_frame|crdn_frame|nil packet
    function public.parse_packet(side, sender, reply_to, message, distance)
        local s_pkt = nic.receive(side, sender, reply_to, message, distance)
        local pkt = nil

        if s_pkt then
            -- get as SCADA management packet
            if s_pkt.protocol() == PROTOCOL.SCADA_MGMT then
                local mgmt_pkt = comms.mgmt_packet()
                if mgmt_pkt.decode(s_pkt) then
                    pkt = mgmt_pkt.get()
                end
            -- get as coordinator packet
            elseif s_pkt.protocol() == PROTOCOL.SCADA_CRDN then
                local crdn_pkt = comms.crdn_packet()
                if crdn_pkt.decode(s_pkt) then
                    pkt = crdn_pkt.get()
                end
            else
                log.debug("attempted parse of illegal packet type " .. s_pkt.protocol(), true)
            end
        end

        return pkt
    end

    -- handle a packet
    ---@param packet mgmt_frame|crdn_frame|nil
    ---@return boolean close_ui
    function public.handle_packet(packet)
        local was_linked = self.sv_linked

        if packet ~= nil then
            local l_chan = packet.scada_frame.local_channel()
            local r_chan = packet.scada_frame.remote_channel()
            local src_addr = packet.scada_frame.src_addr()
            local protocol = packet.scada_frame.protocol()

            if l_chan ~= config.CRD_Channel then
                log.debug("received packet on unconfigured channel " .. l_chan, true)
            elseif r_chan == config.PKT_Channel then
                if not self.sv_linked then
                    log.debug("discarding pocket API packet before linked to supervisor")
                elseif protocol == PROTOCOL.SCADA_CRDN then
                    ---@cast packet crdn_frame
                    -- look for an associated session
                    local session = apisessions.find_session(src_addr)

                    -- coordinator packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    else
                        -- any other packet should be session related, discard it
                        log.debug("discarding SCADA_CRDN packet without a known session")
                    end
                elseif protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_frame
                    -- look for an associated session
                    local session = apisessions.find_session(src_addr)

                    -- SCADA management packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    elseif packet.type == MGMT_TYPE.ESTABLISH then
                        -- establish a new session
                        -- validate packet and continue
                        if packet.length == 4 then
                            local comms_v = util.strval(packet.data[1])
                            local firmware_v = util.strval(packet.data[2])
                            local dev_type = packet.data[3]
                            local api_v = util.strval(packet.data[4])

                            if comms_v ~= comms.version then
                                if self.last_api_est_acks[src_addr] ~= ESTABLISH_ACK.BAD_VERSION then
                                    log.info(util.c("dropping API establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
                                end

                                _send_api_establish_ack(packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
                            elseif api_v ~= comms.api_version then
                                if self.last_api_est_acks[src_addr] ~= ESTABLISH_ACK.BAD_API_VERSION then
                                    log.info(util.c("dropping API establish packet with incorrect api version v", api_v, " (expected v", comms.api_version, ")"))
                                end

                                _send_api_establish_ack(packet.scada_frame, ESTABLISH_ACK.BAD_API_VERSION)
                            elseif dev_type == DEVICE_TYPE.PKT then
                                -- pocket linking request
                                local id = apisessions.establish_session(src_addr, packet.scada_frame.seq_num(), firmware_v)
                                coordinator.log_comms(util.c("API_ESTABLISH: pocket (", firmware_v, ") [@", src_addr, "] connected with session ID ", id))

                                local conf = iocontrol.get_db().facility.conf
                                _send_api_establish_ack(packet.scada_frame, ESTABLISH_ACK.ALLOW, { conf.num_units, conf.cooling })
                            else
                                log.debug(util.c("API_ESTABLISH: illegal establish packet for device ", dev_type, " on pocket channel"))
                                _send_api_establish_ack(packet.scada_frame, ESTABLISH_ACK.DENY)
                            end
                        else
                            log.debug("invalid establish packet (on API listening channel)")
                            _send_api_establish_ack(packet.scada_frame, ESTABLISH_ACK.DENY)
                        end
                    else
                        -- any other packet should be session related, discard it
                        log.debug(util.c("discarding pocket SCADA_MGMT packet without a known session from computer ", src_addr))
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " on pocket channel", true)
                end
            elseif r_chan == config.SVR_Channel then
                -- check sequence number
                if self.sv_r_seq_num == nil then
                    self.sv_r_seq_num = packet.scada_frame.seq_num() + 1
                elseif self.sv_r_seq_num ~= packet.scada_frame.seq_num() then
                    log.warning("sequence out-of-order: next = " .. self.sv_r_seq_num .. ", new = " .. packet.scada_frame.seq_num())
                    return false
                elseif self.sv_linked and src_addr ~= self.sv_addr then
                    log.debug("received packet from unknown computer " .. src_addr .. " while linked; channel in use by another system?")
                    return false
                else
                    self.sv_r_seq_num = packet.scada_frame.seq_num() + 1
                end

                -- feed watchdog on valid sequence number
                sv_watchdog.feed()

                -- handle packet
                if protocol == PROTOCOL.SCADA_CRDN then
                    ---@cast packet crdn_frame
                    if self.sv_linked then
                        if packet.type == CRDN_TYPE.INITIAL_BUILDS then
                            if packet.length == 2 then
                                -- record builds
                                local fac_builds = iocontrol.record_facility_builds(packet.data[1])
                                local unit_builds = iocontrol.record_unit_builds(packet.data[2])

                                if fac_builds and unit_builds then
                                    -- acknowledge receipt of builds
                                    _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.INITIAL_BUILDS, {})
                                else
                                    log.debug("received invalid INITIAL_BUILDS packet")
                                end
                            else
                                log.debug("INITIAL_BUILDS packet length mismatch")
                            end
                        elseif packet.type == CRDN_TYPE.FAC_BUILDS then
                            if packet.length == 1 then
                                -- record facility builds
                                if iocontrol.record_facility_builds(packet.data[1]) then
                                    -- acknowledge receipt of builds
                                    _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.FAC_BUILDS, {})
                                else
                                    log.debug("received invalid FAC_BUILDS packet")
                                end
                            else
                                log.debug("FAC_BUILDS packet length mismatch")
                            end
                        elseif packet.type == CRDN_TYPE.FAC_STATUS then
                            -- update facility status
                            if not iocontrol.update_facility_status(packet.data) then
                                log.debug("received invalid FAC_STATUS packet")
                            end
                        elseif packet.type == CRDN_TYPE.FAC_CMD then
                            -- facility command acknowledgement
                            if packet.length >= 2 then
                                local cmd = packet.data[1]
                                local ack = packet.data[2] == true

                                if cmd == FAC_COMMAND.SCRAM_ALL then
                                    process.fac_ack(cmd, ack)
                                elseif cmd == FAC_COMMAND.STOP then
                                    process.fac_ack(cmd, ack)
                                elseif cmd == FAC_COMMAND.START then
                                    if packet.length == 7 then
                                        process.start_ack_handle({ table.unpack(packet.data, 2) })
                                    else
                                        log.debug("SCADA_CRDN process start (with configuration) ack echo packet length mismatch")
                                    end
                                elseif cmd == FAC_COMMAND.ACK_ALL_ALARMS then
                                    process.fac_ack(cmd, ack)
                                elseif cmd == FAC_COMMAND.SET_WASTE_MODE then
                                    process.waste_ack_handle(packet.data[2])
                                elseif cmd == FAC_COMMAND.SET_PU_FB then
                                    process.pu_fb_ack_handle(packet.data[2])
                                elseif cmd == FAC_COMMAND.SET_SPS_LP then
                                    process.sps_lp_ack_handle(packet.data[2])
                                else
                                    log.debug(util.c("received facility command ack with unknown command ", cmd))
                                end
                            else
                                log.debug("SCADA_CRDN facility command ack packet length mismatch")
                            end
                        elseif packet.type == CRDN_TYPE.UNIT_BUILDS then
                            -- record builds
                            if packet.length == 1 then
                                if iocontrol.record_unit_builds(packet.data[1]) then
                                    -- acknowledge receipt of builds
                                    _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.UNIT_BUILDS, {})
                                else
                                    log.debug("received invalid UNIT_BUILDS packet")
                                end
                            else
                                log.debug("UNIT_BUILDS packet length mismatch")
                            end
                        elseif packet.type == CRDN_TYPE.UNIT_STATUSES then
                            -- update statuses
                            if not iocontrol.update_unit_statuses(packet.data) then
                                log.debug("received invalid UNIT_STATUSES packet")
                            end
                        elseif packet.type == CRDN_TYPE.UNIT_CMD then
                            -- unit command acknowledgement
                            if packet.length == 3 then
                                local cmd = packet.data[1]
                                local unit_id = packet.data[2]
                                local ack = packet.data[3] == true

                                local unit = iocontrol.get_db().units[unit_id]

                                if unit ~= nil then
                                    if cmd == UNIT_COMMAND.SCRAM then
                                        process.unit_ack(unit_id, cmd, ack)
                                    elseif cmd == UNIT_COMMAND.START then
                                        process.unit_ack(unit_id, cmd, ack)
                                    elseif cmd == UNIT_COMMAND.RESET_RPS then
                                        process.unit_ack(unit_id, cmd, ack)
                                    elseif cmd == UNIT_COMMAND.ACK_ALL_ALARMS then
                                        process.unit_ack(unit_id, cmd, ack)
                                    else
                                        log.debug(util.c("received unsupported unit command ack for command ", cmd))
                                    end
                                else
                                    log.debug(util.c("received unit command ack with unknown unit ", unit_id))
                                end
                            else
                                log.debug("SCADA_CRDN unit command ack packet length mismatch")
                            end
                        else
                            log.debug("received unknown SCADA_CRDN packet type " .. packet.type)
                        end
                    else
                        log.debug("discarding SCADA_CRDN packet before linked")
                    end
                elseif protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_frame
                    if self.sv_linked then
                        if packet.type == MGMT_TYPE.KEEP_ALIVE then
                            -- keep alive request received, echo back
                            if packet.length == 1 then
                                local timestamp = packet.data[1]
                                local trip_time = util.time() - timestamp

                                if trip_time > 750 then
                                    log.warning("coordinator KEEP_ALIVE trip time > 750ms (" .. trip_time .. "ms)")
                                end

                                -- log.debug("coordinator RTT = " .. trip_time .. "ms")

                                iocontrol.get_db().facility.ps.publish("sv_ping", trip_time)

                                _send_keep_alive_ack(timestamp)
                            else
                                log.debug("SCADA keep alive packet length mismatch")
                            end
                        elseif packet.type == MGMT_TYPE.CLOSE then
                            -- handle session close
                            sv_watchdog.cancel()
                            self.sv_addr = comms.BROADCAST
                            self.sv_linked = false
                            self.sv_r_seq_num = nil
                            iocontrol.fp_link_state(types.PANEL_LINK_STATE.DISCONNECTED)
                            log.info("server connection closed by remote host")
                        else
                            log.debug("received unknown SCADA_MGMT packet type " .. packet.type)
                        end
                    elseif packet.type == MGMT_TYPE.ESTABLISH then
                        -- connection with supervisor established
                        if packet.length == 2 then
                            local est_ack = packet.data[1]
                            local sv_config = packet.data[2]

                            if est_ack == ESTABLISH_ACK.ALLOW then
                                -- reset to disconnected before validating
                                iocontrol.fp_link_state(types.PANEL_LINK_STATE.DISCONNECTED)

                                if type(sv_config) == "table" and #sv_config == 2 then
                                    -- get configuration

                                    ---@class facility_conf
                                    local conf = {
                                        num_units = sv_config[1], ---@type integer
                                        cooling = sv_config[2]    ---@type sv_cooling_conf
                                    }

                                    if conf.num_units == config.UnitCount then
                                        -- init io controller
                                        iocontrol.init(conf, public, config.TempScale, config.EnergyScale)

                                        self.sv_addr = src_addr
                                        self.sv_linked = true
                                        self.sv_config_err = false

                                        iocontrol.fp_link_state(types.PANEL_LINK_STATE.LINKED)
                                    else
                                        self.sv_config_err = true
                                        log.warning("supervisor config's number of units don't match coordinator's config, establish failed")
                                    end
                                else
                                    log.debug("invalid supervisor configuration table received, establish failed")
                                end
                            else
                                log.debug("SCADA_MGMT establish packet reply (len = 2) unsupported")
                            end

                            self.last_est_ack = est_ack
                        elseif packet.length == 1 then
                            local est_ack = packet.data[1]

                            if est_ack == ESTABLISH_ACK.DENY then
                                if self.last_est_ack ~= est_ack then
                                    iocontrol.fp_link_state(types.PANEL_LINK_STATE.DENIED)
                                    log.info("conex\xe3o com supervisor negado")
                                end
                            elseif est_ack == ESTABLISH_ACK.COLLISION then
                                if self.last_est_ack ~= est_ack then
                                    iocontrol.fp_link_state(types.PANEL_LINK_STATE.COLLISION)
                                    log.warning("conex\xe3o com supervisor negado por colis\xe3o")
                                end
                            elseif est_ack == ESTABLISH_ACK.BAD_VERSION then
                                if self.last_est_ack ~= est_ack then
                                    iocontrol.fp_link_state(types.PANEL_LINK_STATE.BAD_VERSION)
                                    log.warning("supervisor comms version mismatch/vers\xe3o do su")
                                end
                            else
                                log.debug("SCADA_MGMT establish packet reply (len = 1) unsupported")
                            end

                            self.last_est_ack = est_ack
                        else
                            log.debug("SCADA_MGMT establish packet length mismatch")
                        end
                    else
                        log.debug("discarding non-link SCADA_MGMT packet before linked")
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " on supervisor listening channel", true)
                end
            else
                log.debug("received packet for unknown channel " .. r_chan, true)
            end
        end

        return was_linked and not self.sv_linked
    end

    -- check if the coordinator is still linked to the supervisor
    ---@nodiscard
    function public.is_linked() return self.sv_linked end

    return public
end

return coordinator
