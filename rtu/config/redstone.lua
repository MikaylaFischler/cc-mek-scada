local constants   = require("scada-common.constants")
local ppm         = require("scada-common.ppm")
local rsio        = require("scada-common.rsio")
local util        = require("scada-common.util")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local Checkbox    = require("graphics.elements.controls.Checkbox")
local PushButton  = require("graphics.elements.controls.PushButton")
local Radio2D     = require("graphics.elements.controls.Radio2D")

local NumberField = require("graphics.elements.form.NumberField")

---@class rtu_rs_definition
---@field unit integer|nil
---@field port IO_PORT
---@field relay string|nil
---@field side side
---@field color color|nil
---@field invert true|nil

local tri = util.trinary

local cpair = core.cpair

local IO = rsio.IO
local IO_LVL = rsio.IO_LVL
local IO_MODE = rsio.IO_MODE

local LEFT = core.ALIGN.LEFT

local self = {
    rs_cfg_phy = false,     ---@type string|nil|false
    rs_cfg_port = 1,        ---@type IO_PORT
    rs_cfg_editing = false, ---@type integer|false

    rs_cfg_selection = nil, ---@type TextBox
    rs_cfg_unit_l = nil,    ---@type TextBox
    rs_cfg_unit = nil,      ---@type NumberField
    rs_cfg_side_l = nil,    ---@type TextBox
    rs_cfg_bundled = nil,   ---@type Checkbox
    rs_cfg_color = nil,     ---@type Radio2D
    rs_cfg_inverted = nil,  ---@type Checkbox
    rs_cfg_shortcut = nil,  ---@type TextBox
    rs_cfg_advanced = nil   ---@type PushButton
}

-- rsio port descriptions
local PORT_DESC_MAP = {
    { IO.F_SCRAM, "Facility SCRAM" },
    { IO.F_ACK, "Facility Acknowledge" },
    { IO.R_SCRAM, "Reactor SCRAM" },
    { IO.R_RESET, "Reactor RPS Reset" },
    { IO.R_ENABLE, "Reactor Enable" },
    { IO.U_ACK, "Unit Acknowledge" },
    { IO.F_ALARM, "Facility Alarm (high prio)" },
    { IO.F_ALARM_ANY, "Facility Alarm (any)" },
    { IO.F_MATRIX_LOW, "Induction Matrix < " .. (100 * constants.RS_THRESHOLDS.IMATRIX_CHARGE_LOW) .. "%" },
    { IO.F_MATRIX_HIGH, "Induction Matrix > " .. (100 * constants.RS_THRESHOLDS.IMATRIX_CHARGE_HIGH) .. "%" },
    { IO.F_MATRIX_CHG, "Induction Matrix Charge %" },
    { IO.WASTE_PU, "Waste Plutonium Valve" },
    { IO.WASTE_PO, "Waste Polonium Valve" },
    { IO.WASTE_POPL, "Waste Po Pellets Valve" },
    { IO.WASTE_AM, "Waste Antimatter Valve" },
    { IO.R_ACTIVE, "Reactor Active" },
    { IO.R_AUTO_CTRL, "Reactor in Auto Control" },
    { IO.R_SCRAMMED, "RPS Tripped" },
    { IO.R_AUTO_SCRAM, "RPS Auto SCRAM" },
    { IO.R_HIGH_DMG, "RPS High Damage" },
    { IO.R_HIGH_TEMP, "RPS High Temperature" },
    { IO.R_LOW_COOLANT, "RPS Low Coolant" },
    { IO.R_EXCESS_HC, "RPS Excess Heated Coolant" },
    { IO.R_EXCESS_WS, "RPS Excess Waste" },
    { IO.R_INSUFF_FUEL, "RPS Insufficient Fuel" },
    { IO.R_PLC_FAULT, "RPS PLC Fault" },
    { IO.R_PLC_TIMEOUT, "RPS Supervisor Timeout" },
    { IO.U_ALARM, "Unit Alarm" },
    { IO.U_EMER_COOL, "Unit Emergency Cool. Valve" },
    { IO.U_AUX_COOL, "Unit Auxiliary Cool. Valve" }
}

