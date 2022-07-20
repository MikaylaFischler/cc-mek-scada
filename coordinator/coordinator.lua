local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local ppm   = require("scada-common.ppm")
local util  = require("scada-common.util")

local apisessions = require("coordinator.apisessions")
local database    = require("coordinator.database")

local dialog = require("coordinator.ui.dialog")

local coordinator = {}

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local PROTOCOLS = comms.PROTOCOLS
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES
local SCADA_CRDN_TYPES = comms.SCADA_CRDN_TYPES

-- request the user to select a monitor
---@param names table available monitors
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

    -- get all interface names
    for iface, _ in pairs(monitors_avail) do
        table.insert(names, iface)
    end

    -- we need a certain number of monitors (1 per unit + 1 primary display)
    if #names ~= num_units + 1 then
        println("not enough monitors connected (need " .. num_units + 1 .. ")")
        log.warning("insufficient monitors present (need " .. num_units + 1 .. ")")
        return false
    end

    -- attempt to load settings
    settings.load("/coord.settings")

    ---------------------
    -- PRIMARY DISPLAY --
    ---------------------

    local iface_primary_display = settings.get("PRIMARY_DISPLAY")

    if not util.table_contains(names, iface_primary_display) then
        println("primary display is not connected")
        local response = dialog.ask_y_n("would you like to change it", true)
        if response == false then return false end
        iface_primary_display = nil
    end

    while iface_primary_display == nil and #names > 0 do
        -- lets get a monitor
        iface_primary_display = ask_monitor(names)
    end

    if iface_primary_display == false then return false end

    settings.set("PRIMARY_DISPLAY", iface_primary_display)
    util.filter_table(names, function (x) return x ~= iface_primary_display end)

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

            while display == nil and #names > 0 do
                -- lets get a monitor
                println("please select monitor for unit " .. i)
                display = ask_monitor(names)
            end

            if display == false then return false end

            unit_displays[i] = display
        end
    else
        -- make sure all displays are connected
        for i = 1, num_units do
---@diagnostic disable-next-line: need-check-nil
            local display = unit_displays[i]

            if not util.table_contains(names, display) then
                local response = dialog.ask_y_n("unit display " .. i .. " is not connected, would you like to change it?", true)
                if response == false then return false end
                display = nil
            end

            while display == nil and #names > 0 do
                -- lets get a monitor
                display = ask_monitor(names)
            end

            if display == false then return false end

            unit_displays[i] = display
        end
    end

    settings.set("UNIT_DISPLAYS", unit_displays)
    settings.save("/coord.settings")

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

---@param message string
---@return function update, function done
function coordinator.log_comms_connecting(message) return log_dmesg(message, "COMMS", true) end

