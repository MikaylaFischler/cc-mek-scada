local comms      = require("scada-common.comms")
local log        = require("scada-common.log")
local util       = require("scada-common.util")

local svsessions = require("supervisor.session.svsessions")

local supervisor = {}

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local SCADA_MGMT_TYPE = comms.SCADA_MGMT_TYPE

local println = util.println

-- supervisory controller communications
---@nodiscard
---@param version string supervisor version
---@param num_reactors integer number of reactors
---@param cooling_conf table cooling configuration table
---@param modem table modem device
---@param dev_listen integer listening port for PLC/RTU devices
---@param coord_listen integer listening port for coordinator
---@param range integer trusted device connection range
---@diagnostic disable-next-line: unused-local
function supervisor.comms(version, num_reactors, cooling_conf, modem, dev_listen, coord_listen, range)
    local self = {
        last_est_acks = {}
    }

    comms.set_trusted_range(range)

    -- PRIVATE FUNCTIONS --

    -- configure modem channels
    local function _conf_channels()
        modem.closeAll()
        modem.open(dev_listen)
        modem.open(coord_listen)
    end

    _conf_channels()

    -- link modem to svsessions
    svsessions.init(modem, num_reactors, cooling_conf)

    -- send an establish request response to a PLC/RTU
    ---@param dest integer
    ---@param msg table
    local function _send_dev_establish(seq_id, dest, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(SCADA_MGMT_TYPE.ESTABLISH, msg)
        s_pkt.make(seq_id, PROTOCOL.SCADA_MGMT, m_pkt.raw_sendable())

        modem.transmit(dest, dev_listen, s_pkt.raw_sendable())
    end

    -- send coordinator connection establish response
    ---@param seq_id integer
    ---@param dest integer
    ---@param msg table
    local function _send_crdn_establish(seq_id, dest, msg)
        local s_pkt = comms.scada_packet()
        local c_pkt = comms.mgmt_packet()

        c_pkt.make(SCADA_MGMT_TYPE.ESTABLISH, msg)
        s_pkt.make(seq_id, PROTOCOL.SCADA_MGMT, c_pkt.raw_sendable())

        modem.transmit(dest, coord_listen, s_pkt.raw_sendable())
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
            local l_port = packet.scada_frame.local_port()
            local r_port = packet.scada_frame.remote_port()
            local protocol = packet.scada_frame.protocol()

            -- device (RTU/PLC) listening channel
            if l_port == dev_listen then
                if protocol == PROTOCOL.MODBUS_TCP then
                    ---@cast packet modbus_frame
                    -- look for an associated session
                    local session = svsessions.find_rtu_session(r_port)

                    -- MODBUS response
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    else
                        -- any other packet should be session related, discard it
                        log.debug("discarding MODBUS_TCP packet without a known session")
                    end
                elseif protocol == PROTOCOL.RPLC then
                    ---@cast packet rplc_frame
                    -- look for an associated session
                    local session = svsessions.find_plc_session(r_port)

                    -- reactor PLC packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    else
                        -- unknown session, force a re-link
                        log.debug("PLC_ESTABLISH: no session but not an establish, forcing relink")
                        _send_dev_establish(packet.scada_frame.seq_num() + 1, r_port, { ESTABLISH_ACK.DENY })
                    end
                elseif protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_frame
                    -- look for an associated session
                    local session = svsessions.find_device_session(r_port)

                    -- SCADA management packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    elseif packet.type == SCADA_MGMT_TYPE.ESTABLISH then
                        -- establish a new session
                        local next_seq_id = packet.scada_frame.seq_num() + 1

                        -- validate packet and continue
                        if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                            local comms_v = packet.data[1]
                            local firmware_v = packet.data[2]
                            local dev_type = packet.data[3]

                            if comms_v ~= comms.version then
                                if self.last_est_acks[r_port] ~= ESTABLISH_ACK.BAD_VERSION then
                                    log.info(util.c("dropping device establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
                                    self.last_est_acks[r_port] = ESTABLISH_ACK.BAD_VERSION
                                end

                                _send_dev_establish(next_seq_id, r_port, { ESTABLISH_ACK.BAD_VERSION })
                            elseif dev_type == DEVICE_TYPE.PLC then
                                -- PLC linking request
                                if packet.length == 4 and type(packet.data[4]) == "number" then
                                    local reactor_id = packet.data[4]
                                    local plc_id = svsessions.establish_plc_session(l_port, r_port, reactor_id, firmware_v)

                                    if plc_id == false then
                                        -- reactor already has a PLC assigned
                                        if self.last_est_acks[r_port] ~= ESTABLISH_ACK.COLLISION then
                                            log.warning(util.c("PLC_ESTABLISH: assignment collision with reactor ", reactor_id))
                                            self.last_est_acks[r_port] = ESTABLISH_ACK.COLLISION
                                        end

                                        _send_dev_establish(next_seq_id, r_port, { ESTABLISH_ACK.COLLISION })
                                    else
                                        -- got an ID; assigned to a reactor successfully
                                        println(util.c("PLC (", firmware_v, ") [:", r_port, "] \xbb reactor ", reactor_id, " connected"))
                                        log.info(util.c("PLC_ESTABLISH: PLC (", firmware_v, ") [:", r_port, "] reactor unit ", reactor_id, " PLC connected with session ID ", plc_id))

                                        _send_dev_establish(next_seq_id, r_port, { ESTABLISH_ACK.ALLOW })
                                        self.last_est_acks[r_port] = ESTABLISH_ACK.ALLOW
                                    end
                                else
                                    log.debug("PLC_ESTABLISH: packet length mismatch/bad parameter type")
                                    _send_dev_establish(next_seq_id, r_port, { ESTABLISH_ACK.DENY })
                                end
                            elseif dev_type == DEVICE_TYPE.RTU then
                                if packet.length == 4 then
                                    -- this is an RTU advertisement for a new session
                                    local rtu_advert = packet.data[4]
                                    local s_id = svsessions.establish_rtu_session(l_port, r_port, rtu_advert, firmware_v)

                                    println(util.c("RTU (", firmware_v, ") [:", r_port, "] \xbb connected"))
                                    log.info(util.c("RTU_ESTABLISH: RTU (",firmware_v, ") [:", r_port, "] connected with session ID ", s_id))

                                    _send_dev_establish(next_seq_id, r_port, { ESTABLISH_ACK.ALLOW })
                                else
                                    log.debug("RTU_ESTABLISH: packet length mismatch")
                                    _send_dev_establish(next_seq_id, r_port, { ESTABLISH_ACK.DENY })
                                end
                            else
                                log.debug(util.c("illegal establish packet for device ", dev_type, " on PLC/RTU listening channel"))
                                _send_dev_establish(next_seq_id, r_port, { ESTABLISH_ACK.DENY })
                            end
                        else
                            log.debug("invalid establish packet (on PLC/RTU listening channel)")
                            _send_dev_establish(next_seq_id, r_port, { ESTABLISH_ACK.DENY })
                        end
                    else
                        -- any other packet should be session related, discard it
                        log.debug(util.c(r_port, "->", l_port, ": discarding SCADA_MGMT packet without a known session"))
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " on device listening channel")
                end
            -- coordinator listening channel
            elseif l_port == coord_listen then
                -- look for an associated session
                local session = svsessions.find_coord_session(r_port)

                if protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_frame
                    -- SCADA management packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    elseif packet.type == SCADA_MGMT_TYPE.ESTABLISH then
                        -- establish a new session
                        local next_seq_id = packet.scada_frame.seq_num() + 1

                        -- validate packet and continue
                        if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                            local comms_v = packet.data[1]
                            local firmware_v = packet.data[2]
                            local dev_type = packet.data[3]

                            if comms_v ~= comms.version then
                                if self.last_est_acks[r_port] ~= ESTABLISH_ACK.BAD_VERSION then
                                    log.info(util.c("dropping coordinator establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
                                    self.last_est_acks[r_port] = ESTABLISH_ACK.BAD_VERSION
                                end

                                _send_crdn_establish(next_seq_id, r_port, { ESTABLISH_ACK.BAD_VERSION })
                            elseif dev_type ~= DEVICE_TYPE.CRDN then
                                log.debug(util.c("illegal establish packet for device ", dev_type, " on CRDN listening channel"))
                                _send_crdn_establish(next_seq_id, r_port, { ESTABLISH_ACK.DENY })
                            else
                                -- this is an attempt to establish a new session
                                local s_id = svsessions.establish_coord_session(l_port, r_port, firmware_v)

                                if s_id ~= false then
                                    local config = { num_reactors }
                                    for i = 1, #cooling_conf do
                                        table.insert(config, cooling_conf[i].BOILERS)
                                        table.insert(config, cooling_conf[i].TURBINES)
                                    end

                                    println(util.c("CRD (",firmware_v, ") [:", r_port, "] \xbb connected"))
                                    log.info(util.c("CRDN_ESTABLISH: coordinator (",firmware_v, ") [:", r_port, "] connected with session ID ", s_id))

                                    _send_crdn_establish(next_seq_id, r_port, { ESTABLISH_ACK.ALLOW, config })
                                    self.last_est_acks[r_port] = ESTABLISH_ACK.ALLOW
                                else
                                    if self.last_est_acks[r_port] ~= ESTABLISH_ACK.COLLISION then
                                        log.info("CRDN_ESTABLISH: denied new coordinator due to already being connected to another coordinator")
                                        self.last_est_acks[r_port] = ESTABLISH_ACK.COLLISION
                                    end

                                    _send_crdn_establish(next_seq_id, r_port, { ESTABLISH_ACK.COLLISION })
                                end
                            end
                        else
                            log.debug("CRDN_ESTABLISH: establish packet length mismatch")
                            _send_crdn_establish(next_seq_id, r_port, { ESTABLISH_ACK.DENY })
                        end
                    else
                        -- any other packet should be session related, discard it
                        log.debug(r_port .. "->" .. l_port .. ": discarding SCADA_MGMT packet without a known session")
                    end
                elseif protocol == PROTOCOL.SCADA_CRDN then
                    ---@cast packet crdn_frame
                    -- coordinator packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    else
                        -- any other packet should be session related, discard it
                        log.debug(r_port .. "->" .. l_port .. ": discarding SCADA_CRDN packet without a known session")
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " on coordinator listening channel")
                end
            else
                log.warning("received packet on unconfigured channel " .. l_port)
            end
        end
    end

    return public
end

return supervisor
