local comms      = require("scada-common.comms")
local network    = require("scada-common.network")
local ppm        = require("scada-common.ppm")
local rsio       = require("scada-common.rsio")
local tcd        = require("scada-common.tcd")
local util       = require("scada-common.util")

local rtu        = require("rtu.rtu")

local redstone   = require("rtu.config.redstone")

local core       = require("graphics.core")

local Div        = require("graphics.elements.Div")
local ListBox    = require("graphics.elements.ListBox")
local TextBox    = require("graphics.elements.TextBox")

local PushButton = require("graphics.elements.controls.PushButton")

local tri = util.trinary

local cpair = core.cpair

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE = comms.MGMT_TYPE

local self = {
    nic = nil,           ---@type nic
    net_listen = false,
    sv_addr = comms.BROADCAST,
    sv_seq_num = util.time_ms() * 10,

    self_check_pass = true,

    settings = nil,      ---@type rtu_config

    run_test_btn = nil,  ---@type PushButton
    sc_log = nil,        ---@type ListBox
    self_check_msg = nil ---@type function
}

-- report successful completion of the check
local function check_complete()
    TextBox{parent=self.sc_log,text="> all tests passed!",fg_bg=cpair(colors.blue,colors._INHERIT)}
    TextBox{parent=self.sc_log,text=""}
    local more = Div{parent=self.sc_log,height=3,fg_bg=cpair(colors.gray,colors._INHERIT)}
    TextBox{parent=more,text="if you still have a problem:"}
    TextBox{parent=more,text="- check the wiki on GitHub"}
    TextBox{parent=more,text="- ask for help on GitHub discussions or Discord"}
end

-- send a management packet to the supervisor
---@param msg_type MGMT_TYPE
---@param msg table
local function send_sv(msg_type, msg)
    local s_pkt = comms.scada_packet()
    local pkt = comms.mgmt_packet()

    pkt.make(msg_type, msg)
    s_pkt.make(self.sv_addr, self.sv_seq_num, PROTOCOL.SCADA_MGMT, pkt.raw_sendable())

    self.nic.transmit(self.settings.SVR_Channel, self.settings.RTU_Channel, s_pkt)
    self.sv_seq_num = self.sv_seq_num + 1
end

-- handle an establish message from the supervisor
---@param packet mgmt_frame
local function handle_packet(packet)
    local error_msg = nil

    if packet.scada_frame.local_channel() ~= self.settings.RTU_Channel then
        error_msg = "error: unknown receive channel"
    elseif packet.scada_frame.remote_channel() == self.settings.SVR_Channel and packet.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
        if packet.type == MGMT_TYPE.ESTABLISH then
            if packet.length == 1 then
                local est_ack = packet.data[1]

                if est_ack== ESTABLISH_ACK.ALLOW then
                    self.self_check_msg(nil, true, "")
                    self.sv_addr = packet.scada_frame.src_addr()
                    send_sv(MGMT_TYPE.CLOSE, {})
                    if self.self_check_pass then check_complete() end
                elseif est_ack == ESTABLISH_ACK.DENY then
                    error_msg = "error: supervisor connection denied"
                elseif est_ack == ESTABLISH_ACK.BAD_VERSION then
                    error_msg = "RTU gateway comms version does not match supervisor comms version, make sure both devices are up-to-date (ccmsi update)"
                else
                    error_msg = "error: invalid reply from supervisor"
                end
            else
                error_msg = "error: invalid reply length from supervisor"
            end
        else
            error_msg = "error: didn't get an establish reply from supervisor"
        end
    end

    self.net_listen = false
    self.run_test_btn.enable()

    if error_msg then
        self.self_check_msg(nil, false, error_msg)
    end
end

-- handle supervisor connection failure
local function handle_timeout()
    self.net_listen = false
    self.run_test_btn.enable()
    self.self_check_msg(nil, false, "make sure your supervisor is running, your channels are correct, trusted ranges are set properly (if enabled), facility keys match (if set), and if you are using wireless modems rather than ender modems, that your devices are close together in the same dimension")
