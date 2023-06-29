local comms  = require("scada-common.comms")
local log    = require("scada-common.log")
local util   = require("scada-common.util")

local coreio = require("pocket.coreio")

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local SCADA_MGMT_TYPE = comms.SCADA_MGMT_TYPE
-- local CAPI_TYPE = comms.CAPI_TYPE

local LINK_STATE = coreio.LINK_STATE

local pocket = {}

-- pocket coordinator + supervisor communications
---@nodiscard
---@param version string pocket version
---@param nic nic network interface device
---@param pkt_channel integer pocket comms channel
---@param svr_channel integer supervisor access channel
---@param crd_channel integer coordinator access channel
---@param range integer trusted device connection range
---@param sv_watchdog watchdog
---@param api_watchdog watchdog
function pocket.comms(version, nic, pkt_channel, svr_channel, crd_channel, range, sv_watchdog, api_watchdog)
    local self = {
        sv = {
            linked = false,
            addr = comms.BROADCAST,
            seq_num = 0,
            r_seq_num = nil,    ---@type nil|integer
            last_est_ack = ESTABLISH_ACK.ALLOW
        },
        api = {
            linked = false,
            addr = comms.BROADCAST,
            seq_num = 0,
            r_seq_num = nil,    ---@type nil|integer
            last_est_ack = ESTABLISH_ACK.ALLOW
        },
        establish_delay_counter = 0
    }

    comms.set_trusted_range(range)

    -- PRIVATE FUNCTIONS --

    -- configure network channels
    nic.closeAll()
    nic.open(pkt_channel)

    -- send a management packet to the supervisor
    ---@param msg_type SCADA_MGMT_TYPE
    ---@param msg table
    local function _send_sv(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local pkt = comms.mgmt_packet()

        pkt.make(msg_type, msg)
        s_pkt.make(self.sv.addr, self.sv.seq_num, PROTOCOL.SCADA_MGMT, pkt.raw_sendable())

        nic.transmit(svr_channel, pkt_channel, s_pkt)
        self.sv.seq_num = self.sv.seq_num + 1
    end

    -- send a management packet to the coordinator
    ---@param msg_type SCADA_MGMT_TYPE
    ---@param msg table
    local function _send_crd(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local pkt = comms.mgmt_packet()

        pkt.make(msg_type, msg)
        s_pkt.make(self.api.addr, self.api.seq_num, PROTOCOL.SCADA_MGMT, pkt.raw_sendable())

        nic.transmit(crd_channel, pkt_channel, s_pkt)
        self.api.seq_num = self.api.seq_num + 1
    end

    -- send a packet to the coordinator API
    -----@param msg_type CAPI_TYPE
    -----@param msg table
    -- local function _send_api(msg_type, msg)
    --     local s_pkt = comms.scada_packet()
    --     local pkt = comms.capi_packet()

    --     pkt.make(msg_type, msg)
    --     s_pkt.make(self.api.addr, self.api.seq_num, PROTOCOL.COORD_API, pkt.raw_sendable())

    --     nic.transmit(crd_channel, pkt_channel, s_pkt)
    --     self.api.seq_num = self.api.seq_num + 1
    -- end

    -- attempt supervisor connection establishment
    local function _send_sv_establish()
        _send_sv(SCADA_MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.PKT })
    end

    -- attempt coordinator API connection establishment
    local function _send_api_establish()
        _send_crd(SCADA_MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.PKT })
    end

    -- keep alive ack to supervisor
    ---@param srv_time integer
    local function _send_sv_keep_alive_ack(srv_time)
        _send_sv(SCADA_MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- keep alive ack to coordinator
    ---@param srv_time integer
    local function _send_api_keep_alive_ack(srv_time)
        _send_crd(SCADA_MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- PUBLIC FUNCTIONS --

    ---@class pocket_comms
    local public = {}

    -- close connection to the supervisor
    function public.close_sv()
        sv_watchdog.cancel()
        self.sv.linked = false
        self.sv.r_seq_num = nil
        self.sv.addr = comms.BROADCAST
        _send_sv(SCADA_MGMT_TYPE.CLOSE, {})
    end

    -- close connection to coordinator API server
    function public.close_api()
        api_watchdog.cancel()
        self.api.linked = false
        self.api.r_seq_num = nil
        self.api.addr = comms.BROADCAST
        _send_crd(SCADA_MGMT_TYPE.CLOSE, {})
    end

    -- close the connections to the servers
    function public.close()
        public.close_sv()
        public.close_api()
    end

    -- attempt to re-link if any of the dependent links aren't active
    function public.link_update()
        if not self.sv.linked then
            coreio.report_link_state(util.trinary(self.api.linked, LINK_STATE.API_LINK_ONLY, LINK_STATE.UNLINKED))

            if self.establish_delay_counter <= 0 then
                _send_sv_establish()
                self.establish_delay_counter = 4
            else
                self.establish_delay_counter = self.establish_delay_counter - 1
            end
        elseif not self.api.linked then
            coreio.report_link_state(LINK_STATE.SV_LINK_ONLY)

            if self.establish_delay_counter <= 0 then
                _send_api_establish()
                self.establish_delay_counter = 4
            else
                self.establish_delay_counter = self.establish_delay_counter - 1
            end
        else
            -- linked, all good!
            coreio.report_link_state(LINK_STATE.LINKED)
        end
    end

    -- parse a packet
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return mgmt_frame|capi_frame|nil packet
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
            -- get as coordinator API packet
            elseif s_pkt.protocol() == PROTOCOL.COORD_API then
                local capi_pkt = comms.capi_packet()
                if capi_pkt.decode(s_pkt) then
                    pkt = capi_pkt.get()
                end
            else
                log.debug("attempted parse of illegal packet type " .. s_pkt.protocol(), true)
            end
        end

        return pkt
    end

    -- handle a packet
    ---@param packet mgmt_frame|capi_frame|nil
    function public.handle_packet(packet)
        if packet ~= nil then
            local l_chan   = packet.scada_frame.local_channel()
            local r_chan   = packet.scada_frame.remote_channel()
            local protocol = packet.scada_frame.protocol()
            local src_addr = packet.scada_frame.src_addr()

            if l_chan ~= pkt_channel then
                log.debug("received packet on unconfigured channel " .. l_chan, true)
            elseif r_chan == crd_channel then
                -- check sequence number
                if self.api.r_seq_num == nil then
                    self.api.r_seq_num = packet.scada_frame.seq_num()
                elseif self.connected and ((self.api.r_seq_num + 1) ~= packet.scada_frame.seq_num()) then
                    log.warning("sequence out-of-order (API): last = " .. self.api.r_seq_num .. ", new = " .. packet.scada_frame.seq_num())
                    return
                elseif self.api.linked and (src_addr ~= self.api.addr) then
                    log.debug("received packet from unknown computer " .. src_addr .. " while linked (API expected " .. self.api.addr ..
                                "); channel in use by another system?")
                    return
                else
                    self.api.r_seq_num = packet.scada_frame.seq_num()
                end

                -- feed watchdog on valid sequence number
                api_watchdog.feed()

                if protocol == PROTOCOL.COORD_API then
                    ---@cast packet capi_frame
                elseif protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_frame
                    if packet.type == SCADA_MGMT_TYPE.ESTABLISH then
                        -- connection with coordinator established
                        if packet.length == 1 then
                            local est_ack = packet.data[1]

                            if est_ack == ESTABLISH_ACK.ALLOW then
                                log.info("coordinator connection established")
                                self.establish_delay_counter = 0
                                self.api.linked = true
                                self.api.addr = src_addr

                                if self.sv.linked then
                                    coreio.report_link_state(LINK_STATE.LINKED)
                                else
                                    coreio.report_link_state(LINK_STATE.API_LINK_ONLY)
                                end
                            elseif est_ack == ESTABLISH_ACK.DENY then
                                if self.api.last_est_ack ~= est_ack then
                                    log.info("coordinator connection denied")
                                end
                            elseif est_ack == ESTABLISH_ACK.COLLISION then
                                if self.api.last_est_ack ~= est_ack then
                                    log.info("coordinator connection denied due to collision")
                                end
                            elseif est_ack == ESTABLISH_ACK.BAD_VERSION then
                                if self.api.last_est_ack ~= est_ack then
                                    log.info("coordinator comms version mismatch")
                                end
                            else
                                log.debug("coordinator SCADA_MGMT establish packet reply unsupported")
                            end

                            self.api.last_est_ack = est_ack
                        else
                            log.debug("coordinator SCADA_MGMT establish packet length mismatch")
                        end
                    elseif self.api.linked then
                        if packet.type == SCADA_MGMT_TYPE.KEEP_ALIVE then
                            -- keep alive request received, echo back
                            if packet.length == 1 then
                                local timestamp = packet.data[1]
                                local trip_time = util.time() - timestamp

                                if trip_time > 750 then
                                    log.warning("pocket coordinator KEEP_ALIVE trip time > 750ms (" .. trip_time .. "ms)")
                                end

                                -- log.debug("pocket coordinator RTT = " .. trip_time .. "ms")

                                _send_api_keep_alive_ack(timestamp)
                            else
                                log.debug("coordinator SCADA keep alive packet length mismatch")
                            end
                        elseif packet.type == SCADA_MGMT_TYPE.CLOSE then
                            -- handle session close
                            api_watchdog.cancel()
                            self.api.linked = false
                            self.api.r_seq_num = nil
                            self.api.addr = comms.BROADCAST
                            log.info("coordinator server connection closed by remote host")
                        else
                            log.debug("received unknown SCADA_MGMT packet type " .. packet.type .. " from coordinator")
                        end
                    else
                        log.debug("discarding coordinator non-link SCADA_MGMT packet before linked")
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " from coordinator", true)
                end
            elseif r_chan == svr_channel then
                -- check sequence number
                if self.sv.r_seq_num == nil then
                    self.sv.r_seq_num = packet.scada_frame.seq_num()
                elseif self.connected and ((self.sv.r_seq_num + 1) ~= packet.scada_frame.seq_num()) then
                    log.warning("sequence out-of-order (SVR): last = " .. self.sv.r_seq_num .. ", new = " .. packet.scada_frame.seq_num())
                    return
                elseif self.sv.linked and (src_addr ~= self.sv.addr) then
                    log.debug("received packet from unknown computer " .. src_addr .. " while linked (SVR expected " .. self.sv.addr ..
                                "); channel in use by another system?")
                    return
                else
                    self.sv.r_seq_num = packet.scada_frame.seq_num()
                end

                -- feed watchdog on valid sequence number
                sv_watchdog.feed()

                -- handle packet
                if protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_frame
                    if packet.type == SCADA_MGMT_TYPE.ESTABLISH then
                        -- connection with supervisor established
                        if packet.length == 1 then
                            local est_ack = packet.data[1]

                            if est_ack == ESTABLISH_ACK.ALLOW then
                                log.info("supervisor connection established")
                                self.establish_delay_counter = 0
                                self.sv.linked = true
                                self.sv.addr = src_addr

                                if self.api.linked then
                                    coreio.report_link_state(LINK_STATE.LINKED)
                                else
                                    coreio.report_link_state(LINK_STATE.SV_LINK_ONLY)
                                end
                            elseif est_ack == ESTABLISH_ACK.DENY then
                                if self.sv.last_est_ack ~= est_ack then
                                    log.info("supervisor connection denied")
                                end
                            elseif est_ack == ESTABLISH_ACK.COLLISION then
                                if self.sv.last_est_ack ~= est_ack then
                                    log.info("supervisor connection denied due to collision")
                                end
                            elseif est_ack == ESTABLISH_ACK.BAD_VERSION then
                                if self.sv.last_est_ack ~= est_ack then
                                    log.info("supervisor comms version mismatch")
                                end
                            else
                                log.debug("supervisor SCADA_MGMT establish packet reply unsupported")
                            end

                            self.sv.last_est_ack = est_ack
                        else
                            log.debug("supervisor SCADA_MGMT establish packet length mismatch")
                        end
                    elseif self.sv.linked then
                        if packet.type == SCADA_MGMT_TYPE.KEEP_ALIVE then
                            -- keep alive request received, echo back
                            if packet.length == 1 then
                                local timestamp = packet.data[1]
                                local trip_time = util.time() - timestamp

                                if trip_time > 750 then
                                    log.warning("pocket supervisor KEEP_ALIVE trip time > 750ms (" .. trip_time .. "ms)")
                                end

                                -- log.debug("pocket supervisor RTT = " .. trip_time .. "ms")

                                _send_sv_keep_alive_ack(timestamp)
                            else
                                log.debug("supervisor SCADA keep alive packet length mismatch")
                            end
                        elseif packet.type == SCADA_MGMT_TYPE.CLOSE then
                            -- handle session close
                            sv_watchdog.cancel()
                            self.sv.linked = false
                            self.sv.r_seq_num = nil
                            self.sv.addr = comms.BROADCAST
                            log.info("supervisor server connection closed by remote host")
                        else
                            log.debug("received unknown SCADA_MGMT packet type " .. packet.type .. " from supervisor")
                        end
                    else
                        log.debug("discarding supervisor non-link SCADA_MGMT packet before linked")
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " from supervisor", true)
                end
            else
                log.debug("received packet from unconfigured channel " .. r_chan, true)
            end
        end
    end

    -- check if we are still linked with the supervisor
    ---@nodiscard
    function public.is_sv_linked() return self.sv.linked end

    -- check if we are still linked with the coordinator
    ---@nodiscard
    function public.is_api_linked() return self.api.linked end

    return public
end


return pocket
