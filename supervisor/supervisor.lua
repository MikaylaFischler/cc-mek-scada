local comms      = require("scada-common.comms")
local log        = require("scada-common.log")
local util       = require("scada-common.util")

local svsessions = require("supervisor.session.svsessions")

local supervisor = {}

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local SCADA_MGMT_TYPE = comms.SCADA_MGMT_TYPE

-- supervisory controller communications
---@nodiscard
---@param _version string supervisor version
---@param num_reactors integer number of reactors
---@param cooling_conf table cooling configuration table
---@param modem table modem device
---@param channels sv_channel_list network channels
---@param range integer trusted device connection range
---@param fp_ok boolean if the front panel UI is running
---@diagnostic disable-next-line: unused-local
function supervisor.comms(_version, num_reactors, cooling_conf, modem, channels, range, fp_ok)
    -- print a log message to the terminal as long as the UI isn't running
    local function println(message) if not fp_ok then util.println_ts(message) end end

    -- channel list
    local svr_channel = channels.SVR
    local plc_channel = channels.PLC
    local rtu_channel = channels.RTU
    local crd_channel = channels.CRD
    local pkt_channel = channels.PKT

    local self = {
        last_est_acks = {}
    }

    comms.set_trusted_range(range)

    -- PRIVATE FUNCTIONS --

    -- configure modem channels
    local function _conf_channels()
        modem.closeAll()
        modem.open(svr_channel)
    end

    _conf_channels()

    -- pass modem, status, and config data to svsessions
    svsessions.init(modem, fp_ok, num_reactors, cooling_conf)

    -- send an establish request response
    ---@param packet scada_packet
    ---@param ack ESTABLISH_ACK
    ---@param data? any optional data
    local function _send_establish(packet, ack, data)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(SCADA_MGMT_TYPE.ESTABLISH, { ack, data })
        s_pkt.make(packet.src_addr(), packet.seq_num() + 1, PROTOCOL.SCADA_MGMT, m_pkt.raw_sendable())

        modem.transmit(packet.remote_channel(), svr_channel, s_pkt.raw_sendable())
        self.last_est_acks[packet.src_addr()] = ack
    end

    -- PUBLIC FUNCTIONS --

    ---@class superv_comms
    local public = {}

    -- reconnect a newly connected modem
    ---@param new_modem table
    function public.reconnect_modem(new_modem)
        modem = new_modem
        svsessions.relink_modem(new_modem)
        _conf_channels()
    end

    -- parse a packet
    ---@nodiscard
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return modbus_frame|rplc_frame|mgmt_frame|crdn_frame|nil packet
    function public.parse_packet(side, sender, reply_to, message, distance)
        local pkt = nil
        local s_pkt = comms.scada_packet()

        -- parse packet as generic SCADA packet
        s_pkt.receive(side, sender, reply_to, message, distance)

        if s_pkt.is_valid() then
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
    ---@param packet modbus_frame|rplc_frame|mgmt_frame|crdn_frame|nil
    function public.handle_packet(packet)
        if packet ~= nil then
            local l_chan = packet.scada_frame.local_channel()
            local r_chan = packet.scada_frame.remote_channel()
            local s_addr = packet.scada_frame.src_addr()
            local protocol = packet.scada_frame.protocol()

            if l_chan ~= svr_channel then
                log.debug("received packet on unconfigured channel " .. l_chan, true)
                return
            end

            if r_chan == plc_channel then
                -- look for an associated session
                local session = svsessions.find_plc_session(s_addr)

                if protocol == PROTOCOL.RPLC then
                    ---@cast packet rplc_frame
                    -- reactor PLC packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    else
                        -- unknown session, force a re-link
                        log.debug("PLC_ESTABLISH: no session but not an establish, forcing relink")
                        _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                    end
                elseif protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_frame
                    -- SCADA management packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    elseif packet.type == SCADA_MGMT_TYPE.ESTABLISH then
                        -- establish a new session
                        local last_ack = self.last_est_acks[s_addr]

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
                                    local plc_id = svsessions.establish_plc_session(l_chan, r_chan, reactor_id, firmware_v)

                                    if plc_id == false then
                                        -- reactor already has a PLC assigned
                                        if last_ack ~= ESTABLISH_ACK.COLLISION then
                                            log.warning(util.c("PLC_ESTABLISH: assignment collision with reactor ", reactor_id))
                                        end

                                        _send_establish(packet.scada_frame, ESTABLISH_ACK.COLLISION)
                                    else
                                        -- got an ID; assigned to a reactor successfully
                                        println(util.c("PLC (", firmware_v, ") [:", r_chan, "] \xbb reactor ", reactor_id, " connected"))
                                        log.info(util.c("PLC_ESTABLISH: PLC (", firmware_v, ") [:", r_chan, "] reactor unit ", reactor_id, " PLC connected with session ID ", plc_id))
                                        _send_establish(packet.scada_frame, ESTABLISH_ACK.ALLOW)
                                    end
                                else
                                    log.debug("PLC_ESTABLISH: packet length mismatch/bad parameter type")
                                    _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                                end
                            else
                                log.debug(util.c("illegal establish packet for device ", dev_type, " on PLC listening channel"))
                                _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                            end
                        else
                            log.debug("invalid establish packet (on PLC listening channel)")
                            _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                        end
                    else
                        -- any other packet should be session related, discard it
                        log.debug(util.c(r_chan, " -> ", l_chan, ": discarding SCADA_MGMT packet without a known session"))
                    end
                end
            elseif r_chan == rtu_channel then
                -- look for an associated session
                local session = svsessions.find_rtu_session(s_addr)

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
                    elseif packet.type == SCADA_MGMT_TYPE.ESTABLISH then
                        -- establish a new session
                        local last_ack = self.last_est_acks[s_addr]

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
                                    local s_id = svsessions.establish_rtu_session(l_chan, r_chan, rtu_advert, firmware_v)

                                    println(util.c("RTU (", firmware_v, ") [:", r_chan, "] \xbb connected"))
                                    log.info(util.c("RTU_ESTABLISH: RTU (",firmware_v, ") [:", r_chan, "] connected with session ID ", s_id))
                                    _send_establish(packet.scada_frame, ESTABLISH_ACK.ALLOW)
                                else
                                    log.debug("RTU_ESTABLISH: packet length mismatch")
                                    _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                                end
                            else
                                log.debug(util.c("illegal establish packet for device ", dev_type, " on RTU listening channel"))
                                _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                            end
                        else
                            log.debug("invalid establish packet (on RTU listening channel)")
                            _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                        end
                    else
                        -- any other packet should be session related, discard it
                        log.debug(util.c(r_chan, " -> ", l_chan, ": discarding SCADA_MGMT packet without a known session"))
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " on RTU listening channel")
                end
            elseif r_chan == crd_channel then
                -- look for an associated session
                local session = svsessions.find_svctl_session(s_addr)

                if protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_frame
                    -- SCADA management packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    elseif packet.type == SCADA_MGMT_TYPE.ESTABLISH then
                        -- establish a new session
                        local last_ack = self.last_est_acks[s_addr]

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
                            elseif dev_type == DEVICE_TYPE.CRDN then
                                -- this is an attempt to establish a new coordinator session
                                local s_id = svsessions.establish_coord_session(l_chan, r_chan, firmware_v)

                                if s_id ~= false then
                                    local config = { num_reactors }
                                    for i = 1, #cooling_conf do
                                        table.insert(config, cooling_conf[i].BOILERS)
                                        table.insert(config, cooling_conf[i].TURBINES)
                                    end

                                    println(util.c("CRD (", firmware_v, ") [@", s_addr, "] \xbb connected"))
                                    log.info(util.c("ESTABLISH: coordinator (", firmware_v, ") [@", s_addr, "] connected with session ID ", s_id))

                                    _send_establish(packet.scada_frame, ESTABLISH_ACK.ALLOW, config)
                                else
                                    if last_ack ~= ESTABLISH_ACK.COLLISION then
                                        log.info("ESTABLISH: denied new coordinator [@" .. s_addr .. "] due to already being connected to another coordinator")
                                    end

                                    _send_establish(packet.scada_frame, ESTABLISH_ACK.COLLISION)
                                end
                            elseif dev_type == DEVICE_TYPE.PKT then
                                -- this is an attempt to establish a new pocket diagnostic session
                                local s_id = svsessions.establish_pdg_session(l_chan, r_chan, firmware_v)

                                println(util.c("PKT (", firmware_v, ") [:", r_chan, "] \xbb connected"))
                                log.info(util.c("SVCTL_ESTABLISH: pocket (", firmware_v, ") [:", r_chan, "] connected with session ID ", s_id))

                                _send_establish(packet.scada_frame, ESTABLISH_ACK.ALLOW)
                            else
                                log.debug(util.c("illegal establish packet for device ", dev_type, " on SVCTL listening channel"))
                                _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                            end
                        else
                            log.debug("SVCTL_ESTABLISH: establish packet length mismatch")
                            _send_establish(packet.scada_frame, ESTABLISH_ACK.DENY)
                        end
                    else
                        -- any other packet should be session related, discard it
                        log.debug(r_chan .. " -> " .. l_chan .. ": discarding SCADA_MGMT packet without a known session")
                    end
                elseif protocol == PROTOCOL.SCADA_CRDN then
                    ---@cast packet crdn_frame
                    -- coordinator packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    else
                        -- any other packet should be session related, discard it
                        log.debug(r_chan .. "->" .. l_chan .. ": discarding SCADA_CRDN packet without a known session")
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " on coordinator listening channel")
                end
            elseif r_chan == pkt_channel then
                
            else
                log.debug("received packet for unknown channel " .. r_chan, true)
            end
        end
    end

    return public
end

return supervisor
