local comms       = require("scada-common.comms")
local log         = require("scada-common.log")
local ppm         = require("scada-common.ppm")
local util        = require("scada-common.util")

local iocontrol   = require("coordinator.iocontrol")
local process     = require("coordinator.process")

local apisessions = require("coordinator.session.apisessions")

local dialog      = require("coordinator.ui.dialog")

local print = util.print
local println = util.println
local println_ts = util.println_ts

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local SCADA_MGMT_TYPE = comms.SCADA_MGMT_TYPE
local SCADA_CRDN_TYPE = comms.SCADA_CRDN_TYPE
local UNIT_COMMAND = comms.UNIT_COMMAND
local FAC_COMMAND = comms.FAC_COMMAND

local coordinator = {}

-- request the user to select a monitor
---@nodiscard
---@param names table available monitors
---@return boolean|string|nil
local function ask_monitor(names)
    println("available monitors:")
    for i = 1, #names do
        print(" " .. names[i])
    end
    println("")
    println("select a monitor or type c to cancel")

    local iface = dialog.ask_options(names, "c")

    if iface ~= false and iface ~= nil then
        util.filter_table(names, function (x) return x ~= iface end)
    end

    return iface
end

-- configure monitor layout
---@param num_units integer number of units expected
---@return boolean success, monitors_struct? monitors
function coordinator.configure_monitors(num_units)
    ---@class monitors_struct
    local monitors = {
        primary = nil,
        primary_name = "",
        unit_displays = {},
        unit_name_map = {}
    }

    local monitors_avail = ppm.get_monitor_list()
    local names = {}
    local available = {}

    -- get all interface names
    for iface, _ in pairs(monitors_avail) do
        table.insert(names, iface)
        table.insert(available, iface)
    end

    -- we need a certain number of monitors (1 per unit + 1 primary display)
    local num_displays_needed = num_units + 1
    if #names < num_displays_needed then
        local message = "not enough monitors connected (need " .. num_displays_needed .. ")"
        println(message)
        log.warning(message)
        return false
    end

    -- attempt to load settings
    if not settings.load("/coord.settings") then
        log.warning("configure_monitors(): failed to load coordinator settings file (may not exist yet)")
    else
        local _primary = settings.get("PRIMARY_DISPLAY")
        local _unitd = settings.get("UNIT_DISPLAYS")

        -- filter out already assigned monitors
        util.filter_table(available, function (x) return x ~= _primary end)
        if type(_unitd) == "table" then
            util.filter_table(available, function (x) return not util.table_contains(_unitd, x) end)
        end
    end

    ---------------------
    -- PRIMARY DISPLAY --
    ---------------------

    local iface_primary_display = settings.get("PRIMARY_DISPLAY")   ---@type boolean|string|nil

    if not util.table_contains(names, iface_primary_display) then
        println("primary display is not connected")
        local response = dialog.ask_y_n("would you like to change it", true)
        if response == false then return false end
        iface_primary_display = nil
    end

    while iface_primary_display == nil and #available > 0 do
        -- lets get a monitor
        iface_primary_display = ask_monitor(available)
    end

    if type(iface_primary_display) ~= "string" then return false end

    settings.set("PRIMARY_DISPLAY", iface_primary_display)
    util.filter_table(available, function (x) return x ~= iface_primary_display end)

    monitors.primary = ppm.get_periph(iface_primary_display)
    monitors.primary_name = iface_primary_display

    -------------------
    -- UNIT DISPLAYS --
    -------------------

    local unit_displays = settings.get("UNIT_DISPLAYS")

    if unit_displays == nil then
        unit_displays = {}
        for i = 1, num_units do
            local display = nil

            while display == nil and #available > 0 do
                -- lets get a monitor
                println("please select monitor for unit #" .. i)
                display = ask_monitor(available)
            end

            if display == false then return false end

            unit_displays[i] = display
        end
    else
        -- make sure all displays are connected
        for i = 1, num_units do
            local display = unit_displays[i]

            if not util.table_contains(names, display) then
                println("unit #" .. i .. " display is not connected")
                local response = dialog.ask_y_n("would you like to change it", true)
                if response == false then return false end
                display = nil
            end

            while display == nil and #available > 0 do
                -- lets get a monitor
                display = ask_monitor(available)
            end

            if display == false then return false end

            unit_displays[i] = display
        end
    end

    settings.set("UNIT_DISPLAYS", unit_displays)
    if not settings.save("/coord.settings") then
        log.warning("configure_monitors(): failed to save coordinator settings file")
    end

    for i = 1, #unit_displays do
        monitors.unit_displays[i] = ppm.get_periph(unit_displays[i])
        monitors.unit_name_map[i] = unit_displays[i]
    end

    return true, monitors
