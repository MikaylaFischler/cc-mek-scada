local comms       = require("scada-common.comms")
local network     = require("scada-common.network")
local ppm         = require("scada-common.ppm")
local tcd         = require("scada-common.tcd")
local util        = require("scada-common.util")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local PushButton  = require("graphics.elements.controls.PushButton")

local NumberField = require("graphics.elements.form.NumberField")

local tri = util.trinary

local cpair = core.cpair

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE = comms.MGMT_TYPE

local self = {
    nic = nil,            ---@type nic
    net_listen = false,
    sv_addr = comms.BROADCAST,
    sv_seq_num = util.time_ms() * 10,
    show_sv_cfg = nil,    ---@type function

    sv_conn_button = nil, ---@type PushButton
    sv_conn_status = nil, ---@type TextBox
    sv_conn_detail = nil, ---@type TextBox
    sv_next = nil,        ---@type PushButton
    sv_skip = nil,        ---@type PushButton

    tool_ctl = nil,       ---@type _crd_cfg_tool_ctl
    tmp_cfg = nil         ---@type crd_config
}

-- check if a value is an integer within a range (inclusive)
---@param x any
---@param min integer
---@param max integer
local function is_int_min_max(x, min, max) return util.is_int(x) and x >= min and x <= max end

-- send a management packet to the supervisor
---@param msg_type MGMT_TYPE
---@param msg table
local function send_sv(msg_type, msg)
    local s_pkt = comms.scada_packet()
    local pkt = comms.mgmt_packet()

    pkt.make(msg_type, msg)
    s_pkt.make(self.sv_addr, self.sv_seq_num, PROTOCOL.SCADA_MGMT, pkt.raw_sendable())

    self.nic.transmit(self.tmp_cfg.SVR_Channel, self.tmp_cfg.CRD_Channel, s_pkt)
    self.sv_seq_num = self.sv_seq_num + 1
end

-- handle an establish message from the supervisor
---@param packet mgmt_frame
local function handle_packet(packet)
    local error_msg = nil

    if packet.scada_frame.local_channel() ~= self.tmp_cfg.CRD_Channel then
        error_msg = "Error: unknown receive channel."
    elseif packet.scada_frame.remote_channel() == self.tmp_cfg.SVR_Channel and packet.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
        if packet.type == MGMT_TYPE.ESTABLISH then
            if packet.length == 2 then
                local est_ack = packet.data[1]
                local config = packet.data[2]

                if est_ack == ESTABLISH_ACK.ALLOW then
                    if type(config) == "table" and #config == 2 then
                        local count_ok = is_int_min_max(config[1], 1, 4)
                        local cool_ok = type(config[2]) == "table" and type(config[2].r_cool) == "table" and #config[2].r_cool == config[1]

                        if count_ok and cool_ok then
                            self.tmp_cfg.UnitCount = config[1]
                            self.tool_ctl.sv_cool_conf = {}

                            for i = 1, self.tmp_cfg.UnitCount do
                                local num_b = config[2].r_cool[i].BoilerCount
                                local num_t = config[2].r_cool[i].TurbineCount
                                self.tool_ctl.sv_cool_conf[i] = { num_b, num_t }
                                cool_ok = cool_ok and is_int_min_max(num_b, 0, 2) and is_int_min_max(num_t, 1, 3)
                            end
                        end

                        if not count_ok then
                            error_msg = "Error: supervisor unit count out of range."
                        elseif not cool_ok then
                            error_msg = "Error: supervisor cooling configuration malformed."
                            self.tool_ctl.sv_cool_conf = nil
                        end

                        self.sv_addr = packet.scada_frame.src_addr()
                        send_sv(MGMT_TYPE.CLOSE, {})
                    else
                        error_msg = "Error: invalid cooling configuration supervisor."
                    end
                else
                    error_msg = "Error: invalid allow reply length from supervisor."
                end
            elseif packet.length == 1 then
                local est_ack = packet.data[1]

                if est_ack == ESTABLISH_ACK.DENY then
                    error_msg = "Error: supervisor connection denied."
                elseif est_ack == ESTABLISH_ACK.COLLISION then
                    error_msg = "Error: a coordinator is already/still connected. Please try again."
                elseif est_ack == ESTABLISH_ACK.BAD_VERSION then
                    error_msg = "Error: coordinator comms version does not match supervisor comms version."
                else
                    error_msg = "Error: invalid reply from supervisor."
                end
            else
                error_msg = "Error: invalid reply length from supervisor."
            end
        else
            error_msg = "Error: didn't get an establish reply from supervisor."
        end
    end

    self.net_listen = false

    if error_msg then
        self.sv_conn_status.set_value("")
        self.sv_conn_detail.set_value(error_msg)
        self.sv_conn_button.enable()
    else
        self.sv_conn_status.set_value("Connected!")
        self.sv_conn_detail.set_value("Data received successfully, press 'Next' to continue.")
        self.sv_skip.hide()
        self.sv_next.show()
    end
