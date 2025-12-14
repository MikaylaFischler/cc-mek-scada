local comms      = require("scada-common.comms")
local log        = require("scada-common.log")
local types      = require("scada-common.types")
local util       = require("scada-common.util")

local themes     = require("graphics.themes")

local backplane  = require("supervisor.backplane")

local svsessions = require("supervisor.session.svsessions")

local supervisor = {}

local PROTOCOL      = comms.PROTOCOL
local DEVICE_TYPE   = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE     = comms.MGMT_TYPE

local LISTEN_MODE   = types.LISTEN_MODE

---@type svr_config
---@diagnostic disable-next-line: missing-fields
local config = {}

supervisor.config = config

-- control state from last unexpected shutdown
supervisor.boot_state = nil ---@type sv_boot_state|nil

-- load the supervisor configuration and startup state
function supervisor.load_config()
    if not settings.load("/supervisor.settings") then return false end

    ---@class sv_boot_state
    local boot_state = {
        mode = settings.get("LastProcessState"),     ---@type PROCESS
        unit_states = settings.get("LastUnitStates") ---@type boolean[]
    }

    -- only record boot state if likely valid
    if type(boot_state.mode) == "number" and type(boot_state.unit_states) == "table" then
        supervisor.boot_state = boot_state
    end

    config.UnitCount = settings.get("UnitCount")
    config.CoolingConfig = settings.get("CoolingConfig")
    config.FacilityTankMode = settings.get("FacilityTankMode")
    config.FacilityTankDefs = settings.get("FacilityTankDefs")
    config.FacilityTankList = settings.get("FacilityTankList")
    config.FacilityTankConns = settings.get("FacilityTankConns")
    config.TankFluidTypes = settings.get("TankFluidTypes")
    config.AuxiliaryCoolant = settings.get("AuxiliaryCoolant")
    config.ExtChargeIdling = settings.get("ExtChargeIdling")

    config.WirelessModem = settings.get("WirelessModem")
    config.WiredModem = settings.get("WiredModem")

    config.PLC_Listen = settings.get("PLC_Listen")
    config.RTU_Listen = settings.get("RTU_Listen")
    config.CRD_Listen = settings.get("CRD_Listen")

    config.PocketEnabled = settings.get("PocketEnabled")
    config.PocketTest = settings.get("PocketTest")

    config.SVR_Channel = settings.get("SVR_Channel")
    config.PLC_Channel = settings.get("PLC_Channel")
    config.RTU_Channel = settings.get("RTU_Channel")
    config.CRD_Channel = settings.get("CRD_Channel")
    config.PKT_Channel = settings.get("PKT_Channel")

    config.PLC_Timeout = settings.get("PLC_Timeout")
    config.RTU_Timeout = settings.get("RTU_Timeout")
    config.CRD_Timeout = settings.get("CRD_Timeout")
    config.PKT_Timeout = settings.get("PKT_Timeout")

    config.TrustedRange = settings.get("TrustedRange")
    config.AuthKey = settings.get("AuthKey")

    config.LogMode = settings.get("LogMode")
    config.LogPath = settings.get("LogPath")
    config.LogDebug = settings.get("LogDebug")

    config.FrontPanelTheme = settings.get("FrontPanelTheme")
    config.ColorMode = settings.get("ColorMode")

    local cfv = util.new_validator()

    cfv.assert_type_int(config.UnitCount)
    cfv.assert_range(config.UnitCount, 1, 4)

    cfv.assert_type_table(config.CoolingConfig)
    cfv.assert_type_int(config.FacilityTankMode)
    cfv.assert_type_table(config.FacilityTankDefs)
    cfv.assert_type_table(config.FacilityTankList)
    cfv.assert_type_table(config.FacilityTankConns)
    cfv.assert_type_table(config.TankFluidTypes)
    cfv.assert_type_table(config.AuxiliaryCoolant)
    cfv.assert_range(config.FacilityTankMode, 0, 8)

    cfv.assert_type_bool(config.ExtChargeIdling)

    cfv.assert_type_bool(config.WirelessModem)
    cfv.assert((config.WiredModem == false) or (type(config.WiredModem) == "string"))
    cfv.assert((config.WirelessModem == true) or (type(config.WiredModem) == "string"))

    cfv.assert_type_int(config.PLC_Listen)
    cfv.assert_range(config.PLC_Listen, 1, 3)
    cfv.assert_type_int(config.RTU_Listen)
    cfv.assert_range(config.RTU_Listen, 1, 3)
    cfv.assert_type_int(config.CRD_Listen)
    cfv.assert_range(config.CRD_Listen, 1, 3)

    cfv.assert_type_bool(config.PocketEnabled)
    cfv.assert_type_bool(config.PocketTest)

    cfv.assert_channel(config.SVR_Channel)
    cfv.assert_channel(config.PLC_Channel)
    cfv.assert_channel(config.RTU_Channel)
    cfv.assert_channel(config.CRD_Channel)
    cfv.assert_channel(config.PKT_Channel)

    cfv.assert_type_num(config.PLC_Timeout)
    cfv.assert_min(config.PLC_Timeout, 2)
    cfv.assert_type_num(config.RTU_Timeout)
    cfv.assert_min(config.RTU_Timeout, 2)
    cfv.assert_type_num(config.CRD_Timeout)
    cfv.assert_min(config.CRD_Timeout, 2)
    cfv.assert_type_num(config.PKT_Timeout)
    cfv.assert_min(config.PKT_Timeout, 2)

    cfv.assert_type_num(config.TrustedRange)
    cfv.assert_min(config.TrustedRange, 0)

    if type(config.AuthKey) == "string" then
        local len = string.len(config.AuthKey)
        cfv.assert(len == 0 or len >= 8)
    end

    cfv.assert_type_int(config.LogMode)
    cfv.assert_range(config.LogMode, 0, 1)
    cfv.assert_type_str(config.LogPath)
    cfv.assert_type_bool(config.LogDebug)

    cfv.assert_type_int(config.FrontPanelTheme)
    cfv.assert_range(config.FrontPanelTheme, 1, 2)
    cfv.assert_type_int(config.ColorMode)
    cfv.assert_range(config.ColorMode, 1, themes.COLOR_MODE.NUM_MODES)

    return cfv.valid()