end


-- check if a value is an integer within a range (inclusive)
---@param x any
---@param min integer
---@param max integer
local function is_int_min_max(x, min, max) return util.is_int(x) and x >= min and x <= max end

-- execute the self-check
local function self_check()
    self.run_test_btn.disable()

    self.sc_log.remove_all()
    ppm.mount_all()

    self.self_check_pass = true

    local cfg = self.settings
    local modem = ppm.get_wireless_modem()
    local valid_cfg = rtu.validate_config(cfg)

    self.self_check_msg("> check wireless/ender modem connected...", modem ~= nil, "you must connect an ender or wireless modem to the RTU gateway")
    self.self_check_msg("> check gateway configuration...", valid_cfg, "go through Configure Gateway and apply settings to set any missing settings and repair any corrupted ones")

    -- check redstone configurations

    local phys = {} ---@type rtu_rs_definition[][]
    local inputs = { [0] = {}, {}, {}, {}, {} }

    for i = 1, #cfg.Redstone do
        local entry = cfg.Redstone[i]
        local name = entry.relay or "local"

        if phys[name] == nil then phys[name] = {} end
        table.insert(phys[entry.relay or "local"], entry)
    end

    for name, entries in pairs(phys) do
        TextBox{parent=self.sc_log,text="> checking redstone @ "..name.."...",fg_bg=cpair(colors.blue,colors.white)}

        local ifaces = {}
        local bundled_sides = {}

        for i = 1, #entries do
            local entry = entries[i]
            local ident = entry.side .. tri(entry.color, ":" .. rsio.color_name(entry.color), "")

            local sc_dupe  = util.table_contains(ifaces, ident)
            local mixed = (bundled_sides[entry.side] and (entry.color == nil)) or (bundled_sides[entry.side] == false and (entry.color ~= nil))

            local mixed_msg = util.trinary(bundled_sides[entry.side], "bundled entry(s) but this entry is not", "non-bundled entry(s) but this entry is")

            self.self_check_msg("> check redstone " .. ident .. " unique...", not sc_dupe, "only one port should be set to a side/color combination")
            self.self_check_msg("> check redstone " .. ident .. " bundle...", not mixed, "this side has " .. mixed_msg .. " bundled, which will not work")
            self.self_check_msg("> check redstone " .. ident .. " valid...", redstone.validate(entry), "configuration invalid, please re-configure redstone entry")

            if rsio.get_io_dir(entry.port) == rsio.IO_DIR.IN then
                local in_dupe = util.table_contains(inputs[entry.unit or 0], entry.port)
                self.self_check_msg("> check redstone " .. ident .. " input...", not in_dupe, "you cannot have multiple of the same input for a given unit or the facility ("..rsio.to_string(entry.port)..")")
            end

            bundled_sides[entry.side] = bundled_sides[entry.side] or entry.color ~= nil
            table.insert(ifaces, ident)
        end
    end

    -- check peripheral configurations
    for i = 1, #cfg.Peripherals do
        local entry = cfg.Peripherals[i]
        local valid = false

        if type(entry.name) == "string" then
            self.self_check_msg("> check " .. entry.name .. " connected...", ppm.get_periph(entry.name), "please connect this device via a wired modem or direct contact and ensure the configuration matches what it connects as")

            local p_type = ppm.get_type(entry.name)

            if p_type == "boilerValve" then
                valid = is_int_min_max(entry.index, 1, 2) and is_int_min_max(entry.unit, 1, 4)
            elseif p_type == "turbineValve" then
                valid = is_int_min_max(entry.index, 1, 3) and is_int_min_max(entry.unit, 1, 4)
            elseif p_type == "solarNeutronActivator" then
                valid = is_int_min_max(entry.unit, 1, 4)
            elseif p_type == "dynamicValve" then
                valid = (entry.unit == nil and is_int_min_max(entry.index, 1, 4)) or is_int_min_max(entry.unit, 1, 4)
            elseif p_type == "environmentDetector" then
                valid = (entry.unit == nil or is_int_min_max(entry.unit, 1, 4)) and util.is_int(entry.index)
            else
                valid = true

                if p_type ~= nil and not (p_type == "inductionPort" or p_type == "spsPort") then
                    self.self_check_msg("> check " .. entry.name .. " valid...", false, "unrecognized device type")
                end
            end
        end

        if not valid then
            self.self_check_msg("> check " .. entry.name .. " valid...", false, "configuration invalid, please re-configure peripheral entry")
        end
    end

    if valid_cfg and modem then
        self.self_check_msg("> check supervisor connection...")

        -- init mac as needed
        if cfg.AuthKey and string.len(cfg.AuthKey) >= 8 then
            network.init_mac(cfg.AuthKey)
        else
            network.deinit_mac()
        end

        self.nic = network.nic(modem)

        self.nic.closeAll()
        self.nic.open(cfg.RTU_Channel)

        self.sv_addr = comms.BROADCAST
        self.net_listen = true

        send_sv(MGMT_TYPE.ESTABLISH, { comms.version, "0.0.0", DEVICE_TYPE.RTU, {} })

        tcd.dispatch_unique(8, handle_timeout)
    else
        if self.self_check_pass then check_complete() end
        self.run_test_btn.enable()
    end
