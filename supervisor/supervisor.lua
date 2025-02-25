local comms      = require("scada-common.comms")
local log        = require("scada-common.log")
local util       = require("scada-common.util")

local themes     = require("graphics.themes")

local svsessions = require("supervisor.session.svsessions")

local supervisor = {}

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE = comms.MGMT_TYPE

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
---@param nic nic network interface device
---@param fp_ok boolean if the front panel UI is running
---@param facility facility facility instance
---@diagnostic disable-next-line: unused-local
function supervisor.comms(_version, nic, fp_ok, facility)
    -- print a log message to the terminal as long as the UI isn't running
    local function println(message) if not fp_ok then util.println_ts(message) end end

    local self = {
        last_est_acks = {}
    }

    comms.set_trusted_range(config.TrustedRange)

    -- PRIVATE FUNCTIONS --

    -- configure modem channels
    nic.closeAll()
    nic.open(config.SVR_Channel)

    -- pass system data and objects to svsessions
    svsessions.init(nic, fp_ok, config, facility)

    -- send an establish request response
    ---@param packet scada_packet
    ---@param ack ESTABLISH_ACK
    ---@param data? any optional data
    local function _send_establish(packet, ack, data)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(MGMT_TYPE.ESTABLISH, { ack, data })
        s_pkt.make(packet.src_addr(), packet.seq_num() + 1, PROTOCOL.SCADA_MGMT, m_pkt.raw_sendable())

        nic.transmit(packet.remote_channel(), config.SVR_Channel, s_pkt)
        self.last_est_acks[packet.src_addr()] = ack
    end

    -- PUBLIC FUNCTIONS --

    ---@class superv_comms
    local public = {}

    -- parse a packet
    ---@nodiscard
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return modbus_frame|rplc_frame|mgmt_frame|crdn_frame|nil packet
    function public.parse_packet(side, sender, reply_to, message, distance)
        local s_pkt = nic.receive(side, sender, reply_to, message, distance)
        local pkt = nil

        if s_pkt then
            -- get as MODBUS TCP packet
            if s_pkt.protocol() == PROTOCOL.MODBUS_TCP then
                local m_pkt = comms.modbus_packet()
                if m_pkt.decode(s_pkt) then
                    pkt = m_pkt.get()
                end
            -- get as RPLC packet
            elseif s_pkt.protocol() == PROTOCOL.RPLC then
                local rplc_pkt = comms.rplc_packet()
                if rplc_pkt.decode(s_pkt) then
                    pkt = rplc_pkt.get()
                end
            -- get as SCADA management packet
            elseif s_pkt.protocol() == PROTOCOL.SCADA_MGMT then
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
    ---@param packet modbus_frame|rplc_frame|mgmt_frame|crdn_frame
    function public.handle_packet(packet)
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

            if protocol == PROTOCOL.RPLC then
                ---@cast packet rplc_frame
                -- reactor PLC packet
                if session ~= nil then
                    -- pass the packet onto the session handler
                    session.in_queue.push_packet(packet)
                else
                    -- any other packet should be session related, discard it
                    log.debug("discarding RPLC packet without a known session")
                end
            elseif protocol == PROTOCOL.SCADA_MGMT then
                ---@cast packet mgmt_frame
                -- SCADA management packet
                if session ~= nil then
                    -- pass the packet onto the session handler
                    session.in_queue.push_packet(packet)
                elseif packet.type == MGMT_TYPE.ESTABLISH then
                    -- establish a new session
                    local last_ack = self.last_est_acks[src_addr]

                    -- validate packet and continue
                    if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                        local comms_v    = packet.data[1]
                        local firmware_v = packet.data[2]
                        local dev_type   = packet.data[3]

                        if comms_v ~= comms.version then
                            if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
                                log.info(util.c("dropping PLC establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
                            end

                            _send_establish(packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
                        elseif dev_type == DEVICE_TYPE.PLC then
                            -- PLC linking request
                            if packet.length == 4 and type(packet.data[4]) == "number" then
                                local reactor_id = packet.data[4]

                                -- check ID validity
                                if reactor_id < 1 or reactor_id > config.UnitCount then
                                    -- reactor index out of range
                                    if last_ack ~= ESTABLISH_ACK.DENY then
                                        log.warning(util.c("PLC_ESTABLISH: denied assignment ", reactor_id, " outside of configured unit count ", config.UnitCount))
                                    end

                                    _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                                else
                                    -- try to establish the session
                                    local plc_id = svsessions.establish_plc_session(src_addr, i_seq_num, reactor_id, firmware_v)

                                    if plc_id == false then
                                        -- reactor already has a PLC assigned
                                        if last_ack ~= ESTABLISH_ACK.COLLISION then
                                            log.warning(util.c("PLC_ESTABLISH: assignment collision with reactor ", reactor_id))
                                        end

                                        _send_establish(packet.scada_frame, ESTABLISH_ACK.COLLISION)
                                    else
                                        -- got an ID; assigned to a reactor successfully
                                        println(util.c("PLC (", firmware_v, ") [@", src_addr, "] \xbb reactor ", reactor_id, " connected"))
                                        log.info(util.c("PLC_ESTABLISH: PLC (", firmware_v, ") [@", src_addr, "] reactor unit ", reactor_id, " PLC connected with session ID ", plc_id))
                                        _send_establish(packet.scada_frame, ESTABLISH_ACK.ALLOW)
                                    end
                                end
                            else
                                log.debug("PLC_ESTABLISH: packet length mismatch/bad parameter type")
                                _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                            end
                        else
                            log.debug(util.c("illegal establish packet for device ", dev_type, " on PLC channel"))
                            _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                        end
                    else
                        log.debug("invalid establish packet (on PLC channel)")
                        _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
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

            if protocol == PROTOCOL.MODBUS_TCP then
                ---@cast packet modbus_frame
                -- MODBUS response
                if session ~= nil then
                    -- pass the packet onto the session handler
                    session.in_queue.push_packet(packet)
                else
                    -- any other packet should be session related, discard it
                    log.debug("discarding MODBUS_TCP packet without a known session")
                end
            elseif protocol == PROTOCOL.SCADA_MGMT then
                ---@cast packet mgmt_frame
                -- SCADA management packet
                if session ~= nil then
                    -- pass the packet onto the session handler
                    session.in_queue.push_packet(packet)
                elseif packet.type == MGMT_TYPE.ESTABLISH then
                    -- establish a new session
                    local last_ack = self.last_est_acks[src_addr]

                    -- validate packet and continue
                    if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                        local comms_v    = packet.data[1]
                        local firmware_v = packet.data[2]
                        local dev_type   = packet.data[3]

                        if comms_v ~= comms.version then
                            if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
                                log.info(util.c("dropping RTU establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
                            end

                            _send_establish(packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
                        elseif dev_type == DEVICE_TYPE.RTU then
                            if packet.length == 4 then
                                -- this is an RTU advertisement for a new session
                                local rtu_advert = packet.data[4]
                                local s_id = svsessions.establish_rtu_session(src_addr, i_seq_num, rtu_advert, firmware_v)

                                println(util.c("RTU (", firmware_v, ") [@", src_addr, "] \xbb connected"))
                                log.info(util.c("RTU_ESTABLISH: RTU (",firmware_v, ") [@", src_addr, "] connected with session ID ", s_id))
                                _send_establish(packet.scada_frame, ESTABLISH_ACK.ALLOW)
                            else
                                log.debug("RTU_ESTABLISH: packet length mismatch")
                                _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                            end
                        else
                            log.debug(util.c("illegal establish packet for device ", dev_type, " on RTU channel"))
                            _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                        end
                    else
                        log.debug("invalid establish packet (on RTU channel)")
                        _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                    end
                else
                    -- any other packet should be session related, discard it
                    log.debug(util.c("discarding RTU SCADA_MGMT packet without a known session from computer ", src_addr))
                end
            else
                log.debug(util.c("illegal packet type ", protocol, " on RTU channel"))
            end
        elseif r_chan == config.CRD_Channel then
            -- look for an associated session
            local session = svsessions.find_crd_session(src_addr)

            if protocol == PROTOCOL.SCADA_MGMT then
                ---@cast packet mgmt_frame
                -- SCADA management packet
                if session ~= nil then
                    -- pass the packet onto the session handler
                    session.in_queue.push_packet(packet)
                elseif packet.type == MGMT_TYPE.ESTABLISH then
                    -- establish a new session
                    local last_ack = self.last_est_acks[src_addr]

                    -- validate packet and continue
                    if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                        local comms_v    = packet.data[1]
                        local firmware_v = packet.data[2]
                        local dev_type   = packet.data[3]

                        if comms_v ~= comms.version then
                            if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
                                log.info(util.c("dropping coordinator establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
                            end

                            _send_establish(packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
                        elseif dev_type == DEVICE_TYPE.CRD then
                            -- this is an attempt to establish a new coordinator session
                            local s_id = svsessions.establish_crd_session(src_addr, i_seq_num, firmware_v)

                            if s_id ~= false then
                                println(util.c("CRD (", firmware_v, ") [@", src_addr, "] \xbb connected"))
                                log.info(util.c("CRD_ESTABLISH: coordinator (", firmware_v, ") [@", src_addr, "] connected with session ID ", s_id))

                                _send_establish(packet.scada_frame, ESTABLISH_ACK.ALLOW, { config.UnitCount, facility.get_cooling_conf() })
                            else
                                if last_ack ~= ESTABLISH_ACK.COLLISION then
                                    log.info("CRD_ESTABLISH: denied new coordinator [@" .. src_addr .. "] due to already being connected to another coordinator")
                                end

                                _send_establish(packet.scada_frame, ESTABLISH_ACK.COLLISION)
                            end
                        else
                            log.debug(util.c("illegal establish packet for device ", dev_type, " on coordinator channel"))
                            _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                        end
                    else
                        log.debug("CRD_ESTABLISH: establish packet length mismatch")
                        _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                    end
                else
                    -- any other packet should be session related, discard it
                    log.debug(util.c("discarding coordinator SCADA_MGMT packet without a known session from computer ", src_addr))
                end
            elseif protocol == PROTOCOL.SCADA_CRDN then
                ---@cast packet crdn_frame
                -- coordinator packet
                if session ~= nil then
                    -- pass the packet onto the session handler
                    session.in_queue.push_packet(packet)
                else
                    -- any other packet should be session related, discard it
                    log.debug(util.c("discarding coordinator SCADA_CRDN packet without a known session from computer ", src_addr))
                end
            else
                log.debug(util.c("illegal packet type ", protocol, " on coordinator channel"))
            end
        elseif r_chan == config.PKT_Channel then
            -- look for an associated session
            local session = svsessions.find_pdg_session(src_addr)

            if protocol == PROTOCOL.SCADA_MGMT then
                ---@cast packet mgmt_frame
                -- SCADA management packet
                if session ~= nil then
                    -- pass the packet onto the session handler
                    session.in_queue.push_packet(packet)
                elseif packet.type == MGMT_TYPE.ESTABLISH then
                    -- establish a new session
                    local last_ack = self.last_est_acks[src_addr]

                    -- validate packet and continue
                    if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                        local comms_v    = packet.data[1]
                        local firmware_v = packet.data[2]
                        local dev_type   = packet.data[3]

                        if comms_v ~= comms.version then
                            if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
                                log.info(util.c("dropping PDG establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
                            end

                            _send_establish(packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
                        elseif dev_type == DEVICE_TYPE.PKT then
                            -- this is an attempt to establish a new pocket diagnostic session
                            local s_id = svsessions.establish_pdg_session(src_addr, i_seq_num, firmware_v)

                            println(util.c("PKT (", firmware_v, ") [@", src_addr, "] \xbb connected"))
                            log.info(util.c("PDG_ESTABLISH: pocket (", firmware_v, ") [@", src_addr, "] connected with session ID ", s_id))

                            _send_establish(packet.scada_frame, ESTABLISH_ACK.ALLOW)
                        else
                            log.debug(util.c("illegal establish packet for device ", dev_type, " on pocket channel"))
                            _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                        end
                    else
                        log.debug("PDG_ESTABLISH: establish packet length mismatch")
                        _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                    end
                else
                    -- any other packet should be session related, discard it
                    log.debug(util.c("discarding pocket SCADA_MGMT packet without a known session from computer ", src_addr))
                end
            elseif protocol == PROTOCOL.SCADA_CRDN then
                ---@cast packet crdn_frame
                -- coordinator packet
                if session ~= nil then
                    -- pass the packet onto the session handler
                    session.in_queue.push_packet(packet)
                else
                    -- any other packet should be session related, discard it
                    log.debug(util.c("discarding pocket SCADA_CRDN packet without a known session from computer ", src_addr))
                end
            else
                log.debug(util.c("illegal packet type ", protocol, " on pocket channel"))
            end
        else
            log.debug("received packet for unknown channel " .. r_chan, true)
        end
    end

    return public
end

return supervisor