-- designation (0 = facility, 1 = unit)
local PORT_DSGN = { [-1] = 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1 }

assert(#PORT_DESC_MAP == rsio.NUM_PORTS)
assert(#PORT_DSGN == rsio.NUM_PORTS)

local side_options = { "Top", "Bottom", "Left", "Right", "Front", "Back" }
local side_options_map = { "top", "bottom", "left", "right", "front", "back" }
local color_options = { "Red", "Orange", "Yellow", "Lime", "Green", "Cyan", "Light Blue", "Blue", "Purple", "Magenta", "Pink", "White", "Light Gray", "Gray", "Black", "Brown" }
local color_options_map = { colors.red, colors.orange, colors.yellow, colors.lime, colors.green, colors.cyan, colors.lightBlue, colors.blue, colors.purple, colors.magenta, colors.pink, colors.white, colors.lightGray, colors.gray, colors.black, colors.brown }

-- convert text representation to index
---@param side string
local function side_to_idx(side)
    for k, v in ipairs(side_options_map) do
        if v == side then return k end
    end
end

-- convert color to index
---@param color color
local function color_to_idx(color)
    for k, v in ipairs(color_options_map) do
        if v == color then return k end
    end
end

-- select the subset of redstone entries assigned to the given phy
---@param cfg rtu_rs_definition[] the full redstone entry list
---@param phy string|nil which phy to get redstone entries for
---@param invert boolean? true to get all except this phy
---@return rtu_rs_definition[]
local function redstone_subset(cfg, phy, invert)
    local subset = {}

    for i = 1, #cfg do
        if ((not invert) and cfg[i].relay == phy) or (invert and cfg[i].relay ~= phy) then
            table.insert(subset, cfg[i])
        end
    end

    return subset
end

local redstone = {}

-- validate a redstone entry
---@param def rtu_rs_definition
function redstone.validate(def)
    return tri(PORT_DSGN[def.port] == 1, util.is_int(def.unit) and def.unit > 0 and def.unit <= 4, def.unit == nil) and
           rsio.is_valid_port(def.port) and
           rsio.is_valid_side(def.side) and
           (def.color == nil or (rsio.is_digital(def.port) and rsio.is_color(def.color)))
end

-- create the redstone configuration view
---@param tool_ctl _rtu_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ rtu_config, rtu_config, rtu_config, table, function ]
---@param rs_cfg Div
---@param style { [string]: cpair }
---@return MultiPane rs_pane
function redstone.create(tool_ctl, main_pane, cfg_sys, rs_cfg, style)
    local settings_cfg, ini_cfg, tmp_cfg, _, load_settings = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    --#region Redstone

    local rs_c_1  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_2  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_3  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_4  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_5  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_6  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_7  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_8  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_9  = Div{parent=rs_cfg,x=2,y=4,width=49}
    local rs_c_10 = Div{parent=rs_cfg,x=2,y=4,width=49}

    local rs_pane = MultiPane{parent=rs_cfg,x=1,y=4,panes={rs_c_1,rs_c_2,rs_c_3,rs_c_4,rs_c_5,rs_c_6,rs_c_7,rs_c_8,rs_c_9,rs_c_10}}

    local header = TextBox{parent=rs_cfg,x=1,y=2,text=" Redstone Connections",fg_bg=cpair(colors.black,colors.red)}

    --#region Interface Selection

    TextBox{parent=rs_c_1,x=1,y=1,text="Configure this computer or a redstone relay."}
    local iface_list = ListBox{parent=rs_c_1,x=1,y=3,height=10,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    -- update relay interface list
    function tool_ctl.update_relay_list()
        local mounts = ppm.list_mounts()

        iface_list.remove_all()

        -- assemble list of configured relays
        local relays = {}
        for i = 1, #tmp_cfg.Redstone do
            local def = tmp_cfg.Redstone[i]
            if def.relay and not util.table_contains(relays, def.relay) then
                table.insert(relays, def.relay)
            end
        end

        -- add unconfigured connected relays
        for name, entry in pairs(mounts) do
            if entry.type == "redstone_relay" and not util.table_contains(relays, name) then
                table.insert(relays, name)
            end
        end

        local function config_rs(name)
            header.set_value(" Redstone Connections (" .. name .. ")")

            self.rs_cfg_phy = tri(name == "local", nil, name)

            tool_ctl.gen_rs_summary()
            rs_pane.set_value(2)
        end

        local line = Div{parent=iface_list,height=2,fg_bg=cpair(colors.black,colors.white)}
        TextBox{parent=line,x=1,y=1,text="@ local",fg_bg=cpair(colors.black,colors.white)}
        TextBox{parent=line,x=3,y=2,text="This Computer",fg_bg=cpair(colors.gray,colors.white)}
        local count = #redstone_subset(ini_cfg.Redstone, nil)
        TextBox{parent=line,x=33,y=2,width=16,alignment=core.ALIGN.RIGHT,text=count.." connections",fg_bg=cpair(colors.gray,colors.white)}

        PushButton{parent=line,x=41,y=1,min_width=8,height=1,text="CONFIG",callback=function()config_rs("local")end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}

        for i = 1, #relays do
            local name = relays[i]

            line = Div{parent=iface_list,height=2,fg_bg=cpair(colors.black,colors.white)}
            TextBox{parent=line,x=1,y=1,text="@ "..name,fg_bg=cpair(colors.black,colors.white)}
            TextBox{parent=line,x=3,y=2,text="Redstone Relay",fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=line,x=18,y=2,text=tri(mounts[name],"ONLINE","OFFLINE"),fg_bg=cpair(tri(mounts[name],colors.green,colors.red),colors.white)}
            count = #redstone_subset(ini_cfg.Redstone, name)
            TextBox{parent=line,x=33,y=2,width=16,alignment=core.ALIGN.RIGHT,text=count.." connections",fg_bg=cpair(colors.gray,colors.white)}

            PushButton{parent=line,x=41,y=1,min_width=8,height=1,text="CONFIG",callback=function()config_rs(name)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
        end
    end

    tool_ctl.update_relay_list()

    PushButton{parent=rs_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_1,x=27,y=14,min_width=23,text="I don't see my relay!",callback=function()rs_pane.set_value(10)end,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Configuration List

    TextBox{parent=rs_c_2,x=1,y=1,text=" port          side/color       unit/facility",fg_bg=g_lg_fg_bg}
    local rs_list = ListBox{parent=rs_c_2,x=1,y=2,height=11,width=49,scroll_height=200,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function rs_revert()
        tmp_cfg.Redstone = tool_ctl.deep_copy_rs(ini_cfg.Redstone)
        tool_ctl.gen_rs_summary()
    end

    local function rs_apply()
        -- add the changed data to the existing saved data
        local new_data = redstone_subset(tmp_cfg.Redstone, self.rs_cfg_phy)
        local new_save = redstone_subset(ini_cfg.Redstone, self.rs_cfg_phy, true)
        for i = 1, #new_data do table.insert(new_save, new_data[i]) end

        settings.set("Redstone", new_save)

        if settings.save("/rtu.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)
            rs_pane.set_value(5)

            -- for return to list from saved screen
            -- this will delete unsaved changes for other phy's, which is acceptable
            tmp_cfg.Redstone = tool_ctl.deep_copy_rs(ini_cfg.Redstone)
            tool_ctl.gen_rs_summary()
            tool_ctl.update_relay_list()
        else
            rs_pane.set_value(6)
        end
    end

    local function rs_back()
        self.rs_cfg_phy = false
        rs_pane.set_value(1)
        header.set_value(" Redstone Connections")
    end

    PushButton{parent=rs_c_2,x=1,y=14,text="\x1b Back",callback=rs_back,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    local rs_revert_btn = PushButton{parent=rs_c_2,x=8,y=14,min_width=16,text="Revert Changes",callback=rs_revert,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    PushButton{parent=rs_c_2,x=35,y=14,min_width=7,text="New +",callback=function()rs_pane.set_value(3)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    local rs_apply_btn = PushButton{parent=rs_c_2,x=43,y=14,min_width=7,text="Apply",callback=rs_apply,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}

    --#endregion
    --#region Port Selection

    TextBox{parent=rs_c_3,x=1,y=1,text="Select one of the below ports to use."}

    local rs_ports = ListBox{parent=rs_c_3,x=1,y=3,height=10,width=49,scroll_height=200,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function new_rs(port)
        self.rs_cfg_editing = false

        local text

        if port == -1 then
            self.rs_cfg_color.hide(true)
            self.rs_cfg_shortcut.show()
            self.rs_cfg_side_l.set_value("Output Side")
            self.rs_cfg_bundled.enable()
            self.rs_cfg_advanced.disable()
            text = "You selected the ALL_WASTE shortcut."
        else
            self.rs_cfg_shortcut.hide(true)
            self.rs_cfg_side_l.set_value(tri(rsio.get_io_dir(port) == rsio.IO_DIR.IN, "Input Side", "Output Side"))
            self.rs_cfg_color.show()

            local io_type = "analog input "
            local io_mode = rsio.get_io_mode(port)
            local inv = tri(rsio.digital_is_active(port, IO_LVL.LOW) == true, "inverted ", "")

            if rsio.is_analog(port) then
                self.rs_cfg_bundled.set_value(false)
                self.rs_cfg_bundled.disable()
                self.rs_cfg_color.disable()
                self.rs_cfg_inverted.set_value(false)
                self.rs_cfg_advanced.disable()
            else
                self.rs_cfg_bundled.enable()
                if self.rs_cfg_bundled.get_value() then self.rs_cfg_color.enable() else self.rs_cfg_color.disable() end
                self.rs_cfg_inverted.set_value(false)
                self.rs_cfg_advanced.enable()
            end

            if io_mode == IO_MODE.DIGITAL_IN then
                io_type = inv .. "digital input "
            elseif io_mode == IO_MODE.DIGITAL_OUT then
                io_type = inv .. "digital output "
            elseif io_mode == IO_MODE.ANALOG_OUT then
                io_type = "analog output "
            end

            text = "You selected the " .. io_type .. rsio.to_string(port) .. " (for "

            if PORT_DSGN[port] == 1 then
                text = text .. "a unit)."
                self.rs_cfg_unit_l.show()
                self.rs_cfg_unit.show()
            else
                self.rs_cfg_unit_l.hide(true)
                self.rs_cfg_unit.hide(true)
                text = text .. "the facility)."
            end
        end

        self.rs_cfg_selection.set_value(text)
        self.rs_cfg_port = port
        rs_pane.set_value(4)
    end

    -- add entries to redstone option list
    local all_w_macro = Div{parent=rs_ports,height=1}
    PushButton{parent=all_w_macro,x=1,y=1,min_width=14,alignment=LEFT,height=1,text=">ALL_WASTE",callback=function()new_rs(-1)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.black)}
    TextBox{parent=all_w_macro,x=16,y=1,width=5,text="[n/a]",fg_bg=cpair(colors.lightGray,colors.white)}
    TextBox{parent=all_w_macro,x=22,y=1,text="Create all 4 waste entries",fg_bg=cpair(colors.gray,colors.white)}

    for i = 1, rsio.NUM_PORTS do
        local p = PORT_DESC_MAP[i][1]
        local name = rsio.to_string(p)
        local io_dir = tri(rsio.get_io_dir(p) == rsio.IO_DIR.IN, "[in]", "[out]")
        local btn_color = tri(rsio.get_io_dir(p) == rsio.IO_DIR.IN, colors.yellow, colors.lightBlue)

        local entry = Div{parent=rs_ports,height=1}
        PushButton{parent=entry,x=1,y=1,min_width=14,alignment=LEFT,height=1,text=">"..name,callback=function()new_rs(p)end,fg_bg=cpair(colors.black,btn_color),active_fg_bg=cpair(colors.white,colors.black)}
        TextBox{parent=entry,x=16,y=1,width=5,text=io_dir,fg_bg=cpair(colors.lightGray,colors.white)}
        TextBox{parent=entry,x=22,y=1,text=PORT_DESC_MAP[i][2],fg_bg=cpair(colors.gray,colors.white)}
    end

    PushButton{parent=rs_c_3,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion
    --#region Port Configuration

    self.rs_cfg_selection = TextBox{parent=rs_c_4,x=1,y=1,height=2,text=""}

    PushButton{parent=rs_c_4,x=36,y=3,text="What's that?",min_width=14,callback=function()rs_pane.set_value(8)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    self.rs_cfg_side_l = TextBox{parent=rs_c_4,x=1,y=4,width=11,text="Output Side"}
    local side = Radio2D{parent=rs_c_4,x=1,y=5,rows=1,columns=6,default=1,options=side_options,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.red}

    self.rs_cfg_unit_l = TextBox{parent=rs_c_4,x=25,y=7,width=7,text="Unit ID"}
    self.rs_cfg_unit = NumberField{parent=rs_c_4,x=33,y=7,width=10,max_chars=2,min=1,max=4,fg_bg=bw_fg_bg}

    local function set_bundled(bundled)
        if bundled then self.rs_cfg_color.enable() else self.rs_cfg_color.disable() end
    end

    self.rs_cfg_shortcut = TextBox{parent=rs_c_4,x=1,y=9,height=4,text="This shortcut will add entries for each of the 4 waste outputs. If you select bundled, 4 colors will be assigned to the selected side. Otherwise, 4 default sides will be used."}
    self.rs_cfg_shortcut.hide(true)

    self.rs_cfg_bundled = Checkbox{parent=rs_c_4,x=1,y=7,label="Is Bundled?",default=false,box_fg_bg=cpair(colors.red,colors.black),callback=set_bundled,disable_fg_bg=g_lg_fg_bg}
    self.rs_cfg_color = Radio2D{parent=rs_c_4,x=1,y=9,rows=4,columns=4,default=1,options=color_options,radio_colors=cpair(colors.lightGray,colors.black),color_map=color_options_map,disable_color=colors.gray,disable_fg_bg=g_lg_fg_bg}
    self.rs_cfg_color.disable()

    local rs_err = TextBox{parent=rs_c_4,x=8,y=14,width=30,text="Unit ID invalid.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
    rs_err.hide(true)

    local function back_from_rs_opts()
        rs_err.hide(true)
        if self.rs_cfg_editing ~= false then rs_pane.set_value(2) else rs_pane.set_value(3) end
    end

    local function save_rs_entry()
        assert(self.rs_cfg_phy ~= false, "tried to save a redstone entry without a phy")

        local port = self.rs_cfg_port
        local u = tonumber(self.rs_cfg_unit.get_value())

        if PORT_DSGN[port] == 0 or (util.is_int(u) and u > 0 and u < 5) then
            rs_err.hide(true)

            if port >= 0 then
                ---@type rtu_rs_definition
                local def = {
                    unit = tri(PORT_DSGN[port] == 1, u, nil),
                    port = port,
                    relay = self.rs_cfg_phy,
                    side = side_options_map[side.get_value()],
                    color = tri(self.rs_cfg_bundled.get_value() and rsio.is_digital(port), color_options_map[self.rs_cfg_color.get_value()], nil),
                    invert = self.rs_cfg_inverted.get_value() or nil
                }

                if self.rs_cfg_editing == false then
                    -- check for duplicate inputs for this unit/facility
                    if (rsio.get_io_dir(port) == rsio.IO_DIR.IN) then
                        for i = 1, #tmp_cfg.Redstone do
                            if tmp_cfg.Redstone[i].port == port and tmp_cfg.Redstone[i].unit == def.unit then
                                rs_pane.set_value(7)
                                return
                            end
                        end
                    end

                    table.insert(tmp_cfg.Redstone, def)
                else
                    def.port = tmp_cfg.Redstone[self.rs_cfg_editing].port
                    tmp_cfg.Redstone[self.rs_cfg_editing] = def
                end
            elseif port == -1 then
                local default_sides = { "left", "back", "right", "front" }
                local default_colors = { colors.red, colors.orange, colors.yellow, colors.lime }
                for i = 0, 3 do
                    table.insert(tmp_cfg.Redstone, {
                        unit = tri(PORT_DSGN[IO.WASTE_PU + i] == 1, u, nil),
                        port = IO.WASTE_PU + i,
                        relay = self.rs_cfg_phy,
                        side = tri(self.rs_cfg_bundled.get_value(), side_options_map[side.get_value()], default_sides[i + 1]),
                        color = tri(self.rs_cfg_bundled.get_value(), default_colors[i + 1], nil)
                    })
                end
            end

            rs_pane.set_value(2)
            tool_ctl.gen_rs_summary()

            side.set_value(1)
            self.rs_cfg_bundled.set_value(false)
            self.rs_cfg_color.set_value(1)
            self.rs_cfg_color.disable()
            self.rs_cfg_inverted.set_value(false)
            self.rs_cfg_advanced.disable()
        else rs_err.show() end
    end

    PushButton{parent=rs_c_4,x=1,y=14,text="\x1b Back",callback=back_from_rs_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    self.rs_cfg_advanced = PushButton{parent=rs_c_4,x=30,y=14,min_width=10,text="Advanced",callback=function()rs_pane.set_value(9)end,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    PushButton{parent=rs_c_4,x=41,y=14,min_width=9,text="Confirm",callback=save_rs_entry,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}

    --#endregion

    TextBox{parent=rs_c_5,x=1,y=1,text="Settings saved!"}
    PushButton{parent=rs_c_5,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_5,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_6,x=1,y=1,height=5,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=rs_c_6,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=rs_c_6,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_7,x=1,y=1,height=6,text="You already configured this input for this facility/unit assignment. There can only be one entry for each input per each unit or the facility (for facility inputs).\n\nPlease select a different port."}
    PushButton{parent=rs_c_7,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_8,x=1,y=1,height=4,text="(Normal) Digital Input: On if there is a redstone signal, off otherwise\nInverted Digital Input: On without a redstone signal, off otherwise"}
    TextBox{parent=rs_c_8,x=1,y=6,height=4,text="(Normal) Digital Output: Redstone signal to 'turn it on', none to 'turn it off'\nInverted Digital Output: No redstone signal to 'turn it on', redstone signal to 'turn it off'"}
    TextBox{parent=rs_c_8,x=1,y=11,height=2,text="Analog Input: 0-15 redstone power level input\nAnalog Output: 0-15 scaled redstone power level output"}
    PushButton{parent=rs_c_8,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_9,x=1,y=1,height=5,text="Advanced Options"}
    self.rs_cfg_inverted = Checkbox{parent=rs_c_9,x=1,y=3,label="Invert",default=false,box_fg_bg=cpair(colors.red,colors.black),callback=function()end,disable_fg_bg=g_lg_fg_bg}
    TextBox{parent=rs_c_9,x=3,y=4,height=4,text="Digital I/O is already inverted (or not) based on intended use. If you have a non-standard setup, you can use this option to avoid needing a redstone inverter.",fg_bg=cpair(colors.gray,colors.lightGray)}
    PushButton{parent=rs_c_9,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=rs_c_10,x=1,y=1,height=10,text="Make sure your relay is either touching the RTU gateway or connected via wired modems. There should be a wired modem on a side of the RTU gateway then one on the device, connected by a cable. The modem on the device needs to be right clicked to connect it (which will turn its border red), at which point the peripheral name will be shown in the chat."}
    PushButton{parent=rs_c_10,x=1,y=14,text="\x1b Back",callback=function()rs_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Tool Functions

    local function edit_rs_entry(idx)
        local def = tmp_cfg.Redstone[idx]

        self.rs_cfg_shortcut.hide(true)
        self.rs_cfg_color.show()

        self.rs_cfg_port = def.port
        self.rs_cfg_editing = idx

        local text = "Editing " .. rsio.to_string(def.port) .. " (for "
        if PORT_DSGN[def.port] == 1 then
            text = text .. "a unit)."
            self.rs_cfg_unit_l.show()
            self.rs_cfg_unit.show()
            self.rs_cfg_unit.set_value(def.unit or 1)
        else
            self.rs_cfg_unit_l.hide(true)
            self.rs_cfg_unit.hide(true)
            text = text .. "the facility)."
        end

        if rsio.is_analog(def.port) then
            self.rs_cfg_bundled.set_value(false)
            self.rs_cfg_bundled.disable()
            self.rs_cfg_advanced.disable()
        else
            self.rs_cfg_bundled.enable()
            self.rs_cfg_bundled.set_value(def.color ~= nil)
            self.rs_cfg_advanced.enable()
        end

        local value = 1
        if def.color ~= nil then
            value = color_to_idx(def.color)
            self.rs_cfg_color.enable()
        else
            self.rs_cfg_color.disable()
        end

        self.rs_cfg_selection.set_value(text)
        self.rs_cfg_side_l.set_value(tri(rsio.get_io_dir(def.port) == rsio.IO_DIR.IN, "Input Side", "Output Side"))
        side.set_value(side_to_idx(def.side))
        self.rs_cfg_color.set_value(value)
        self.rs_cfg_inverted.set_value(def.invert or false)
        rs_pane.set_value(4)
    end

    local function delete_rs_entry(idx)
        table.remove(tmp_cfg.Redstone, idx)
        tool_ctl.gen_rs_summary()
    end

    -- generate the redstone summary list
    function tool_ctl.gen_rs_summary()
        assert(self.rs_cfg_phy ~= false, "tried to generate a summary without a phy set")

        rs_list.remove_all()

        local ini = redstone_subset(ini_cfg.Redstone, self.rs_cfg_phy)
        local tmp = redstone_subset(tmp_cfg.Redstone, self.rs_cfg_phy)

        local modified = #ini ~= #tmp

        for i = 1, #tmp_cfg.Redstone do
            local def = tmp_cfg.Redstone[i]

            if def.relay == self.rs_cfg_phy then
                local name = rsio.to_string(def.port)
                local io_dir = tri(rsio.get_io_dir(def.port) == rsio.IO_DIR.IN, "\x1a", "\x1b")
                local io_c = tri(rsio.is_digital(def.port), colors.blue, colors.purple)
                local conn = def.side
                local unit = util.strval(def.unit or "F")

                if def.color ~= nil then conn = def.side .. "/" .. rsio.color_name(def.color) end

                local entry = Div{parent=rs_list,height=1}
                TextBox{parent=entry,x=1,y=1,width=1,text=io_dir,fg_bg=cpair(tri(def.invert,colors.orange,io_c),colors.white)}
                TextBox{parent=entry,x=2,y=1,width=14,text=name}
                TextBox{parent=entry,x=16,y=1,width=string.len(conn),text=conn,fg_bg=cpair(colors.gray,colors.white)}
                TextBox{parent=entry,x=33,y=1,width=1,text=unit,fg_bg=cpair(colors.gray,colors.white)}
                PushButton{parent=entry,x=35,y=1,min_width=6,height=1,text="EDIT",callback=function()edit_rs_entry(i)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
                PushButton{parent=entry,x=41,y=1,min_width=8,height=1,text="DELETE",callback=function()delete_rs_entry(i)end,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}

                if not modified then
                    local a = ini_cfg.Redstone[i]
                    local b = tmp_cfg.Redstone[i]

                    modified = (a.unit ~= b.unit) or (a.port ~= b.port) or (a.relay ~= b.relay) or (a.side ~= b.side) or (a.color ~= b.color) or (a.invert ~= b.invert)
                end
            end
        end

        if modified then
            rs_revert_btn.enable()
            rs_apply_btn.enable()
        else
            rs_revert_btn.disable()
            rs_apply_btn.disable()
        end
    end

    --#endregion

    return rs_pane
end

return redstone