-- coordinator communications
---@param version string
---@param modem table
---@param sv_port integer
---@param sv_listen integer
---@param api_listen integer
---@param sv_watchdog watchdog
function coordinator.comms(version, modem, sv_port, sv_listen, api_listen, sv_watchdog)
    local self = {
        sv_linked = false,
        sv_seq_num = 0,
        sv_r_seq_num = nil,
        modem = modem,
        connected = false
    }

    ---@class coord_comms
    local public = {}

    -- PRIVATE FUNCTIONS --

    -- open all channels
    local function _open_channels()
        if not self.modem.isOpen(sv_listen) then
            self.modem.open(sv_listen)
        end

        if not self.modem.isOpen(api_listen) then
            self.modem.open(api_listen)
        end
    end

    -- open at construct time
    _open_channels()

    -- send a packet to the supervisor
    ---@param msg_type SCADA_MGMT_TYPES|SCADA_CRDN_TYPES
    ---@param msg table
    local function _send_sv(protocol, msg_type, msg)
        local s_pkt = comms.scada_packet()
        local pkt = nil ---@type mgmt_packet|crdn_packet

        if protocol == PROTOCOLS.SCADA_MGMT then
            pkt = comms.mgmt_packet()
        elseif protocol == PROTOCOLS.SCADA_CRDN then
            pkt = comms.crdn_packet()
        else
            return
        end

        pkt.make(msg_type, msg)
        s_pkt.make(self.sv_seq_num, protocol, pkt.raw_sendable())

        self.modem.transmit(sv_port, sv_listen, s_pkt.raw_sendable())
        self.sv_seq_num = self.sv_seq_num + 1
    end

    -- attempt connection establishment
    local function _send_establish()
        _send_sv(PROTOCOLS.SCADA_CRDN, SCADA_CRDN_TYPES.ESTABLISH, { version })
    end

    -- keep alive ack
    ---@param srv_time integer
    local function _send_keep_alive_ack(srv_time)
        _send_sv(PROTOCOLS.SCADA_MGMT, SCADA_MGMT_TYPES.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- PUBLIC FUNCTIONS --

    -- reconnect a newly connected modem
    ---@param modem table
---@diagnostic disable-next-line: redefined-local
    function public.reconnect_modem(modem)
        self.modem = modem
        _open_channels()
    end

    -- close the connection to the server
    function public.close()
        sv_watchdog.cancel()
        _send_sv(PROTOCOLS.SCADA_MGMT, SCADA_MGMT_TYPES.CLOSE, {})
    end

    -- attempt to connect to the subervisor
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

        while (util.time_s() - start) < timeout_s and not self.sv_linked do
            local event, p1, p2, p3, p4, p5 = util.pull_event()

            if event == "timer" and clock.is_clock(p1) then
                -- timed out attempt, try again
                tick_dmesg_waiting(math.max(0, timeout_s - (util.time_s() - start)))
                _send_establish()
                clock.start()
            elseif event == "modem_message" then
                -- handle message
                local packet = public.parse_packet(p1, p2, p3, p4, p5)
                if packet ~= nil and packet.type == SCADA_CRDN_TYPES.ESTABLISH then
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
        end

        return self.sv_linked
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
            if s_pkt.protocol() == PROTOCOLS.SCADA_MGMT then
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
            -- get as coordinator API packet
            elseif s_pkt.protocol() == PROTOCOLS.COORD_API then
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
    ---@param packet mgmt_frame|crdn_frame|capi_frame
    function public.handle_packet(packet)
        if packet ~= nil then
            local protocol = packet.scada_frame.protocol()

            if protocol == PROTOCOLS.COORD_API then
                apisessions.handle_packet(packet)
            else
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
                if protocol == PROTOCOLS.SCADA_CRDN then
                    if packet.type == SCADA_CRDN_TYPES.ESTABLISH then
                        -- connection with supervisor established
                        if packet.length > 1 then
                            -- get configuration

                            ---@class facility_conf
                            local conf = {
                                num_units = packet.data[1],
                                defs = {}   -- boilers and turbines
                            }

                            if (packet.length - 1) == (conf.num_units * 2) then
                                -- record sequence of pairs of [#boilers, #turbines] per unit
                                for i = 2, packet.length do
                                    table.insert(conf.defs, packet.data[i])
                                end

                                -- init database structure
                                database.init(conf)

                                self.sv_linked = true
                            else
                                log.debug("supervisor conn establish packet length mismatch")
                            end
                        else
                            log.debug("supervisor conn establish packet length mismatch")
                        end
                    elseif packet.type == SCADA_CRDN_TYPES.QUERY_UNIT then
                    elseif packet.type == SCADA_CRDN_TYPES.QUERY_FACILITY then
                    elseif packet.type == SCADA_CRDN_TYPES.COMMAND_UNIT then
                    elseif packet.type == SCADA_CRDN_TYPES.ALARM then
                    else
                        log.warning("received unknown SCADA_CRDN packet type " .. packet.type)
                    end
                elseif protocol == PROTOCOLS.SCADA_MGMT then
                    if packet.type == SCADA_MGMT_TYPES.KEEP_ALIVE then
                        -- keep alive request received, echo back
                        if packet.length == 1 then
                            local timestamp = packet.data[1]
                            local trip_time = util.time() - timestamp

                            if trip_time > 500 then
                                log.warning("coord KEEP_ALIVE trip time > 500ms (" .. trip_time .. "ms)")
                            end

                            -- log.debug("coord RTT = " .. trip_time .. "ms")

                            _send_keep_alive_ack(timestamp)
                        else
                            log.debug("SCADA keep alive packet length mismatch")
                        end
                    elseif packet.type == SCADA_MGMT_TYPES.CLOSE then
                        -- handle session close
                        sv_watchdog.cancel()
                        println_ts("server connection closed by remote host")
                        log.warning("server connection closed by remote host")
                    else
                        log.warning("received unknown SCADA_MGMT packet type " .. packet.type)
                    end
                else
                    -- should be unreachable assuming packet is from parse_packet()
                    log.error("illegal packet type " .. protocol, true)
                end
            end
        end
    end

    return public
end

return coordinator