end

-- exit self check back home
---@param main_pane MultiPane
local function exit_self_check(main_pane)
    tcd.abort(handle_timeout)
    self.net_listen = false
    self.run_test_btn.enable()
    self.sc_log.remove_all()
    main_pane.set_value(1)
end

local check = {}

-- create the self-check view
---@param main_pane MultiPane
---@param settings_cfg rtu_config
---@param check_sys Div
---@param style { [string]: cpair }
function check.create(main_pane, settings_cfg, check_sys, style)
    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    self.settings = settings_cfg

    local sc = Div{parent=check_sys,x=2,y=4,width=49}

    TextBox{parent=check_sys,x=1,y=2,text=" RTU Gateway Self-Check",fg_bg=bw_fg_bg}

    self.sc_log = ListBox{parent=sc,x=1,y=1,height=12,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local last_check = { nil, nil }

    function self.self_check_msg(msg, success, fail_msg)
        if type(msg) == "string" then
            last_check[1] = Div{parent=self.sc_log,height=1}
            local e = TextBox{parent=last_check[1],text=msg,fg_bg=bw_fg_bg}
            last_check[2] = e.get_x()+string.len(msg)
        end

        if type(fail_msg) == "string" then
            TextBox{parent=last_check[1],x=last_check[2],y=1,text=tri(success,"PASS","FAIL"),fg_bg=tri(success,cpair(colors.green,colors._INHERIT),cpair(colors.red,colors._INHERIT))}

            if not success then
                local fail = Div{parent=self.sc_log,height=#util.strwrap(fail_msg, 46)}
                TextBox{parent=fail,x=3,text=fail_msg,fg_bg=cpair(colors.gray,colors.white)}
            end

            self.self_check_pass = self.self_check_pass and success
        end
    end

    PushButton{parent=sc,x=1,y=14,text="\x1b Back",callback=function()exit_self_check(main_pane)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    self.run_test_btn = PushButton{parent=sc,x=40,y=14,min_width=10,text="Run Test",callback=function()self_check()end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
end

-- handle incoming modem messages
---@param side string
---@param sender integer
---@param reply_to integer
---@param message any
---@param distance integer
function check.receive_sv(side, sender, reply_to, message, distance)
    if self.nic ~= nil and self.net_listen then
        local s_pkt = self.nic.receive(side, sender, reply_to, message, distance)

        if s_pkt and s_pkt.protocol() == PROTOCOL.SCADA_MGMT then
            local mgmt_pkt = comms.mgmt_packet()
            if mgmt_pkt.decode(s_pkt) then
                tcd.abort(handle_timeout)
                handle_packet(mgmt_pkt.get())
            end
        end
    end
end

return check