end

-- supervisory controller communications
---@nodiscard
---@param _version string supervisor version
---@param fp_ok boolean if the front panel UI is running
---@param facility facility facility instance
---@diagnostic disable-next-line: unused-local
function supervisor.comms(_version, fp_ok, facility)
    -- print a log message to the terminal as long as the UI isn't running
    local function println(message) if not fp_ok then util.println_ts(message) end end

    local self = {
        last_est_acks = {}  ---@type ESTABLISH_ACK[]
    }

    if config.WirelessModem then
        comms.set_trusted_range(config.TrustedRange)
    end

    -- pass system data and objects to svsessions
    svsessions.init(fp_ok, config, facility)

    --#region PRIVATE FUNCTIONS --

    -- send an establish request response
    ---@param nic nic
    ---@param rx_frame scada_frame
    ---@param ack ESTABLISH_ACK
    ---@param data? any optional data
    local function _send_establish(nic, rx_frame, ack, data)
        local tx_frame, mgmt = comms.scada_frame(), comms.mgmt_container()

        mgmt.make(MGMT_TYPE.ESTABLISH, { ack, data })
        tx_frame.make(rx_frame.src_addr(), rx_frame.seq_num() + 1, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())

        nic.transmit(rx_frame.remote_channel(), config.SVR_Channel, tx_frame)
        self.last_est_acks[rx_frame.src_addr()] = ack
    end

    --#region Establish Handlers

    -- handle a PLC establish
    ---@param nic nic
    ---@param packet mgmt_packet
    ---@param src_addr integer
    ---@param i_seq_num integer
    ---@param last_ack ESTABLISH_ACK
    local function _establish_plc(nic, packet, src_addr, i_seq_num, last_ack)
        local comms_v    = packet.data[1]
        local firmware_v = packet.data[2]
        local dev_type   = packet.data[3]

        if (config.PLC_Listen ~= LISTEN_MODE.ALL) and (nic.isWireless() ~= (config.PLC_Listen == LISTEN_MODE.WIRELESS)) and periphemu == nil then
            -- drop if not listening
        elseif comms_v ~= comms.version then
            if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
                log.info(util.c("PLC_ESTABLISH: PLC [@", src_addr, "] dropping PLC establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
            end

            _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
        elseif dev_type == DEVICE_TYPE.PLC then
            -- PLC linking request
            if packet.length == 4 and type(packet.data[4]) == "number" then
                local reactor_id = packet.data[4]

                -- check ID validity
                if reactor_id < 1 or reactor_id > config.UnitCount then
                    -- reactor index out of range
                    if last_ack ~= ESTABLISH_ACK.DENY then
                        log.warning(util.c("PLC_ESTABLISH: PLC [@", src_addr, "] denied assignment ", reactor_id, " outside of configured unit count ", config.UnitCount))
                    end

                    _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
                else
                    -- try to establish the session
                    local plc_id = svsessions.establish_plc_session(nic, src_addr, i_seq_num, reactor_id, firmware_v)

                    if plc_id == false then
                        -- reactor already has a PLC assigned
                        if last_ack ~= ESTABLISH_ACK.COLLISION then
                            log.warning(util.c("PLC_ESTABLISH: PLC [@", src_addr, "] assignment collision with reactor ", reactor_id))
                        end

                        _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.COLLISION)
                    elseif plc_id == true then
                        -- valid, but this was just a test
                        log.info(util.c("PLC_ESTABLISH: PLC [@", src_addr, "] sending connection test success response on ", nic.phy_name()))
                        _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW)
                    else
                        -- got an ID; assigned to a reactor successfully
                        println(util.c("PLC (", firmware_v, ") [@", src_addr, "] \xbb reactor ", reactor_id, " connected"))
                        log.info(util.c("PLC_ESTABLISH: PLC [@", src_addr, "] (", firmware_v, ") reactor unit ", reactor_id, " PLC connected with session ID ", plc_id, " on ", nic.phy_name()))
                        _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW)
                    end
                end
            else
                log.debug("PLC_ESTABLISH: [@" .. src_addr .. "] packet length mismatch/bad parameter type")
                _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
            end
        else
            log.debug(util.c("PLC_ESTABLISH: [@", src_addr, "] illegal establish packet for device ", dev_type, " on PLC channel"))
            _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
        end
    end

    -- handle an RTU gateway establish
    ---@param nic nic
    ---@param packet mgmt_packet
    ---@param src_addr integer
    ---@param i_seq_num integer
    ---@param last_ack ESTABLISH_ACK
    local function _establish_rtu_gw(nic, packet, src_addr, i_seq_num, last_ack)
        local comms_v    = packet.data[1]
        local firmware_v = packet.data[2]
        local dev_type   = packet.data[3]

        if (config.RTU_Listen ~= LISTEN_MODE.ALL) and (nic.isWireless() ~= (config.RTU_Listen == LISTEN_MODE.WIRELESS)) and periphemu == nil then
            -- drop if not listening
        elseif comms_v ~= comms.version then
            if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
                log.info(util.c("RTU_GW_ESTABLISH: [@", src_addr, "] dropping RTU_GW establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
            end

            _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
        elseif dev_type == DEVICE_TYPE.RTU then
            if packet.length == 4 then
                if firmware_v ~= comms.CONN_TEST_FWV then
                    -- this is an RTU advertisement for a new session
                    local rtu_advert = packet.data[4]
                    local s_id = svsessions.establish_rtu_session(nic, src_addr, i_seq_num, rtu_advert, firmware_v)

                    println(util.c("RTU (", firmware_v, ") [@", src_addr, "] \xbb connected"))
                    log.info(util.c("RTU_GW_ESTABLISH: [@", src_addr, "] RTU_GW (",firmware_v, ") connected with session ID ", s_id, " on ", nic.phy_name()))
                    _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW)
                else
                    -- valid, but this was just a test
                    log.info(util.c("RTU_GW_ESTABLISH: RTU_GW [@", src_addr, "] sending connection test success response on ", nic.phy_name()))
                    _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW)
                end
            else
                log.debug("RTU_GW_ESTABLISH: [@" .. src_addr .. "] packet length mismatch")
                _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
            end
        else
            log.debug(util.c("RTU_GW_ESTABLISH: [@", src_addr, "] illegal establish packet for device ", dev_type, " on RTU channel"))
            _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
        end
    end

    -- handle a coordinator establish
    ---@param nic nic
    ---@param packet mgmt_packet
    ---@param src_addr integer
    ---@param i_seq_num integer
    ---@param last_ack ESTABLISH_ACK
    local function _establish_crd(nic, packet, src_addr, i_seq_num, last_ack)
        local comms_v    = packet.data[1]
        local firmware_v = packet.data[2]
        local dev_type   = packet.data[3]

        if (config.CRD_Listen ~= LISTEN_MODE.ALL) and (nic.isWireless() ~= (config.CRD_Listen == LISTEN_MODE.WIRELESS)) and periphemu == nil then
            -- drop if not listening
        elseif comms_v ~= comms.version then
            if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
                log.info(util.c("CRD_ESTABLISH: [@", src_addr, "] dropping coordinator establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
            end

            _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
        elseif dev_type == DEVICE_TYPE.CRD then
            -- this is an attempt to establish a new coordinator session
            local s_id = svsessions.establish_crd_session(nic, src_addr, i_seq_num, firmware_v)

            if s_id ~= false then
                println(util.c("CRD (", firmware_v, ") [@", src_addr, "] \xbb connected"))
                log.info(util.c("CRD_ESTABLISH: [@", src_addr, "] CRD (", firmware_v, ") connected with session ID ", s_id, " on ", nic.phy_name()))

                _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW, { config.UnitCount, facility.get_cooling_conf() })
            else
                if last_ack ~= ESTABLISH_ACK.COLLISION then
                    log.info("CRD_ESTABLISH: [@" .. src_addr .. "] denied new coordinator due to already being connected to another coordinator")
                end

                _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.COLLISION)
            end
        else
            log.debug(util.c("CRD_ESTABLISH: [@", src_addr, "] illegal establish packet for device ", dev_type, " on CRD channel"))
            _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
        end
    end

    -- handle a pocket debug establish
    ---@param nic nic
    ---@param packet mgmt_packet
    ---@param src_addr integer
    ---@param i_seq_num integer
    ---@param last_ack ESTABLISH_ACK
    local function _establish_pdg(nic, packet, src_addr, i_seq_num, last_ack)
        local comms_v    = packet.data[1]
        local firmware_v = packet.data[2]
        local dev_type   = packet.data[3]

        if not config.PocketEnabled then
            -- drop if not listening
        elseif comms_v ~= comms.version then
            if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
                log.info(util.c("PDG_ESTABLISH: [@", src_addr, "] dropping PKT establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
            end

            _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
        elseif dev_type == DEVICE_TYPE.PKT then
            -- this is an attempt to establish a new pocket diagnostic session
            local s_id = svsessions.establish_pdg_session(nic, src_addr, i_seq_num, firmware_v)

            println(util.c("PKT (", firmware_v, ") [@", src_addr, "] \xbb connected"))
            log.info(util.c("PDG_ESTABLISH: [@", src_addr, "] pocket (", firmware_v, ") connected with session ID ", s_id, " on ", nic.phy_name()))

            _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.ALLOW)
        else
            log.debug(util.c("PDG_ESTABLISH: [@", src_addr, "] illegal establish packet for device ", dev_type, " on PKT channel"))
            _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
        end

    end

    --#endregion

    --#endregion

    --#region PUBLIC FUNCTIONS --

    ---@class superv_comms
    local public = {}

    -- parse a packet
    ---@nodiscard
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return modbus_adu|rplc_packet|mgmt_packet|crdn_packet|nil packet
    function public.parse_packet(side, sender, reply_to, message, distance)
        local pkt, frame, nic = nil, nil, backplane.nics[side]

        if nic then
            frame = nic.receive(side, sender, reply_to, message, distance)
        else
            log.error("parse_packet(" .. side .. "): received a packet from an interface without a nic?")
        end

        if frame then
            if frame.protocol() == PROTOCOL.MODBUS_TCP then
                pkt = comms.modbus_container().decode(frame)
            elseif frame.protocol() == PROTOCOL.RPLC then
                pkt = comms.rplc_container().decode(frame)
            elseif frame.protocol() == PROTOCOL.SCADA_MGMT then
                pkt = comms.mgmt_container().decode(frame)
            elseif frame.protocol() == PROTOCOL.SCADA_CRDN then
                pkt = comms.crdn_container().decode(frame)
            else
                log.debug("parse_packet(" .. side .. "): attempted parse of illegal packet type " .. frame.protocol(), true)
            end
        end

        return pkt
    end

    -- handle a packet
    ---@param packet modbus_adu|rplc_packet|mgmt_packet|crdn_packet
    function public.handle_packet(packet)
        local nic       = backplane.nics[packet.scada_frame.interface()]
        local l_chan    = packet.scada_frame.local_channel()
        local r_chan    = packet.scada_frame.remote_channel()
        local src_addr  = packet.scada_frame.src_addr()
        local protocol  = packet.scada_frame.protocol()
        local i_seq_num = packet.scada_frame.seq_num()

        if l_chan ~= config.SVR_Channel then
            log.debug("received packet on unconfigured channel " .. l_chan, true)
        elseif r_chan == config.PLC_Channel then
            -- look for an associated session
            local session = svsessions.find_plc_session(src_addr)

            if session then
                if nic ~= session.nic then
                    -- this is from the same device but on a different interface
                    -- drop unless it is a connection transfer
                    if (protocol == PROTOCOL.SCADA_MGMT) and (packet.type == MGMT_TYPE.SWITCH_NET) then
                        session.nic = nic
                        session.in_queue.push_network(packet)

                        log.info(util.c("switched session ", session, " to ", nic.phy_name()))
                    else
                        log.debug(util.c("unexpected packet for PLC @ ", src_addr, " received on ", nic.phy_name()))
                    end
                else
                    -- pass the packet onto the session handler
                    session.in_queue.push_network(packet)
                end
            elseif protocol == PROTOCOL.RPLC then
                -- reactor PLC packet should be session related, discard it
                log.debug("discarding RPLC packet without a known session")
            elseif protocol == PROTOCOL.SCADA_MGMT then
                ---@cast packet mgmt_packet
                -- SCADA management packet
                if packet.type == MGMT_TYPE.ESTABLISH then
                    -- establish a new session: validate packet and continue
                    if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                        _establish_plc(nic, packet, src_addr, i_seq_num, self.last_est_acks[src_addr])
                    else
                        log.debug("invalid establish packet (on PLC channel)")
                        _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
                    end
                else
                    -- any other packet should be session related, discard it
                    log.debug(util.c("discarding PLC SCADA_MGMT packet without a known session from computer ", src_addr))
                end
            else
                log.debug(util.c("illegal packet type ", protocol, " on PLC channel"))
            end
        elseif r_chan == config.RTU_Channel then
            -- look for an associated session
            local session = svsessions.find_rtu_session(src_addr)

            if session then
                if nic ~= session.nic then
                    -- this is from the same device but on a different interface
                    -- drop unless it is a connection transfer
                    if (protocol == PROTOCOL.SCADA_MGMT) and (packet.type == MGMT_TYPE.SWITCH_NET) then
                        session.nic = nic
                        session.in_queue.push_network(packet)

                        log.info(util.c("switched session ", session, " to ", nic.phy_name()))
                    else
                        log.debug(util.c("unexpected packet for RTU_GW @ ", src_addr, " received on ", nic.phy_name()))
                    end
                else
                    -- pass the packet onto the session handler
                    session.in_queue.push_network(packet)
                end
            elseif protocol == PROTOCOL.MODBUS_TCP then
                ---@cast packet modbus_adu
                -- MODBUS response, should be session related, discard it
                log.debug("discarding MODBUS_TCP packet without a known session")
            elseif protocol == PROTOCOL.SCADA_MGMT then
                ---@cast packet mgmt_packet
                -- SCADA management packet
                if packet.type == MGMT_TYPE.ESTABLISH then
                    -- establish a new session: validate packet and continue
                    if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                        _establish_rtu_gw(nic, packet, src_addr, i_seq_num, self.last_est_acks[src_addr])
                    else
                        log.debug("invalid establish packet (on RTU channel)")
                        _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
                    end
                else
                    -- any other packet should be session related, discard it
                    log.debug(util.c("discarding RTU gateway SCADA_MGMT packet without a known session from computer ", src_addr))
                end
            else
                log.debug(util.c("illegal packet type ", protocol, " on RTU channel"))
            end
        elseif r_chan == config.CRD_Channel then
            -- look for an associated session
            local session = svsessions.find_crd_session(src_addr)

            if session then
                if nic ~= session.nic then
                    -- this is from the same device but on a different interface
                    -- drop unless it is a connection transfer
                    if (protocol == PROTOCOL.SCADA_MGMT) and (packet.type == MGMT_TYPE.SWITCH_NET) then
                        session.nic = nic
                        session.in_queue.push_network(packet)

                        log.info(util.c("switched session ", session, " to ", nic.phy_name()))
                    else
                        log.debug(util.c("unexpected packet for CRD @ ", src_addr, " received on ", nic.phy_name()))
                    end
                else
                    -- pass the packet onto the session handler
                    session.in_queue.push_network(packet)
                end
            elseif protocol == PROTOCOL.SCADA_MGMT then
                ---@cast packet mgmt_packet
                -- SCADA management packet
                if packet.type == MGMT_TYPE.ESTABLISH then
                    -- establish a new session: validate packet and continue
                    if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                        _establish_crd(nic, packet, src_addr, i_seq_num, self.last_est_acks[src_addr])
                    else
                        log.debug("CRD_ESTABLISH: establish packet length mismatch")
                        _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
                    end
                else
                    -- any other packet should be session related, discard it
                    log.debug(util.c("discarding coordinator SCADA_MGMT packet without a known session from computer ", src_addr))
                end
            elseif protocol == PROTOCOL.SCADA_CRDN then
                ---@cast packet crdn_packet
                -- coordinator packet,  should be session related, discard it
                log.debug(util.c("discarding coordinator SCADA_CRDN packet without a known session from computer ", src_addr))
            else
                log.debug(util.c("illegal packet type ", protocol, " on CRD channel"))
            end
        elseif r_chan == config.PKT_Channel then
            -- look for an associated session
            local session = svsessions.find_pdg_session(src_addr)

            if session then
                -- pass the packet onto the session handler
                session.in_queue.push_network(packet)
            elseif protocol == PROTOCOL.SCADA_MGMT then
                ---@cast packet mgmt_packet
                -- SCADA management packet
                if packet.type == MGMT_TYPE.ESTABLISH then
                    -- establish a new session: validate packet and continue
                    if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                        _establish_pdg(nic, packet, src_addr, i_seq_num, self.last_est_acks[src_addr])
                    else
                        log.debug("PDG_ESTABLISH: establish packet length mismatch")
                        _send_establish(nic, packet.scada_frame, ESTABLISH_ACK.DENY)
                    end
                else
                    -- any other packet should be session related, discard it
                    log.debug(util.c("discarding pocket SCADA_MGMT packet without a known session from computer ", src_addr))
                end
            elseif protocol == PROTOCOL.SCADA_CRDN then
                ---@cast packet crdn_packet
                -- coordinator packet, should be session related, discard it
                log.debug(util.c("discarding pocket SCADA_CRDN packet without a known session from computer ", src_addr))
            else
                log.debug(util.c("illegal packet type ", protocol, " on pocket channel"))
            end
        else
            log.debug("received packet for unknown channel " .. r_chan, true)
        end
    end

    --#endregion

    return public
end

return supervisor