end

-- dmesg print wrapper
---@param message string message
---@param dmesg_tag string tag
---@param working? boolean to use dmesg_working
---@return function? update, function? done
local function log_dmesg(message, dmesg_tag, working)
    local colors = {
        GRAPHICS = colors.green,
        SYSTEM = colors.cyan,
        BOOT = colors.blue,
        COMMS = colors.purple
    }

    if working then
        return log.dmesg_working(message, dmesg_tag, colors[dmesg_tag])
    else
        log.dmesg(message, dmesg_tag, colors[dmesg_tag])
    end
end

function coordinator.log_graphics(message) log_dmesg(message, "GRAPHICS") end
function coordinator.log_sys(message) log_dmesg(message, "SYSTEM") end
function coordinator.log_boot(message) log_dmesg(message, "BOOT") end
function coordinator.log_comms(message) log_dmesg(message, "COMMS") end

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
---@param modem table modem device
---@param sv_port integer port of configured supervisor
---@param sv_listen integer listening port for supervisor replys
---@param api_listen integer listening port for pocket API
---@param range integer trusted device connection range
---@param sv_watchdog watchdog
function coordinator.comms(version, modem, sv_port, sv_listen, api_listen, range, sv_watchdog)
    local self = {
        sv_linked = false,
        sv_seq_num = 0,
        sv_r_seq_num = nil,
        sv_config_err = false,
        connected = false,
        last_est_ack = ESTABLISH_ACK.ALLOW,
        last_api_est_acks = {}
    }

    comms.set_trusted_range(range)

    -- PRIVATE FUNCTIONS --

    -- configure modem channels
    local function _conf_channels()
        modem.closeAll()
        modem.open(sv_listen)
        modem.open(api_listen)
    end

    _conf_channels()

    -- link modem to apisessions
    apisessions.init(modem)

    -- send a packet to the supervisor
    ---@param msg_type SCADA_MGMT_TYPE|SCADA_CRDN_TYPE
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
        s_pkt.make(self.sv_seq_num, protocol, pkt.raw_sendable())

        modem.transmit(sv_port, sv_listen, s_pkt.raw_sendable())
        self.sv_seq_num = self.sv_seq_num + 1
    end

    -- send an API establish request response
    ---@param dest integer
    ---@param msg table
    local function _send_api_establish_ack(seq_id, dest, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(SCADA_MGMT_TYPE.ESTABLISH, msg)
        s_pkt.make(seq_id, PROTOCOL.SCADA_MGMT, m_pkt.raw_sendable())

        modem.transmit(dest, api_listen, s_pkt.raw_sendable())
    end

    -- attempt connection establishment
    local function _send_establish()
        _send_sv(PROTOCOL.SCADA_MGMT, SCADA_MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.CRDN })
    end

    -- keep alive ack
    ---@param srv_time integer
    local function _send_keep_alive_ack(srv_time)
        _send_sv(PROTOCOL.SCADA_MGMT, SCADA_MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- PUBLIC FUNCTIONS --

    ---@class coord_comms
    local public = {}

    -- reconnect a newly connected modem
    ---@param new_modem table
    function public.reconnect_modem(new_modem)
        modem = new_modem
        _conf_channels()
    end

    -- close the connection to the server
    function public.close()
        sv_watchdog.cancel()
        self.sv_linked = false
        _send_sv(PROTOCOL.SCADA_MGMT, SCADA_MGMT_TYPE.CLOSE, {})
    end

    -- attempt to connect to the subervisor
    ---@nodiscard
    ---@param timeout_s number timeout in seconds
    ---@param tick_dmesg_waiting function callback to tick dmesg waiting
    ---@param task_done function callback to show done on dmesg
    ---@return boolean sv_linked true if connected, false otherwise
    --- EVENT_CONSUMER: this function consumes events
    function public.sv_connect(timeout_s, tick_dmesg_waiting, task_done)
        local clock = util.new_clock(1)
        local start = util.time_s()
        local terminated = false

        _send_establish()

        clock.start()

        while (util.time_s() - start) < timeout_s and (not self.sv_linked) and (not self.sv_config_err) do
            local event, p1, p2, p3, p4, p5 = util.pull_event()

            if event == "timer" and clock.is_clock(p1) then
                -- timed out attempt, try again
                tick_dmesg_waiting(math.max(0, timeout_s - (util.time_s() - start)))
                _send_establish()
                clock.start()
            elseif event == "modem_message" then
                -- handle message
                local packet = public.parse_packet(p1, p2, p3, p4, p5)
                if packet ~= nil and packet.type == SCADA_MGMT_TYPE.ESTABLISH then
                    public.handle_packet(packet)
                end
            elseif event == "terminate" then
                terminated = true
                break
            end
        end

        task_done(self.sv_linked)

        if terminated then
            coordinator.log_comms("supervisor connection attempt cancelled by user")
        elseif self.sv_config_err then
            coordinator.log_comms("supervisor cooling configuration invalid, check supervisor config file")
        elseif not self.sv_linked then
            if self.last_est_ack == ESTABLISH_ACK.DENY then
                coordinator.log_comms("supervisor connection attempt denied")
            elseif self.last_est_ack == ESTABLISH_ACK.COLLISION then
                coordinator.log_comms("supervisor connection failed due to collision")
            elseif self.last_est_ack == ESTABLISH_ACK.BAD_VERSION then
                coordinator.log_comms("supervisor connection failed due to version mismatch")
            else
                coordinator.log_comms("supervisor connection failed with no valid response")
            end
        end

        return self.sv_linked
    end

    -- send a facility command
    ---@param cmd FAC_COMMAND command
    function public.send_fac_command(cmd)
        _send_sv(PROTOCOL.SCADA_CRDN, SCADA_CRDN_TYPE.FAC_CMD, { cmd })
    end

    -- send the auto process control configuration with a start command
    ---@param config coord_auto_config configuration
    function public.send_auto_start(config)
        _send_sv(PROTOCOL.SCADA_CRDN, SCADA_CRDN_TYPE.FAC_CMD, {
            FAC_COMMAND.START, config.mode, config.burn_target, config.charge_target, config.gen_target, config.limits
        })
    end

    -- send a unit command
    ---@param cmd UNIT_COMMAND command
    ---@param unit integer unit ID
    ---@param option any? optional option options for the optional options (like burn rate) (does option still look like a word?)
    function public.send_unit_command(cmd, unit, option)
        _send_sv(PROTOCOL.SCADA_CRDN, SCADA_CRDN_TYPE.UNIT_CMD, { cmd, unit, option })
    end

    -- parse a packet
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return mgmt_frame|crdn_frame|capi_frame|nil packet
    function public.parse_packet(side, sender, reply_to, message, distance)
        local pkt = nil
        local s_pkt = comms.scada_packet()

        -- parse packet as generic SCADA packet
        s_pkt.receive(side, sender, reply_to, message, distance)

        if s_pkt.is_valid() then
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
    ---@param packet mgmt_frame|crdn_frame|capi_frame|nil
    function public.handle_packet(packet)
        if packet ~= nil then
            local l_port = packet.scada_frame.local_port()
            local r_port = packet.scada_frame.remote_port()
            local protocol = packet.scada_frame.protocol()

            if l_port == api_listen then
                if protocol == PROTOCOL.COORD_API then
                    ---@cast packet capi_frame
                    -- look for an associated session
                    local session = apisessions.find_session(r_port)

                    -- API packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    else
                        -- any other packet should be session related, discard it
                        log.debug("discarding COORD_API packet without a known session")
                    end
                elseif protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_frame
                    -- look for an associated session
                    local session = apisessions.find_session(r_port)

                    -- SCADA management packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_packet(packet)
                    elseif packet.type == SCADA_MGMT_TYPE.ESTABLISH then
                        -- establish a new session
                        local next_seq_id = packet.scada_frame.seq_num() + 1

                        -- validate packet and continue
                        if packet.length == 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                            local comms_v = packet.data[1]
                            local firmware_v = packet.data[2]
                            local dev_type = packet.data[3]

                            if comms_v ~= comms.version then
                                if self.last_api_est_acks[r_port] ~= ESTABLISH_ACK.BAD_VERSION then
                                    log.info(util.c("dropping API establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
                                    self.last_api_est_acks[r_port] = ESTABLISH_ACK.BAD_VERSION
                                end

                                _send_api_establish_ack(next_seq_id, r_port, { ESTABLISH_ACK.BAD_VERSION })
                            elseif dev_type == DEVICE_TYPE.PKT then
                                -- pocket linking request
                                local id = apisessions.establish_session(l_port, r_port, firmware_v)
                                println(util.c("API: pocket (", firmware_v, ") [:", r_port, "] connected with session ID ", id))
                                coordinator.log_comms(util.c("API: pocket (", firmware_v, ") [:", r_port, "] connected with session ID ", id))

                                _send_api_establish_ack(next_seq_id, r_port, { ESTABLISH_ACK.ALLOW })
                                self.last_api_est_acks[r_port] = ESTABLISH_ACK.ALLOW
                            else
                                log.debug(util.c("illegal establish packet for device ", dev_type, " on API listening channel"))
                                _send_api_establish_ack(next_seq_id, r_port, { ESTABLISH_ACK.DENY })
                            end
                        else
                            log.debug("invalid establish packet (on API listening channel)")
                            _send_api_establish_ack(next_seq_id, r_port, { ESTABLISH_ACK.DENY })
                        end
                    else
                        -- any other packet should be session related, discard it
                        log.debug(util.c(r_port, "->", l_port, ": discarding SCADA_MGMT packet without a known session"))
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " on api listening channel", true)
                end
            elseif l_port == sv_listen then
                -- check sequence number
                if self.sv_r_seq_num == nil then
                    self.sv_r_seq_num = packet.scada_frame.seq_num()
                elseif self.connected and self.sv_r_seq_num >= packet.scada_frame.seq_num() then
                    log.warning("sequence out-of-order: last = " .. self.sv_r_seq_num .. ", new = " .. packet.scada_frame.seq_num())
                    return
                else
                    self.sv_r_seq_num = packet.scada_frame.seq_num()
                end

                -- feed watchdog on valid sequence number
                sv_watchdog.feed()

                -- handle packet
                if protocol == PROTOCOL.SCADA_CRDN then
                    ---@cast packet crdn_frame
                    if self.sv_linked then
                        if packet.type == SCADA_CRDN_TYPE.INITIAL_BUILDS then
                            if packet.length == 2 then
                                -- record builds
                                local fac_builds = iocontrol.record_facility_builds(packet.data[1])
                                local unit_builds = iocontrol.record_unit_builds(packet.data[2])

                                if fac_builds and unit_builds then
                                    -- acknowledge receipt of builds
                                    _send_sv(PROTOCOL.SCADA_CRDN, SCADA_CRDN_TYPE.INITIAL_BUILDS, {})
                                else
                                    log.debug("received invalid INITIAL_BUILDS packet")
                                end
                            else
                                log.debug("INITIAL_BUILDS packet length mismatch")
                            end
                        elseif packet.type == SCADA_CRDN_TYPE.FAC_BUILDS then
                            if packet.length == 1 then
                                -- record facility builds
                                if iocontrol.record_facility_builds(packet.data[1]) then
                                    -- acknowledge receipt of builds
                                    _send_sv(PROTOCOL.SCADA_CRDN, SCADA_CRDN_TYPE.FAC_BUILDS, {})
                                else
                                    log.debug("received invalid FAC_BUILDS packet")
                                end
                            else
                                log.debug("FAC_BUILDS packet length mismatch")
                            end
                        elseif packet.type == SCADA_CRDN_TYPE.FAC_STATUS then
                            -- update facility status
                            if not iocontrol.update_facility_status(packet.data) then
                                log.debug("received invalid FAC_STATUS packet")
                            end
                        elseif packet.type == SCADA_CRDN_TYPE.FAC_CMD then
                            -- facility command acknowledgement
                            if packet.length >= 2 then
                                local cmd = packet.data[1]
                                local ack = packet.data[2] == true

                                if cmd == FAC_COMMAND.SCRAM_ALL then
                                    iocontrol.get_db().facility.scram_ack(ack)
                                elseif cmd == FAC_COMMAND.STOP then
                                    iocontrol.get_db().facility.stop_ack(ack)
                                elseif cmd == FAC_COMMAND.START then
                                    if packet.length == 7 then
                                        process.start_ack_handle({ table.unpack(packet.data, 2) })
                                    else
                                        log.debug("SCADA_CRDN process start (with configuration) ack echo packet length mismatch")
                                    end
                                elseif cmd == FAC_COMMAND.ACK_ALL_ALARMS then
                                    iocontrol.get_db().facility.ack_alarms_ack(ack)
                                else
                                    log.debug(util.c("received facility command ack with unknown command ", cmd))
                                end
                            else
                                log.debug("SCADA_CRDN facility command ack packet length mismatch")
                            end
                        elseif packet.type == SCADA_CRDN_TYPE.UNIT_BUILDS then
                            -- record builds
                            if packet.length == 1 then
                                if iocontrol.record_unit_builds(packet.data[1]) then
                                    -- acknowledge receipt of builds
                                    _send_sv(PROTOCOL.SCADA_CRDN, SCADA_CRDN_TYPE.UNIT_BUILDS, {})
                                else
                                    log.debug("received invalid UNIT_BUILDS packet")
                                end
                            else
                                log.debug("UNIT_BUILDS packet length mismatch")
                            end
                        elseif packet.type == SCADA_CRDN_TYPE.UNIT_STATUSES then
                            -- update statuses
                            if not iocontrol.update_unit_statuses(packet.data) then
                                log.error("received invalid UNIT_STATUSES packet")
                            end
                        elseif packet.type == SCADA_CRDN_TYPE.UNIT_CMD then
                            -- unit command acknowledgement
                            if packet.length == 3 then
                                local cmd = packet.data[1]
                                local unit_id = packet.data[2]
                                local ack = packet.data[3] == true

                                local unit = iocontrol.get_db().units[unit_id]  ---@type ioctl_unit

                                if unit ~= nil then
                                    if cmd == UNIT_COMMAND.SCRAM then
                                        unit.scram_ack(ack)
                                    elseif cmd == UNIT_COMMAND.START then
                                        unit.start_ack(ack)
                                    elseif cmd == UNIT_COMMAND.RESET_RPS then
                                        unit.reset_rps_ack(ack)
                                    elseif cmd == UNIT_COMMAND.SET_BURN then
                                        unit.set_burn_ack(ack)
                                    elseif cmd == UNIT_COMMAND.SET_WASTE then
                                        unit.set_waste_ack(ack)
                                    elseif cmd == UNIT_COMMAND.ACK_ALL_ALARMS then
                                        unit.ack_alarms_ack(ack)
                                    elseif cmd == UNIT_COMMAND.SET_GROUP then
                                        -- UI will be updated to display current group if changed successfully
                                    else
                                        log.debug(util.c("received unit command ack with unknown command ", cmd))
                                    end
                                else
                                    log.debug(util.c("received unit command ack with unknown unit ", unit_id))
                                end
                            else
                                log.debug("SCADA_CRDN unit command ack packet length mismatch")
                            end
                        else
                            log.warning("received unknown SCADA_CRDN packet type " .. packet.type)
                        end
                    else
                        log.debug("discarding SCADA_CRDN packet before linked")
                    end
                elseif protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_frame
                    if packet.type == SCADA_MGMT_TYPE.ESTABLISH then
                        -- connection with supervisor established
                        if packet.length == 2 then
                            local est_ack = packet.data[1]
                            local config = packet.data[2]

                            if est_ack == ESTABLISH_ACK.ALLOW then
                                if type(config) == "table" and #config > 1 then
                                    -- get configuration

                                    ---@class facility_conf
                                    local conf = {
                                        num_units = config[1],  ---@type integer
                                        defs = {}               -- boilers and turbines
                                    }

                                    if (#config - 1) == (conf.num_units * 2) then
                                        -- record sequence of pairs of [#boilers, #turbines] per unit
                                        for i = 2, #config do
                                            table.insert(conf.defs, config[i])
                                        end

                                        -- init io controller
                                        iocontrol.init(conf, public)

                                        self.sv_linked = true
                                        self.sv_config_err = false
                                    else
                                        self.sv_config_err = true
                                        log.warning("invalid supervisor configuration definitions received, establish failed")
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
                                    log.info("supervisor connection denied")
                                end
                            elseif est_ack == ESTABLISH_ACK.COLLISION then
                                if self.last_est_ack ~= est_ack then
                                    log.info("supervisor connection denied due to collision")
                                end
                            elseif est_ack == ESTABLISH_ACK.BAD_VERSION then
                                if self.last_est_ack ~= est_ack then
                                    log.info("supervisor comms version mismatch")
                                end
                            else
                                log.debug("SCADA_MGMT establish packet reply (len = 1) unsupported")
                            end

                            self.last_est_ack = est_ack
                        else
                            log.debug("SCADA_MGMT establish packet length mismatch")
                        end
                    elseif self.sv_linked then
                        if packet.type == SCADA_MGMT_TYPE.KEEP_ALIVE then
                            -- keep alive request received, echo back
                            if packet.length == 1 then
                                local timestamp = packet.data[1]
                                local trip_time = util.time() - timestamp

                                if trip_time > 750 then
                                    log.warning("coord KEEP_ALIVE trip time > 750ms (" .. trip_time .. "ms)")
                                end

                                -- log.debug("coord RTT = " .. trip_time .. "ms")

                                iocontrol.get_db().facility.ps.publish("sv_ping", trip_time)

                                _send_keep_alive_ack(timestamp)
                            else
                                log.debug("SCADA keep alive packet length mismatch")
                            end
                        elseif packet.type == SCADA_MGMT_TYPE.CLOSE then
                            -- handle session close
                            sv_watchdog.cancel()
                            self.sv_linked = false
                            println_ts("server connection closed by remote host")
                            log.info("server connection closed by remote host")
                        else
                            log.debug("received unknown SCADA_MGMT packet type " .. packet.type)
                        end
                    else
                        log.debug("discarding non-link SCADA_MGMT packet before linked")
                    end
                else
                    log.debug("illegal packet type " .. protocol .. " on supervisor listening channel", true)
                end
            else
                log.debug("received packet on unconfigured channel " .. l_port, true)
            end
        end
    end

    -- check if the coordinator is still linked to the supervisor
    ---@nodiscard
    function public.is_linked() return self.sv_linked end

    return public
end

return coordinator
