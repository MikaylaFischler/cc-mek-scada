local audio   = require("scada-common.audio")
local comms   = require("scada-common.comms")
local ppm     = require("scada-common.ppm")
local log     = require("scada-common.log")
local types   = require("scada-common.types")
local util    = require("scada-common.util")

local themes  = require("graphics.themes")

local databus = require("rtu.databus")
local modbus  = require("rtu.modbus")

local rtu = {}

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE = comms.MGMT_TYPE
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE

---@type rtu_config
---@diagnostic disable-next-line: missing-fields
local config = {}

rtu.config = config

-- load the RTU configuration
function rtu.load_config()
    if not settings.load("/rtu.settings") then return false end

    config.Peripherals = settings.get("Peripherals")
    config.Redstone = settings.get("Redstone")

    config.SpeakerVolume = settings.get("SpeakerVolume")

    config.SVR_Channel = settings.get("SVR_Channel")
    config.RTU_Channel = settings.get("RTU_Channel")
    config.ConnTimeout = settings.get("ConnTimeout")
    config.TrustedRange = settings.get("TrustedRange")
    config.AuthKey = settings.get("AuthKey")

    config.LogMode = settings.get("LogMode")
    config.LogPath = settings.get("LogPath")
    config.LogDebug = settings.get("LogDebug")

    config.FrontPanelTheme = settings.get("FrontPanelTheme")
    config.ColorMode = settings.get("ColorMode")

    return rtu.validate_config(config)
end

-- validate an RTU gateway configuration
---@param cfg rtu_config
function rtu.validate_config(cfg)
    local cfv = util.new_validator()

    cfv.assert_type_num(cfg.SpeakerVolume)
    cfv.assert_range(cfg.SpeakerVolume, 0, 3)

    cfv.assert_channel(cfg.SVR_Channel)
    cfv.assert_channel(cfg.RTU_Channel)
    cfv.assert_type_num(cfg.ConnTimeout)
    cfv.assert_min(cfg.ConnTimeout, 2)
    cfv.assert_type_num(cfg.TrustedRange)
    cfv.assert_min(cfg.TrustedRange, 0)
    cfv.assert_type_str(cfg.AuthKey)

    if type(cfg.AuthKey) == "string" then
        local len = string.len(cfg.AuthKey)
        cfv.assert(len == 0 or len >= 8)
    end

    cfv.assert_type_int(cfg.LogMode)
    cfv.assert_range(cfg.LogMode, 0, 1)
    cfv.assert_type_str(cfg.LogPath)
    cfv.assert_type_bool(cfg.LogDebug)

    cfv.assert_type_int(cfg.FrontPanelTheme)
    cfv.assert_range(cfg.FrontPanelTheme, 1, 2)
    cfv.assert_type_int(cfg.ColorMode)
    cfv.assert_range(cfg.ColorMode, 1, themes.COLOR_MODE.NUM_MODES)

    cfv.assert_type_table(cfg.Peripherals)
    cfv.assert_type_table(cfg.Redstone)

    return cfv.valid()
end

