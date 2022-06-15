
local comms = require("scada-common.comms")
local log = require("scada-common.log")
local ppm = require("scada-common.ppm")
local util = require("scada-common.util")

local dialog = require("coordinator.util.dialog")

local coordinator = {}

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local PROTOCOLS = comms.PROTOCOLS
local SCADA_MGMT_TYPES = comms.SCADA_MGMT_TYPES
local COORD_TYPES = comms.COORD_TYPES

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
        unit_displays = {}
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
    end

    return true, monitors
end

-- coordinator communications
---@param conn_watchdog watchdog
function coordinator.coord_comms(version, num_reactors, modem, sv_port, sv_listen, api_listen, conn_watchdog)
    local self = {
        seq_num = 0,
        r_seq_num = nil,
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

    -- send a coordinator packet
    ---@param msg_type COORD_TYPES
    ---@param msg string
    local function _send(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local c_pkt = comms.coord_packet()

        c_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.COORD_DATA, c_pkt.raw_sendable())

        self.modem.transmit(sv_port, sv_listen, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- send a SCADA management packet
    ---@param msg_type SCADA_MGMT_TYPES
    ---@param msg string
    local function _send_mgmt(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.seq_num, PROTOCOLS.SCADA_MGMT, m_pkt.raw_sendable())

        self.modem.transmit(sv_port, sv_listen, s_pkt.raw_sendable())
        self.seq_num = self.seq_num + 1
    end

    -- PUBLIC FUNCTIONS --

    -- reconnect a newly connected modem
    ---@param modem table
---@diagnostic disable-next-line: redefined-local
    function public.reconnect_modem(modem)
        self.modem = modem
        _open_channels()
    end

    -- parse a packet
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return mgmt_frame|coord_frame|capi_frame|nil packet
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
            elseif s_pkt.protocol() == PROTOCOLS.COORD_DATA then
                local coord_pkt = comms.coord_packet()
                if coord_pkt.decode(s_pkt) then
                    pkt = coord_pkt.get()
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
    ---@param packet mgmt_frame|coord_frame|capi_frame
    function public.handle_packet(packet)
        if packet ~= nil then
            -- check sequence number
            if self.r_seq_num == nil then
                self.r_seq_num = packet.scada_frame.seq_num()
            elseif self.connected and self.r_seq_num >= packet.scada_frame.seq_num() then
                log.warning("sequence out-of-order: last = " .. self.r_seq_num .. ", new = " .. packet.scada_frame.seq_num())
                return
            else
                self.r_seq_num = packet.scada_frame.seq_num()
            end

            -- feed watchdog on valid sequence number
            conn_watchdog.feed()

            local protocol = packet.scada_frame.protocol()

            -- handle packet
            if protocol == PROTOCOLS.COORD_DATA then
                if packet.type == COORD_TYPES.ESTABLISH then
                elseif packet.type == COORD_TYPES.QUERY_UNIT then
                elseif packet.type == COORD_TYPES.QUERY_FACILITY then
                elseif packet.type == COORD_TYPES.COMMAND_UNIT then
                elseif packet.type == COORD_TYPES.ALARM then
                else
                    log.warning("received unknown coordinator data packet type " .. packet.type)
                end
            elseif protocol == PROTOCOLS.COORD_API then
            elseif protocol == PROTOCOLS.SCADA_MGMT then
                if packet.type == SCADA_MGMT_TYPES.KEEP_ALIVE then
                    -- keep alive response received
                elseif packet.type == SCADA_MGMT_TYPES.CLOSE then
                    -- handle session close
                    conn_watchdog.cancel()
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

    return public
end

return coordinator
