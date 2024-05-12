local comms     = require("scada-common.comms")
local log       = require("scada-common.log")
local util      = require("scada-common.util")

local iocontrol = require("pocket.iocontrol")

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE = comms.MGMT_TYPE
local CRDN_TYPE = comms.CRDN_TYPE

local LINK_STATE = iocontrol.LINK_STATE

local pocket = {}

---@type pkt_config
local config = {}

pocket.config = config

-- load the pocket configuration
function pocket.load_config()
    if not settings.load("/pocket.settings") then return false end

    config.SVR_Channel = settings.get("SVR_Channel")
    config.CRD_Channel = settings.get("CRD_Channel")
    config.PKT_Channel = settings.get("PKT_Channel")
    config.ConnTimeout = settings.get("ConnTimeout")
    config.TrustedRange = settings.get("TrustedRange")
    config.AuthKey = settings.get("AuthKey")

    config.LogMode = settings.get("LogMode")
    config.LogPath = settings.get("LogPath")
    config.LogDebug = settings.get("LogDebug")

    local cfv = util.new_validator()

    cfv.assert_channel(config.SVR_Channel)
    cfv.assert_channel(config.CRD_Channel)
    cfv.assert_channel(config.PKT_Channel)
    cfv.assert_type_num(config.ConnTimeout)
    cfv.assert_min(config.ConnTimeout, 2)
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

    return cfv.valid()
end

