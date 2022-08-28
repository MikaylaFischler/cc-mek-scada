local comms      = require("scada-common.comms")
local log        = require("scada-common.log")
local util       = require("scada-common.util")

local svsessions = require("supervisor.session.svsessions")

local supervisor = {}

local PROTOCOLS = comms.PROTOCOLS
local RPLC_TYPES = comms.RPLC_TYPES
local RPLC_LINKING = comms.RPLC_LINKING
local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES
local SCADA_CRDN_TYPES = comms.SCADA_CRDN_TYPES

local SESSION_TYPE = svsessions.SESSION_TYPE

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

-- supervisory controller communications
---@param version string
---@param num_reactors integer
---@param cooling_conf table
---@param modem table
---@param dev_listen integer
---@param coord_listen integer
function supervisor.comms(version, num_reactors, cooling_conf, modem, dev_listen, coord_listen)
    local self = {
        version = version,
        num_reactors = num_reactors,
        modem = modem,
        dev_listen = dev_listen,
        coord_listen = coord_listen,
        reactor_struct_cache = nil
    }

    ---@class superv_comms
    local public = {}

    -- PRIVATE FUNCTIONS --

    -- open all channels
    local function _open_channels()
        if not self.modem.isOpen(self.dev_listen) then
            self.modem.open(self.dev_listen)
        end

        if not self.modem.isOpen(self.coord_listen) then
            self.modem.open(self.coord_listen)
        end
    end

    -- open at construct time
    _open_channels()

    -- link modem to svsessions
    svsessions.init(self.modem, num_reactors, cooling_conf)

    -- send PLC link request response
    ---@param dest integer
    ---@param msg table
    local function _send_plc_linking(seq_id, dest, msg)
        local s_pkt = comms.scada_packet()
        local r_pkt = comms.rplc_packet()

        r_pkt.make(0, RPLC_TYPES.LINK_REQ, msg)
        s_pkt.make(seq_id, PROTOCOLS.RPLC, r_pkt.raw_sendable())

        self.modem.transmit(dest, self.dev_listen, s_pkt.raw_sendable())
    end

    -- send RTU advertisement response
    ---@param seq_id integer
    ---@param dest integer
    local function _send_remote_linked(seq_id, dest)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(SCADA_MGMT_TYPES.REMOTE_LINKED, {})
        s_pkt.make(seq_id, PROTOCOLS.SCADA_MGMT, m_pkt.raw_sendable())

        self.modem.transmit(dest, self.dev_listen, s_pkt.raw_sendable())
    end

    -- send coordinator connection establish response
    ---@param seq_id integer
    ---@param dest integer
    local function _send_crdn_establish(seq_id, dest)
        local s_pkt = comms.scada_packet()
        local c_pkt = comms.crdn_packet()

        local config = { self.num_reactors }

        for i = 1, #cooling_conf do
            table.insert(config, cooling_conf[i].BOILERS)
            table.insert(config, cooling_conf[i].TURBINES)
        end

        c_pkt.make(SCADA_CRDN_TYPES.ESTABLISH, config)
        s_pkt.make(seq_id, PROTOCOLS.SCADA_CRDN, c_pkt.raw_sendable())

        self.modem.transmit(dest, self.coord_listen, s_pkt.raw_sendable())
    end

    -- PUBLIC FUNCTIONS --

    -- reconnect a newly connected modem
    ---@param modem table