-- create a new RTU unit<br>
-- if this is for a PPM peripheral, auto fault clearing MUST stay enabled once access begins
---@nodiscard
---@param device table|nil peripheral device, if applicable
function rtu.init_unit(device)
    local self = {
        discrete_inputs = {},
        coils = {},
        input_regs = {},
        holding_regs = {},
        io_count_cache = { 0, 0, 0, 0 }
    }

    local insert = table.insert

    local stub = function () log.warning("tried to call an RTU function stub") end

    ---@class rtu_device
    local public = {}

    ---@class rtu
    local protected = {}

    -- function to check if the peripheral (if exists) is faulted
    local function _is_faulted() return false end
    if device then _is_faulted = device.__p_is_faulted end

    -- refresh IO count
    local function _count_io()
        self.io_count_cache = { #self.discrete_inputs, #self.coils, #self.input_regs, #self.holding_regs }
    end

    -- return IO count
    ---@return integer discrete_inputs, integer coils, integer input_regs, integer holding_regs
    function public.io_count()
        return self.io_count_cache[1], self.io_count_cache[2], self.io_count_cache[3], self.io_count_cache[4]
    end

    -- pass a function through or generate one to call a function by name from the device
    ---@param f function|string function or device function name
    local function _as_func(f)
        if type(f) == "string" then
            local name = f
            if device then
                f = function (...) return device[name](...) end
            else f = stub end
        end

        return f
    end

    -- discrete inputs: single bit read-only

    -- connect discrete input
    ---@param f function|string function or function name
    ---@return integer count count of discrete inputs
    function protected.connect_di(f)
        insert(self.discrete_inputs, { read = _as_func(f) })
        _count_io()
        return #self.discrete_inputs
    end

    -- read discrete input
    ---@param di_addr integer
    ---@return any value, boolean access_fault
    function public.read_di(di_addr)
        local value = self.discrete_inputs[di_addr].read()
        return value, _is_faulted()
    end

    -- coils: single bit read-write

    -- connect coil
    ---@param f_read function|string function or function name
    ---@param f_write function|string function or function name
    ---@return integer count count of coils
    function protected.connect_coil(f_read, f_write)
        insert(self.coils, { read = _as_func(f_read), write = _as_func(f_write) })
        _count_io()
        return #self.coils
    end

    -- read coil
    ---@param coil_addr integer
    ---@return any value, boolean access_fault
    function public.read_coil(coil_addr)
        local value = self.coils[coil_addr].read()
        return value, _is_faulted()
    end

    -- write coil
    ---@param coil_addr integer
    ---@param value any
    ---@return boolean access_fault
    function public.write_coil(coil_addr, value)
        self.coils[coil_addr].write(value)
        return _is_faulted()
    end

    -- input registers: multi-bit read-only

    -- connect input register
    ---@param f function|string function or function name
    ---@return integer count count of input registers
    function protected.connect_input_reg(f)
        insert(self.input_regs, { read = _as_func(f) })
        _count_io()
        return #self.input_regs
    end

    -- read input register
    ---@param reg_addr integer
    ---@return any value, boolean access_fault
    function public.read_input_reg(reg_addr)
        local value = self.input_regs[reg_addr].read()
        return value, _is_faulted()
    end

    -- holding registers: multi-bit read-write

    -- connect holding register
    ---@param f_read function|string function or function name
    ---@param f_write function|string function or function name
    ---@return integer count count of holding registers
    function protected.connect_holding_reg(f_read, f_write)
        insert(self.holding_regs, { read = _as_func(f_read), write = _as_func(f_write) })
        _count_io()
        return #self.holding_regs
    end

    -- read holding register
    ---@param reg_addr integer
    ---@return any value, boolean access_fault
    function public.read_holding_reg(reg_addr)
        local value = self.holding_regs[reg_addr].read()
        return value, _is_faulted()
    end

    -- write holding register
    ---@param reg_addr integer
    ---@param value any
    ---@return boolean access_fault
    function public.write_holding_reg(reg_addr, value)
        self.holding_regs[reg_addr].write(value)
        return _is_faulted()
    end

    -- public RTU device access

    -- get the public interface to this RTU
    function protected.interface() return public end

    return protected
end

-- create an alarm speaker sounder
---@param speaker Speaker device peripheral
function rtu.init_sounder(speaker)
    ---@class rtu_speaker_sounder
    local spkr_ctl = {
        speaker = speaker,
        name = ppm.get_iface(speaker),
        playing = false,
        stream = audio.new_stream(),
        play = function () end,
        stop = function () end,
        continue = function () end
    }

    -- continue audio stream if playing
    function spkr_ctl.continue()
        if spkr_ctl.playing then
            if spkr_ctl.speaker ~= nil and spkr_ctl.stream.has_next_block() then
                local success = spkr_ctl.speaker.playAudio(spkr_ctl.stream.get_next_block(), config.SpeakerVolume)
                if not success then log.error(util.c("rtu_sounder(", spkr_ctl.name, "): error playing audio")) end
            end
        end
    end

    -- start audio stream playback
    function spkr_ctl.play()
        if not spkr_ctl.playing then
            spkr_ctl.playing = true
            return spkr_ctl.continue()
        end
    end

    -- stop audio stream playback
    function spkr_ctl.stop()
        spkr_ctl.playing = false
        spkr_ctl.speaker.stop()
        spkr_ctl.stream.stop()
    end

    return spkr_ctl
end

-- RTU Communications
---@nodiscard
---@param version string RTU version
---@param nic nic network interface device
---@param conn_watchdog watchdog watchdog reference
function rtu.comms(version, nic, conn_watchdog)
    local self = {
        sv_addr = comms.BROADCAST,
        seq_num = util.time_ms() * 10, -- unique per peer, restarting will not re-use seq nums due to message rate
        r_seq_num = nil,               ---@type nil|integer
        txn_id = 0,
        last_est_ack = ESTABLISH_ACK.ALLOW
    }

    local insert = table.insert

    comms.set_trusted_range(config.TrustedRange)

    -- PRIVATE FUNCTIONS --

    -- configure modem channels
    nic.closeAll()
    nic.open(config.RTU_Channel)

    -- send a scada management packet
    ---@param msg_type MGMT_TYPE
    ---@param msg table
    local function _send(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.sv_addr, self.seq_num, PROTOCOL.SCADA_MGMT, m_pkt.raw_sendable())

        nic.transmit(config.SVR_Channel, config.RTU_Channel, s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- keep alive ack
    ---@param srv_time integer
    local function _send_keep_alive_ack(srv_time)
        _send(MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- generate device advertisement table
    ---@nodiscard
    ---@param units rtu_registry_entry[]
    ---@return table advertisement
    local function _generate_advertisement(units)
        local advertisement = {}

        for i = 1, #units do
            local unit = units[i]

            if unit.type ~= nil then
                insert(advertisement, { unit.type, unit.index, unit.reactor or -1, unit.rs_conns })
            end
        end

        return advertisement
    end

    -- PUBLIC FUNCTIONS --

    ---@class rtu_comms
    local public = {}

    -- send a MODBUS TCP packet
    ---@param m_pkt modbus_packet
    function public.send_modbus(m_pkt)
        local s_pkt = comms.scada_packet()
        s_pkt.make(self.sv_addr, self.seq_num, PROTOCOL.MODBUS_TCP, m_pkt.raw_sendable())
        nic.transmit(config.SVR_Channel, config.RTU_Channel, s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- unlink from the server
    ---@param rtu_state rtu_state
    function public.unlink(rtu_state)
        rtu_state.linked = false
        self.sv_addr = comms.BROADCAST
        self.r_seq_num = nil
        databus.tx_link_state(types.PANEL_LINK_STATE.DISCONNECTED)
    end

    -- close the connection to the server
    ---@param rtu_state rtu_state
    function public.close(rtu_state)
        conn_watchdog.cancel()
        public.unlink(rtu_state)
        _send(MGMT_TYPE.CLOSE, {})
    end

    -- send establish request (includes advertisement)
    ---@param units table
    function public.send_establish(units)
        self.r_seq_num = nil
        _send(MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.RTU, _generate_advertisement(units) })
    end

    -- send capability advertisement
    ---@param units table
    function public.send_advertisement(units)
        _send(MGMT_TYPE.RTU_ADVERT, _generate_advertisement(units))
    end

    -- notify that a peripheral was remounted
    ---@param unit_index integer RTU unit ID
    function public.send_remounted(unit_index)
        _send(MGMT_TYPE.RTU_DEV_REMOUNT, { unit_index })
    end

    -- parse a MODBUS/SCADA packet
    ---@nodiscard
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return modbus_frame|mgmt_frame|nil packet
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
            -- get as SCADA management packet
            elseif s_pkt.protocol() == PROTOCOL.SCADA_MGMT then
                local mgmt_pkt = comms.mgmt_packet()
                if mgmt_pkt.decode(s_pkt) then
                    pkt = mgmt_pkt.get()
                end
            else
                log.debug("illegal packet type " .. s_pkt.protocol(), true)
            end
        end

        return pkt
    end

    -- handle a MODBUS/SCADA packet
    ---@param packet modbus_frame|mgmt_frame
    ---@param units rtu_registry_entry[] RTU entries
    ---@param rtu_state rtu_state
    ---@param sounders rtu_speaker_sounder[] speaker alarm sounders
    function public.handle_packet(packet, units, rtu_state, sounders)
        -- print a log message to the terminal as long as the UI isn't running
        local function println_ts(message) if not rtu_state.fp_ok then util.println_ts(message) end end

        local protocol = packet.scada_frame.protocol()
        local l_chan   = packet.scada_frame.local_channel()
        local src_addr = packet.scada_frame.src_addr()

        if l_chan == config.RTU_Channel then
            -- check sequence number
            if self.r_seq_num == nil then
                self.r_seq_num = packet.scada_frame.seq_num() + 1
            elseif self.r_seq_num ~= packet.scada_frame.seq_num() then
                log.warning("sequence out-of-order: next = " .. self.r_seq_num .. ", new = " .. packet.scada_frame.seq_num())
                return
            elseif rtu_state.linked and (src_addr ~= self.sv_addr) then
                log.debug("received packet from unknown computer " .. src_addr .. " while linked (expected " .. self.sv_addr ..
                            "); channel in use by another system?")
                return
            else
                self.r_seq_num = packet.scada_frame.seq_num() + 1
            end

            -- feed watchdog on valid sequence number
            conn_watchdog.feed()

            -- handle packet
            if protocol == PROTOCOL.MODBUS_TCP then
                ---@cast packet modbus_frame
                if rtu_state.linked then
                    local return_code   ---@type boolean
                    local reply         ---@type modbus_packet

                    -- handle MODBUS instruction
                    if packet.unit_id <= #units then
                        local unit = units[packet.unit_id]
                        local unit_dbg_tag = " (unit " .. packet.unit_id .. ")"

                        if unit.type == RTU_UNIT_TYPE.REDSTONE then
                            -- immediately execute redstone RTU requests
                            return_code, reply = unit.modbus_io.handle_packet(packet)

                            if not return_code then
                                log.warning("requested MODBUS operation failed" .. unit_dbg_tag)
                            end
                        else
                            -- check validity then pass off to unit comms thread
                            return_code, reply = unit.modbus_io.check_request(packet)
                            if return_code then
                                -- check if there are more than 3 active transactions, which will be treated as busy
                                if unit.pkt_queue.length() > 3 then
                                    reply = modbus.reply__srv_device_busy(packet)
                                    log.warning("device busy, discarding new request" .. unit_dbg_tag)
                                else
                                    -- queue the command if not busy
                                    unit.pkt_queue.push_packet(packet)
                                end
                            else
                                log.warning("requested MODBUS operation failed" .. unit_dbg_tag)
                            end
                        end
                    else
                        -- unit ID out of range?
                        reply = modbus.reply__gw_unavailable(packet)
                        log.debug("received MODBUS packet for non-existent unit")
                    end

                    public.send_modbus(reply)
                else
                    log.debug("discarding MODBUS packet before linked")
                end
            elseif protocol == PROTOCOL.SCADA_MGMT then
                ---@cast packet mgmt_frame
                -- SCADA management packet
                if rtu_state.linked then
                    if packet.type == MGMT_TYPE.KEEP_ALIVE then
                        -- keep alive request received, echo back
                        if packet.length == 1 and type(packet.data[1]) == "number" then
                            local timestamp = packet.data[1]
                            local trip_time = util.time() - timestamp

                            if trip_time > 750 then
                                log.warning("RTU KEEP_ALIVE trip time > 750ms (" .. trip_time .. "ms)")
                            end

                            -- log.debug("RTU RTT = " .. trip_time .. "ms")

                            _send_keep_alive_ack(timestamp)
                        else
                            log.debug("SCADA_MGMT keep alive packet length/type mismatch")
                        end
                    elseif packet.type == MGMT_TYPE.CLOSE then
                        -- close connection
                        conn_watchdog.cancel()
                        public.unlink(rtu_state)
                        println_ts("server connection closed by remote host")
                        log.warning("server connection closed by remote host")
                    elseif packet.type == MGMT_TYPE.RTU_ADVERT then
                        -- request for capabilities again
                        public.send_advertisement(units)
                    elseif packet.type == MGMT_TYPE.RTU_TONE_ALARM then
                        -- alarm tone update from supervisor
                        if (packet.length == 1) and type(packet.data[1] == "table") and (#packet.data[1] == 8) then
                            local states = packet.data[1]

                            -- set tone states
                            for i = 1, #sounders do
                                for id = 1, #states do sounders[i].stream.set_active(id, states[id] == true) end
                            end
                        end
                    else
                        -- not supported
                        log.debug("received unsupported SCADA_MGMT message type " .. packet.type)
                    end
                elseif packet.type == MGMT_TYPE.ESTABLISH then
                    if packet.length == 1 then
                        local est_ack = packet.data[1]

                        if est_ack == ESTABLISH_ACK.ALLOW then
                            -- establish allowed
                            rtu_state.linked = true
                            self.sv_addr = packet.scada_frame.src_addr()
                            println_ts("supervisor connection established")
                            log.info("supervisor connection established")
                        else
                            -- establish denied
                            if est_ack ~= self.last_est_ack then
                                if est_ack == ESTABLISH_ACK.BAD_VERSION then
                                    -- version mismatch
                                    println_ts("supervisor comms version mismatch (try updating), retrying...")
                                    log.warning("supervisor connection denied due to comms version mismatch, retrying")
                                else
                                    println_ts("supervisor connection denied, retrying...")
                                    log.warning("supervisor connection denied, retrying")
                                end
                            end

                            -- unlink
                            self.sv_addr = comms.BROADCAST
                            rtu_state.linked = false
                        end

                        self.last_est_ack = est_ack

                        -- report link state
                        databus.tx_link_state(est_ack + 1)
                    else
                        log.debug("SCADA_MGMT establish packet length mismatch")
                    end
                else
                    log.debug("discarding non-link SCADA_MGMT packet before linked")
                end
            else
                -- should be unreachable assuming packet is from parse_packet()
                log.error("illegal packet type " .. protocol, true)
            end
        else
            log.debug("received packet on unconfigured channel " .. l_chan, true)
        end
    end

    return public
end

return rtu