-- pocket coordinator + supervisor communications
---@nodiscard
---@param version string pocket version
---@param nic nic network interface device
---@param sv_watchdog watchdog
---@param api_watchdog watchdog
function pocket.comms(version, nic, sv_watchdog, api_watchdog)
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

    comms.set_trusted_range(config.TrustedRange)

    -- PRIVATE FUNCTIONS --

    -- configure network channels
    nic.closeAll()
    nic.open(config.PKT_Channel)

    -- send a management packet to the supervisor
    ---@param msg_type MGMT_TYPE
    ---@param msg table
    local function _send_sv(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local pkt = comms.mgmt_packet()

        pkt.make(msg_type, msg)
        s_pkt.make(self.sv.addr, self.sv.seq_num, PROTOCOL.SCADA_MGMT, pkt.raw_sendable())

        nic.transmit(config.SVR_Channel, config.PKT_Channel, s_pkt)
        self.sv.seq_num = self.sv.seq_num + 1
    end

    -- send a management packet to the coordinator
    ---@param msg_type MGMT_TYPE
    ---@param msg table
    local function _send_crd(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local pkt = comms.mgmt_packet()

        pkt.make(msg_type, msg)
        s_pkt.make(self.api.addr, self.api.seq_num, PROTOCOL.SCADA_MGMT, pkt.raw_sendable())

        nic.transmit(config.CRD_Channel, config.PKT_Channel, s_pkt)
        self.api.seq_num = self.api.seq_num + 1
    end

    -- send an API packet to the coordinator
    ---@param msg_type CRDN_TYPE
    ---@param msg table
    local function _send_api(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local pkt = comms.crdn_packet()

        pkt.make(msg_type, msg)
        s_pkt.make(self.api.addr, self.api.seq_num, PROTOCOL.SCADA_CRDN, pkt.raw_sendable())

        nic.transmit(config.CRD_Channel, config.PKT_Channel, s_pkt)
        self.api.seq_num = self.api.seq_num + 1
    end

    -- attempt supervisor connection establishment
    local function _send_sv_establish()
        _send_sv(MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.PKT })
    end

    -- attempt coordinator API connection establishment
    local function _send_api_establish()
        _send_crd(MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.PKT, comms.api_version })
    end

    -- keep alive ack to supervisor
    ---@param srv_time integer
    local function _send_sv_keep_alive_ack(srv_time)
        _send_sv(MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- keep alive ack to coordinator
    ---@param srv_time integer
    local function _send_api_keep_alive_ack(srv_time)
        _send_crd(MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
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
        _send_sv(MGMT_TYPE.CLOSE, {})
    end

    -- close connection to coordinator API server
    function public.close_api()
        api_watchdog.cancel()
        self.api.linked = false
        self.api.r_seq_num = nil
        self.api.addr = comms.BROADCAST
        _send_crd(MGMT_TYPE.CLOSE, {})
    end

    -- close the connections to the servers
    function public.close()
        public.close_sv()
        public.close_api()
    end

    -- attempt to re-link if any of the dependent links aren't active
    function public.link_update()
        if not self.sv.linked then
            iocontrol.report_link_state(util.trinary(self.api.linked, LINK_STATE.API_LINK_ONLY, LINK_STATE.UNLINKED))

            if self.establish_delay_counter <= 0 then
                _send_sv_establish()
                self.establish_delay_counter = 4
            else
                self.establish_delay_counter = self.establish_delay_counter - 1
            end
        elseif not self.api.linked then
            iocontrol.report_link_state(LINK_STATE.SV_LINK_ONLY)

            if self.establish_delay_counter <= 0 then
                _send_api_establish()
                self.establish_delay_counter = 4
            else
                self.establish_delay_counter = self.establish_delay_counter - 1
            end
        else
            -- linked, all good!
            iocontrol.report_link_state(LINK_STATE.LINKED, self.sv.addr, self.api.addr)
        end
    end

    -- supervisor get active alarm tones
    function public.diag__get_alarm_tones()
        if self.sv.linked then _send_sv(MGMT_TYPE.DIAG_TONE_GET, {}) end
    end

    -- supervisor test alarm tones by tone
    ---@param id TONE|0 tone ID, or 0 to stop all
    ---@param state boolean tone state
    function public.diag__set_alarm_tone(id, state)
        if self.sv.linked then _send_sv(MGMT_TYPE.DIAG_TONE_SET, { id, state }) end
    end

    -- supervisor test alarm tones by alarm
    ---@param id ALARM|0 alarm ID, 0 to stop all
    ---@param state boolean alarm state
    function public.diag__set_alarm(id, state)
        if self.sv.linked then _send_sv(MGMT_TYPE.DIAG_ALARM_SET, { id, state }) end
    end

    -- coordinator get unit data
    function public.api__get_unit(unit)
        if self.api.linked then _send_api(CRDN_TYPE.API_GET_UNIT, { unit }) end
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

    ---@param packet mgmt_frame|crdn_frame
    ---@param length integer
    ---@param max integer?
    ---@return boolean
    local function _check_length(packet, length, max)
        local ok = util.trinary(max == nil, packet.length == length, packet.length >= length and packet.length <= (max or 0))
        if not ok then
            local fmt = "[comms] RX_PACKET{r_chan=%d,proto=%d,type=%d}: packet length mismatch -> expect %d != actual %d"
            log.debug(util.sprintf(fmt, packet.scada_frame.remote_channel(), packet.scada_frame.protocol(), packet.type))
        end
        return ok
    end

    ---@param packet mgmt_frame|crdn_frame
    local function _fail_type(packet)
        local fmt = "[comms] RX_PACKET{r_chan=%d,proto=%d,type=%d}: unrecognized packet type"
        log.debug(util.sprintf(fmt, packet.scada_frame.remote_channel(), packet.scada_frame.protocol(), packet.type))
    end

    -- handle a packet
    ---@param packet mgmt_frame|crdn_frame|nil
    function public.handle_packet(packet)
        local diag = iocontrol.get_db().diag

        if packet ~= nil then
            local l_chan   = packet.scada_frame.local_channel()
            local r_chan   = packet.scada_frame.remote_channel()
            local protocol = packet.scada_frame.protocol()
            local src_addr = packet.scada_frame.src_addr()

            if l_chan ~= config.PKT_Channel then
                log.debug("received packet on unconfigured channel " .. l_chan, true)
            elseif r_chan == config.CRD_Channel then
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

                if protocol == PROTOCOL.SCADA_CRDN then
                    ---@cast packet crdn_frame
                    if self.api.linked then
                        if packet.type == CRDN_TYPE.API_GET_FAC then
                            if _check_length(packet, 11) then
                                iocontrol.record_facility_data(packet.data)
                            end
                        elseif packet.type == CRDN_TYPE.API_GET_UNIT then
                            if _check_length(packet, 9) then
                                iocontrol.record_unit_data(packet.data)
                            end
                        else _fail_type(packet) end
                    else
                        log.debug("discarding coordinator SCADA_CRDN packet before linked")
                    end
                elseif protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_frame
                    if self.api.linked then
                        if packet.type == MGMT_TYPE.KEEP_ALIVE then
                            -- keep alive request received, echo back
                            if _check_length(packet, 1) then
                                local timestamp = packet.data[1]
                                local trip_time = util.time() - timestamp

                                if trip_time > 750 then
                                    log.warning("pocket coordinator KEEP_ALIVE trip time > 750ms (" .. trip_time .. "ms)")
                                end

                                -- log.debug("pocket coordinator TT = " .. trip_time .. "ms")

                                _send_api_keep_alive_ack(timestamp)

                                iocontrol.report_crd_tt(trip_time)
                            end
                        elseif packet.type == MGMT_TYPE.CLOSE then
                            -- handle session close
                            api_watchdog.cancel()
                            self.api.linked = false
                            self.api.r_seq_num = nil
                            self.api.addr = comms.BROADCAST
                            log.info("coordinator server connection closed by remote host")
                        else _fail_type(packet) end
                    elseif packet.type == MGMT_TYPE.ESTABLISH then
                        -- connection with coordinator established
                        if _check_length(packet, 1, 2) then
                            local est_ack = packet.data[1]

                            if est_ack == ESTABLISH_ACK.ALLOW then
                                if packet.length == 2 then
                                    local fac_config = packet.data[2]

                                    if type(fac_config) == "table" and #fac_config == 2 then
                                        -- get configuration
                                        local conf = { num_units = fac_config[1], cooling = fac_config[2] }

                                        ---@todo unit options
                                        iocontrol.init_fac(conf, 1)

                                        log.info("coordinator connection established")
                                        self.establish_delay_counter = 0
                                        self.api.linked = true
                                        self.api.addr = src_addr

                                        if self.sv.linked then
                                            iocontrol.report_link_state(LINK_STATE.LINKED, self.sv.addr, self.api.addr)
                                        else
                                            iocontrol.report_link_state(LINK_STATE.API_LINK_ONLY)
                                        end
                                    else
                                        log.debug("invalid facility configuration table received from coordinator, establish failed")
                                    end
                                else
                                    log.debug("received coordinator establish allow without facility configuration")
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
                            elseif est_ack == ESTABLISH_ACK.BAD_API_VERSION then
                                if self.api.last_est_ack ~= est_ack then
                                    log.info("coordinator api version mismatch")
                                end
                            else
                                log.debug("coordinator SCADA_MGMT establish packet reply unsupported")
                            end

                            self.api.last_est_ack = est_ack
                        end
                    else
                        log.debug("discarding coordinator non-link SCADA_MGMT packet before linked")
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " from coordinator", true)
                end
            elseif r_chan == config.SVR_Channel then
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
                    if self.sv.linked then
                        if packet.type == MGMT_TYPE.KEEP_ALIVE then
                            -- keep alive request received, echo back
                            if _check_length(packet, 1) then
                                local timestamp = packet.data[1]
                                local trip_time = util.time() - timestamp

                                if trip_time > 750 then
                                    log.warning("pocket supervisor KEEP_ALIVE trip time > 750ms (" .. trip_time .. "ms)")
                                end

                                -- log.debug("pocket supervisor TT = " .. trip_time .. "ms")

                                _send_sv_keep_alive_ack(timestamp)

                                iocontrol.report_svr_tt(trip_time)
                            end
                        elseif packet.type == MGMT_TYPE.CLOSE then
                            -- handle session close
                            sv_watchdog.cancel()
                            self.sv.linked = false
                            self.sv.r_seq_num = nil
                            self.sv.addr = comms.BROADCAST
                            log.info("supervisor server connection closed by remote host")
                        elseif packet.type == MGMT_TYPE.DIAG_TONE_GET then
                            if _check_length(packet, 8) then
                                for i = 1, #packet.data do
                                    diag.tone_test.tone_indicators[i].update(packet.data[i] == true)
                                end
                            end
                        elseif packet.type == MGMT_TYPE.DIAG_TONE_SET then
                            if packet.length == 1 and packet.data[1] == false then
                                diag.tone_test.ready_warn.set_value("testing denied")
                                log.debug("supervisor SCADA diag tone set failed")
                            elseif packet.length == 2 and type(packet.data[2]) == "table" then
                                local ready = packet.data[1]
                                local states = packet.data[2]

                                diag.tone_test.ready_warn.set_value(util.trinary(ready, "", "system not ready"))

                                for i = 1, #states do
                                    if diag.tone_test.tone_buttons[i] ~= nil then
                                        diag.tone_test.tone_buttons[i].set_value(states[i] == true)
                                        diag.tone_test.tone_indicators[i].update(states[i] == true)
                                    end
                                end
                            else
                                log.debug("supervisor SCADA diag tone set packet length/type mismatch")
                            end
                        elseif packet.type == MGMT_TYPE.DIAG_ALARM_SET then
                            if packet.length == 1 and packet.data[1] == false then
                                diag.tone_test.ready_warn.set_value("testing denied")
                                log.debug("supervisor SCADA diag alarm set failed")
                            elseif packet.length == 2 and type(packet.data[2]) == "table" then
                                local ready = packet.data[1]
                                local states = packet.data[2]

                                diag.tone_test.ready_warn.set_value(util.trinary(ready, "", "system not ready"))

                                for i = 1, #states do
                                    if diag.tone_test.alarm_buttons[i] ~= nil then
                                        diag.tone_test.alarm_buttons[i].set_value(states[i] == true)
                                    end
                                end
                            else
                                log.debug("supervisor SCADA diag alarm set packet length/type mismatch")
                            end
                        else _fail_type(packet) end
                    elseif packet.type == MGMT_TYPE.ESTABLISH then
                        -- connection with supervisor established
                        if _check_length(packet, 1) then
                            local est_ack = packet.data[1]

                            if est_ack == ESTABLISH_ACK.ALLOW then
                                log.info("supervisor connection established")
                                self.establish_delay_counter = 0
                                self.sv.linked = true
                                self.sv.addr = src_addr

                                if self.api.linked then
                                    iocontrol.report_link_state(LINK_STATE.LINKED, self.sv.addr, self.api.addr)
                                else
                                    iocontrol.report_link_state(LINK_STATE.SV_LINK_ONLY)
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
                        end
                    else
                        log.debug("discarding supervisor non-link SCADA_MGMT packet before linked")
                    end
                else _fail_type(packet) end
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