---@diagnostic disable-next-line: redefined-local
    function public.reconnect_modem(modem)
        self.modem = modem
        svsessions.relink_modem(self.modem)
        _open_channels()
    end

    -- parse a packet
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
            if s_pkt.protocol() == PROTOCOLS.MODBUS_TCP then
                local m_pkt = comms.modbus_packet()
                if m_pkt.decode(s_pkt) then
                    pkt = m_pkt.get()
                end
            -- get as RPLC packet
            elseif s_pkt.protocol() == PROTOCOLS.RPLC then
                local rplc_pkt = comms.rplc_packet()
                if rplc_pkt.decode(s_pkt) then
                    pkt = rplc_pkt.get()
                end
            -- get as SCADA management packet
            elseif s_pkt.protocol() == PROTOCOLS.SCADA_MGMT then
                local mgmt_pkt = comms.mgmt_packet()
                if mgmt_pkt.decode(s_pkt) then
                    pkt = mgmt_pkt.get()
                end
            -- get as coordinator packet
            elseif s_pkt.protocol() == PROTOCOLS.SCADA_CRDN then
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
        if packet ~= nil then
            local l_port = packet.scada_frame.local_port()
            local r_port = packet.scada_frame.remote_port()
            local protocol = packet.scada_frame.protocol()

            -- device (RTU/PLC) listening channel
            if l_port == self.dev_listen then
                if protocol == PROTOCOLS.MODBUS_TCP then
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
                elseif protocol == PROTOCOLS.RPLC then
                    -- look for an associated session
                    local session = svsessions.find_plc_session(r_port)

                    -- reactor PLC packet
                    if session ~= nil then
                        if packet.type == RPLC_TYPES.LINK_REQ then
                            -- new device on this port? that's a collision
                            log.debug("PLC_LNK: request from existing connection received on " .. r_port .. ", responding with collision")
                            _send_plc_linking(packet.scada_frame.seq_num() + 1, r_port, { RPLC_LINKING.COLLISION })
                        else
                            -- pass the packet onto the session handler
                            session.in_queue.push_packet(packet)
                        end
                    else
                        local next_seq_id = packet.scada_frame.seq_num() + 1

                        -- unknown session, is this a linking request?
                        if packet.type == RPLC_TYPES.LINK_REQ then
                            if packet.length == 2 then
                                -- this is a linking request
                                local plc_id = svsessions.establish_plc_session(l_port, r_port, packet.data[1], packet.data[2])
                                if plc_id == false then
                                    -- reactor already has a PLC assigned
                                    log.debug(util.c("PLC_LNK: assignment collision with reactor ", packet.data[1]))
                                    _send_plc_linking(next_seq_id, r_port, { RPLC_LINKING.COLLISION })
                                else
                                    -- got an ID; assigned to a reactor successfully
                                    println(util.c("connected to reactor ", packet.data[1], " PLC (", packet.data[2], ") [:", r_port, "]"))
                                    log.debug("PLC_LNK: allowed for device at " .. r_port)
                                    _send_plc_linking(next_seq_id, r_port, { RPLC_LINKING.ALLOW })
                                end
                            else
                                log.debug("PLC_LNK: new linking packet length mismatch")
                            end
                        else
                            -- force a re-link
                            log.debug("PLC_LNK: no session but not a link, force relink")
                            _send_plc_linking(next_seq_id, r_port, { RPLC_LINKING.DENY })
                        end
                    end
                elseif protocol == PROTOCOLS.SCADA_MGMT then
                    -- look for an associated session
                    local session = svsessions.find_device_session(r_port)

                    -- SCADA management packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    elseif packet.type == SCADA_MGMT_TYPES.RTU_ADVERT then
                        if packet.length >= 1 then
                            -- this is an RTU advertisement for a new session
                            println(util.c("connected to RTU (", packet.data[1], ") [:", r_port, "]"))

                            svsessions.establish_rtu_session(l_port, r_port, packet.data)

                            log.debug("RTU_ADVERT: linked " .. r_port)
                            _send_remote_linked(packet.scada_frame.seq_num() + 1, r_port)
                        else
                            log.debug("RTU_ADVERT: advertisement packet empty")
                        end
                    else
                        -- any other packet should be session related, discard it
                        log.debug(util.c(r_port, "->", l_port, ": discarding SCADA_MGMT packet without a known session"))
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " on device listening channel")
                end
            -- coordinator listening channel
            elseif l_port == self.coord_listen then
                -- look for an associated session
                local session = svsessions.find_coord_session(r_port)

                if protocol == PROTOCOLS.SCADA_MGMT then
                    -- SCADA management packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    else
                        -- any other packet should be session related, discard it
                        log.debug(util.c(r_port, "->", l_port, ": discarding SCADA_MGMT packet without a known session"))
                    end
                elseif protocol == PROTOCOLS.SCADA_CRDN then
                    -- coordinator packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    elseif packet.type == SCADA_CRDN_TYPES.ESTABLISH then
                        if packet.length == 1 then
                            -- this is an attempt to establish a new session
                            println(util.c("connected to coordinator [:", r_port, "]"))

                            svsessions.establish_coord_session(l_port, r_port, packet.data[1])

                            log.debug("CRDN_ESTABLISH: connected to " .. r_port)
                            _send_crdn_establish(packet.scada_frame.seq_num() + 1, r_port)
                        else
                            log.debug("CRDN_ESTABLISH: establish packet length mismatch")
                        end
                    else
                        -- any other packet should be session related, discard it
                        log.debug(util.c(r_port, "->", l_port, ": discarding SCADA_CRDN packet without a known session"))
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " on coordinator listening channel")
                end
            else
                log.warning("received packet on unused channel " .. l_port)
            end
        end
    end

    return public
end

return supervisor