end

-- handle supervisor connection failure
local function handle_timeout()
    self.net_listen = false
    self.sv_conn_button.enable()
    self.sv_conn_status.set_value("Timed out.")
    self.sv_conn_detail.set_value("Supervisor did not reply. Ensure startup app is running on the supervisor.")
end

-- attempt a connection to the supervisor to get cooling info
local function sv_connect()
    self.sv_conn_button.disable()
    self.sv_conn_detail.set_value("")

    local modem = ppm.get_wireless_modem()
    if modem == nil then
        self.sv_conn_status.set_value("Please connect an ender/wireless modem.")
    else
        self.sv_conn_status.set_value("Modem found, connecting...")
        if self.nic == nil then self.nic = network.nic(modem) end

        self.nic.closeAll()
        self.nic.open(self.tmp_cfg.CRD_Channel)

        self.sv_addr = comms.BROADCAST
        self.net_listen = true

        send_sv(MGMT_TYPE.ESTABLISH, { comms.version, "0.0.0", DEVICE_TYPE.CRD })

        tcd.dispatch_unique(8, handle_timeout)
    end
end

local facility = {}

-- create the facility configuration view
---@param tool_ctl _crd_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ crd_config, crd_config, crd_config, { [1]: string, [2]: string, [3]: any }[], function ]
---@param fac_cfg Div
---@param style { [string]: cpair }
---@return MultiPane fac_pane
function facility.create(tool_ctl, main_pane, cfg_sys, fac_cfg, style)
    local _, ini_cfg, tmp_cfg, _, _ = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]

    self.tmp_cfg = tmp_cfg
    self.tool_ctl = tool_ctl

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    --#region Facility

    local fac_c_1 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_2 = Div{parent=fac_cfg,x=2,y=4,width=49}
    local fac_c_3 = Div{parent=fac_cfg,x=2,y=4,width=49}

    local fac_pane = MultiPane{parent=fac_cfg,x=1,y=4,panes={fac_c_1,fac_c_2,fac_c_3}}

    TextBox{parent=fac_cfg,x=1,y=2,text=" Facility Configuration",fg_bg=cpair(colors.black,colors.yellow)}

    TextBox{parent=fac_c_1,x=1,y=1,height=4,text="This tool can attempt to connect to your supervisor computer. This would load facility information in order to get the unit count and aid monitor setup."}
    TextBox{parent=fac_c_1,x=1,y=6,height=2,text="The supervisor startup app must be running and fully configured on your supervisor computer."}

    self.sv_conn_status = TextBox{parent=fac_c_1,x=11,y=9,text=""}
    self.sv_conn_detail = TextBox{parent=fac_c_1,x=1,y=11,height=2,text=""}

    self.sv_conn_button = PushButton{parent=fac_c_1,x=1,y=9,text="Connect",min_width=9,callback=function()sv_connect()end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}

    local function sv_skip()
        tcd.abort(handle_timeout)
        tool_ctl.sv_cool_conf = nil
        self.net_listen = false
        fac_pane.set_value(2)
    end

    local function sv_next()
        self.show_sv_cfg()
        tool_ctl.update_mon_reqs()
        fac_pane.set_value(3)
    end

    PushButton{parent=fac_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    self.sv_skip = PushButton{parent=fac_c_1,x=44,y=14,text="Skip \x1a",callback=sv_skip,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    self.sv_next = PushButton{parent=fac_c_1,x=44,y=14,text="Next \x1a",callback=sv_next,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,hidden=true}

    TextBox{parent=fac_c_2,x=1,y=1,height=3,text="Please enter the number of reactors you have, also referred to as reactor units or 'units' for short. A maximum of 4 is currently supported."}
    tool_ctl.num_units = NumberField{parent=fac_c_2,x=1,y=5,width=5,max_chars=2,default=ini_cfg.UnitCount,min=1,max=4,fg_bg=bw_fg_bg}
    TextBox{parent=fac_c_2,x=7,y=5,text="reactors"}
    TextBox{parent=fac_c_2,x=1,y=7,height=3,text="This will decide how many monitors you need. If this does not match the supervisor's number of reactor units, the coordinator will not connect.",fg_bg=g_lg_fg_bg}
    TextBox{parent=fac_c_2,x=1,y=10,height=3,text="Since you skipped supervisor sync, the main monitor minimum height can't be determined precisely. It is marked with * on the next page.",fg_bg=g_lg_fg_bg}

    local nu_error = TextBox{parent=fac_c_2,x=8,y=14,width=35,text="Please set the number of reactors.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_num_units()
        local count = tonumber(tool_ctl.num_units.get_value())
        if count ~= nil and count > 0 and count < 5 then
            nu_error.hide(true)
            tmp_cfg.UnitCount = count
            tool_ctl.update_mon_reqs()
            main_pane.set_value(4)
        else nu_error.show() end
    end

    PushButton{parent=fac_c_2,x=1,y=14,text="\x1b Back",callback=function()fac_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_2,x=44,y=14,text="Next \x1a",callback=submit_num_units,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=fac_c_3,x=1,y=1,height=2,text="The following facility configuration was fetched from your supervisor computer."}

    local fac_config_list = ListBox{parent=fac_c_3,x=1,y=4,height=9,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    PushButton{parent=fac_c_3,x=1,y=14,text="\x1b Back",callback=function()fac_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=fac_c_3,x=44,y=14,text="Next \x1a",callback=function()main_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Tool and Helper Functions

    tool_ctl.is_int_min_max = is_int_min_max

    -- reset the connection display for a new attempt
    function tool_ctl.init_sv_connect_ui()
        self.sv_next.hide()
        self.sv_skip.disable()
        self.sv_skip.show()
        self.sv_conn_button.enable()
        self.sv_conn_status.set_value("")
        self.sv_conn_detail.set_value("")

        -- the user needs to wait a few seconds, encouraging the to connect
        tcd.dispatch_unique(2, function () self.sv_skip.enable() end)
    end

    -- show the facility's unit count and cooling configuration data
    function self.show_sv_cfg()
        local conf = tool_ctl.sv_cool_conf
        fac_config_list.remove_all()

        local str = util.sprintf("Facility has %d reactor unit%s:", #conf, tri(#conf==1,"","s"))
        TextBox{parent=fac_config_list,text=str,fg_bg=cpair(colors.gray,colors.white)}

        for i = 1, #conf do
            local num_b, num_t = conf[i][1], conf[i][2]
            str = util.sprintf("\x07 Unit %d has %d boiler%s and %d turbine%s", i, num_b, tri(num_b == 1, "", "s"), num_t, tri(num_t == 1, "", "s"))
            TextBox{parent=fac_config_list,text=str,fg_bg=cpair(colors.gray,colors.white)}
        end
    end

    --#endregion

    return fac_pane
end

-- handle incoming modem messages
---@param side string
---@param sender integer
---@param reply_to integer
---@param message any
---@param distance integer
function facility.receive_sv(side, sender, reply_to, message, distance)
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

return facility
