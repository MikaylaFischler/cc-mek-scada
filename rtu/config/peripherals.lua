local ppm         = require("scada-common.ppm")
local util        = require("scada-common.util")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local PushButton  = require("graphics.elements.controls.PushButton")
local Radio2D     = require("graphics.elements.controls.Radio2D")
local RadioButton = require("graphics.elements.controls.RadioButton")

local NumberField = require("graphics.elements.form.NumberField")
local TextField   = require("graphics.elements.form.TextField")

---@class rtu_peri_definition
---@field unit integer|nil
---@field index integer|nil
---@field name string

local tri = util.trinary

local cpair = core.cpair

local LEFT = core.ALIGN.LEFT

local self = {
    peri_cfg_editing = false, ---@type integer|false

    p_assign = nil,           ---@type function

    ppm_devs = nil,           ---@type ListBox
    p_name_msg = nil,         ---@type TextBox
    p_prompt = nil,           ---@type TextBox
    p_idx = nil,              ---@type NumberField
    p_unit = nil,             ---@type NumberField
    p_desc = nil,             ---@type TextBox
    p_desc_ext = nil,         ---@type TextBox
    p_err = nil               ---@type TextBox
}

local peripherals = {}

local RTU_DEV_TYPES = { "boilerValve", "turbineValve", "dynamicValve", "inductionPort", "spsPort", "solarNeutronActivator", "environmentDetector", "environment_detector" }
local NEEDS_UNIT = { "boilerValve", "turbineValve", "dynamicValve", "solarNeutronActivator", "environmentDetector", "environment_detector" }

-- create the peripherals configuration view
---@param tool_ctl _rtu_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ rtu_config, rtu_config, rtu_config, table, function ]
---@param peri_cfg Div
---@param style { [string]: cpair }
---@return MultiPane peri_pane, string[] NEEDS_UNIT
function peripherals.create(tool_ctl, main_pane, cfg_sys, peri_cfg, style)
    local settings_cfg, ini_cfg, tmp_cfg, _, load_settings = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    --#region Peripherals

    local peri_c_1 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_2 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_3 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_4 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_5 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_6 = Div{parent=peri_cfg,x=2,y=4,width=49}
    local peri_c_7 = Div{parent=peri_cfg,x=2,y=4,width=49}

    local peri_pane = MultiPane{parent=peri_cfg,x=1,y=4,panes={peri_c_1,peri_c_2,peri_c_3,peri_c_4,peri_c_5,peri_c_6,peri_c_7}}

    TextBox{parent=peri_cfg,x=1,y=2,text=" Peripheral Connections",fg_bg=cpair(colors.black,colors.purple)}

    local peri_list = ListBox{parent=peri_c_1,x=1,y=1,height=12,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function peri_revert()
        tmp_cfg.Peripherals = tool_ctl.deep_copy_peri(ini_cfg.Peripherals)
        tool_ctl.gen_peri_summary()
    end

    local function peri_apply()
        settings.set("Peripherals", tmp_cfg.Peripherals)

        if settings.save("/rtu.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)
            peri_pane.set_value(5)

            -- for return to list from saved screen
            tmp_cfg.Peripherals = tool_ctl.deep_copy_peri(ini_cfg.Peripherals)
            tool_ctl.gen_peri_summary()
        else
            peri_pane.set_value(6)
        end
    end

    PushButton{parent=peri_c_1,x=1,y=14,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    local peri_revert_btn = PushButton{parent=peri_c_1,x=8,y=14,min_width=16,text="Revert Changes",callback=peri_revert,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    PushButton{parent=peri_c_1,x=35,y=14,min_width=7,text="Add +",callback=function()peri_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    local peri_apply_btn = PushButton{parent=peri_c_1,x=43,y=14,min_width=7,text="Apply",callback=peri_apply,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}

    TextBox{parent=peri_c_2,x=1,y=1,text="Select one of the below devices to use."}

    self.ppm_devs = ListBox{parent=peri_c_2,x=1,y=3,height=10,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    PushButton{parent=peri_c_2,x=1,y=14,text="\x1b Back",callback=function()peri_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_2,x=8,y=14,min_width=10,text="Manual +",callback=function()peri_pane.set_value(3)end,fg_bg=cpair(colors.black,colors.orange),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_2,x=26,y=14,min_width=24,text="I don't see my device!",callback=function()peri_pane.set_value(7)end,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=peri_c_7,x=1,y=1,height=10,text="Make sure your device is either touching the RTU or connected via wired modems. There should be a wired modem on a side of the RTU then one on the device, connected by a cable. The modem on the device needs to be right clicked to connect it (which will turn its border red), at which point the peripheral name will be shown in the chat."}
    TextBox{parent=peri_c_7,x=1,y=9,height=4,text="If it still does not show, it may not be compatible. Currently only Boilers, Turbines, Dynamic Tanks, SNAs, SPSs, Induction Matricies, and Environment Detectors are supported."}
    PushButton{parent=peri_c_7,x=1,y=14,text="\x1b Back",callback=function()peri_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    local new_peri_attrs = { "", "" }
    local function new_peri(name, type)
        new_peri_attrs = { name, type }
        self.peri_cfg_editing = false

        self.p_err.hide(true)
        self.p_name_msg.set_value("Configuring peripheral on '" .. name .. "':")
        self.p_desc_ext.set_value("")

        local function reposition(prompt, idx_x, idx_max, unit_x, unit_y, desc_y)
            self.p_prompt.set_value(prompt)
            self.p_idx.reposition(idx_x, 4)
            self.p_idx.enable()
            self.p_idx.set_max(idx_max)
            self.p_idx.show()
            self.p_unit.reposition(unit_x, unit_y)
            self.p_unit.enable()
            self.p_unit.show()
            self.p_desc.reposition(1, desc_y)
        end

        if type == "boilerValve" then
            reposition("This is reactor unit #    's #     boiler.", 31, 2, 23, 4, 7)
            self.p_assign_btn.hide(true)
            self.p_desc.set_value("Each unit can have at most 2 boilers. Boiler #1 shows up first on the main display, followed by boiler #2 below it. The numberings are per unit (unit 1 and unit 2 would both have a boiler #1 if each had one boiler) and can be split amongst multiple RTUs (one has #1, another has #2).")
        elseif type == "turbineValve" then
            reposition("This is reactor unit #    's #     turbine.", 31, 3, 23, 4, 7)
            self.p_assign_btn.hide(true)
            self.p_desc.set_value("Each unit can have at most 3 turbines. Turbine #1 shows up first on the main display, followed by #2 then #3 below it. The numberings are per unit (unit 1 and unit 2 would both have a turbine #1) and can be split amongst multiple RTUs (one has #1, another has #2).")
        elseif type == "solarNeutronActivator" then
            reposition("This SNA is for reactor unit #    .", 46, 1, 31, 4, 7)
            self.p_idx.hide()
            self.p_assign_btn.hide(true)
            self.p_desc_ext.set_value("Warning: too many devices on one RTU Gateway can cause lag. Note that 10x the \"PEAK\x1a\" rate on the flow monitor gives you the mB/t of waste that the SNA(s) can process. Enough SNAs to provide 2x to 3x of that unit's max burn rate should be a good margin to catch up after night or cloudy weather.")
        elseif type == "dynamicValve" then
            reposition("This is the below system's #     dynamic tank.", 29, 4, 17, 6, 8)
            self.p_assign_btn.show()
            self.p_assign_btn.redraw()

            if self.p_assign_btn.get_value() == 1 then
                self.p_idx.enable()
                self.p_unit.disable()
            else
                self.p_idx.set_value(1)
                self.p_idx.disable()
                self.p_unit.enable()
            end

            self.p_desc.set_value("Each reactor unit can have at most 1 tank and the facility can have at most 4. Each facility tank must have a unique # 1 through 4, regardless of where it is connected. Only a total of 4 tanks can be displayed on the flow monitor.")
        elseif type == "environmentDetector" or type == "environment_detector" then
            reposition("This is the below system's #     env. detector.", 29, 99, 17, 6, 8)
            self.p_assign_btn.show()
            self.p_assign_btn.redraw()
            if self.p_assign_btn.get_value() == 1 then self.p_unit.disable() else self.p_unit.enable() end
            self.p_desc.set_value("You can connect more than one environment detector for a particular unit or the facility. In that case, the maximum radiation reading from those assigned to that particular unit or the facility will be used for alarms and display.")
        elseif type == "inductionPort" or type == "spsPort" then
            local dev = tri(type == "inductionPort", "induction matrix", "SPS")
            self.p_idx.hide(true)
            self.p_unit.hide(true)
            self.p_prompt.set_value("This is the " .. dev .. " for the facility.")
            self.p_assign_btn.hide(true)
            self.p_desc.reposition(1, 7)
            self.p_desc.set_value("There can only be one of these devices per SCADA network, so it will be assigned as the sole " .. dev .. " for the facility. There must only be one of these across all the RTUs you have.")
        else
            assert(false, "invalid peripheral type after type validation")
        end

        peri_pane.set_value(4)
    end

    -- update peripherals list
    function tool_ctl.update_peri_list()
        local alternate = true
        local mounts = ppm.list_mounts()

        -- filter out in-use peripherals
        for _, v in ipairs(tmp_cfg.Peripherals) do mounts[v.name] = nil end

        self.ppm_devs.remove_all()
        for name, entry in pairs(mounts) do
            if util.table_contains(RTU_DEV_TYPES, entry.type) then
                local bkg = tri(alternate, colors.white, colors.lightGray)

                ---@cast entry ppm_entry
                local line = Div{parent=self.ppm_devs,height=2,fg_bg=cpair(colors.black,bkg)}
                PushButton{parent=line,x=1,y=1,min_width=9,alignment=LEFT,height=1,text="> SELECT",callback=function()new_peri(name,entry.type)end,fg_bg=cpair(colors.black,colors.purple),active_fg_bg=cpair(colors.white,colors.black)}
                TextBox{parent=line,x=11,y=1,text=name,fg_bg=cpair(colors.black,bkg)}
                TextBox{parent=line,x=11,y=2,text=entry.type,fg_bg=cpair(colors.gray,bkg)}

                alternate = not alternate
            end
        end
    end

    tool_ctl.update_peri_list()

    TextBox{parent=peri_c_3,x=1,y=1,height=4,text="This feature is intended for advanced users. If you are clicking this just because your device is not shown, follow the connection instructions in 'I don't see my device!'."}
    TextBox{parent=peri_c_3,x=1,y=6,height=4,text="Peripheral Name"}
    local p_name = TextField{parent=peri_c_3,x=1,y=7,width=49,height=1,max_len=128,fg_bg=bw_fg_bg}
    local p_type = Radio2D{parent=peri_c_3,x=1,y=9,rows=4,columns=2,default=1,options=RTU_DEV_TYPES,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.purple}
    local man_p_err = TextBox{parent=peri_c_3,x=8,y=14,width=35,text="Please enter a peripheral name.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
    man_p_err.hide(true)

    local function submit_manual_peri()
        local name = p_name.get_value()
        if string.len(name) > 0 then
            tool_ctl.entering_manual = true
            man_p_err.hide(true)
            new_peri(name, RTU_DEV_TYPES[p_type.get_value()])
        else man_p_err.show() end
    end

    PushButton{parent=peri_c_3,x=1,y=14,text="\x1b Back",callback=function()peri_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_3,x=44,y=14,text="Next \x1a",callback=submit_manual_peri,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    self.p_name_msg = TextBox{parent=peri_c_4,x=1,y=1,height=2,text=""}
    self.p_prompt = TextBox{parent=peri_c_4,x=1,y=4,height=2,text=""}
    self.p_idx = NumberField{parent=peri_c_4,x=31,y=4,width=4,max_chars=2,min=1,max=2,default=1,fg_bg=bw_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    self.p_assign_btn = RadioButton{parent=peri_c_4,x=1,y=5,default=1,options={"the facility","reactor unit #"},callback=function(v)self.p_assign(v)end,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.purple}

    self.p_unit = NumberField{parent=peri_c_4,x=23,y=4,width=4,max_chars=2,min=1,max=4,default=1,fg_bg=bw_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    self.p_unit.disable()

    function self.p_assign(opt)
        if opt == 1 then
            self.p_unit.disable()
            if new_peri_attrs[2] == "dynamicValve" then self.p_idx.enable() end
        else
            self.p_unit.enable()
            if new_peri_attrs[2] == "dynamicValve" then
                self.p_idx.set_value(1)
                self.p_idx.disable()
            end
        end
    end

    self.p_desc = TextBox{parent=peri_c_4,x=1,y=7,height=6,text="",fg_bg=g_lg_fg_bg}
    self.p_desc_ext = TextBox{parent=peri_c_4,x=1,y=6,height=7,text="",fg_bg=g_lg_fg_bg}

    self.p_err = TextBox{parent=peri_c_4,x=8,y=14,width=32,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}
    self.p_err.hide(true)

    local function back_from_peri_opts()
        if self.peri_cfg_editing ~= false then
            peri_pane.set_value(1)
        elseif tool_ctl.entering_manual then
            peri_pane.set_value(3)
        else
            peri_pane.set_value(2)
        end

        tool_ctl.entering_manual = false
    end

    local function save_peri_entry()
        local peri_name = new_peri_attrs[1]
        local peri_type = new_peri_attrs[2]

        local unit, index = nil, nil

        local for_facility = self.p_assign_btn.get_value() == 1
        local u = tonumber(self.p_unit.get_value())
        local idx = tonumber(self.p_idx.get_value())

        if util.table_contains(NEEDS_UNIT, peri_type) then
            if (peri_type == "dynamicValve" or peri_type == "environmentDetector" or peri_type == "environment_detector") and for_facility then
                -- skip
            elseif not (util.is_int(u) and u > 0 and u < 5) then
                self.p_err.set_value("Unit ID must be within 1 to 4.")
                self.p_err.show()
                return
            else unit = u end
        end

        if peri_type == "boilerValve" then
            if not (idx == 1 or idx == 2) then
                self.p_err.set_value("Index must be 1 or 2.")
                self.p_err.show()
                return
            else index = idx end
        elseif peri_type == "turbineValve" then
            if not (idx == 1 or idx == 2 or idx == 3) then
                self.p_err.set_value("Index must be 1, 2, or 3.")
                self.p_err.show()
                return
            else index = idx end
        elseif peri_type == "dynamicValve" and for_facility then
            if not (util.is_int(idx) and idx > 0 and idx < 5) then
                self.p_err.set_value("Index must be within 1 to 4.")
                self.p_err.show()
                return
            else index = idx end
        elseif peri_type == "dynamicValve" then
            index = 1
        elseif peri_type == "environmentDetector" or peri_type == "environment_detector" then
            if not (util.is_int(idx) and idx > 0) then
                self.p_err.set_value("Index must be greater than 0.")
                self.p_err.show()
                return
            else index = idx end
        end

        self.p_err.hide(true)

        ---@type rtu_peri_definition
        local def = { name = peri_name, unit = unit, index = index }

        if self.peri_cfg_editing == false then
            table.insert(tmp_cfg.Peripherals, def)
        else
            def.name = tmp_cfg.Peripherals[self.peri_cfg_editing].name
            tmp_cfg.Peripherals[self.peri_cfg_editing] = def
        end

        peri_pane.set_value(1)
        tool_ctl.gen_peri_summary()
        tool_ctl.update_peri_list()

        self.p_idx.set_value(1)
    end

    PushButton{parent=peri_c_4,x=1,y=14,text="\x1b Back",callback=back_from_peri_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_4,x=41,y=14,min_width=9,text="Confirm",callback=save_peri_entry,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=peri_c_5,x=1,y=1,text="Settings saved!"}
    PushButton{parent=peri_c_5,x=1,y=14,text="\x1b Back",callback=function()peri_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_5,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=peri_c_6,x=1,y=1,height=5,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=peri_c_6,x=1,y=14,text="\x1b Back",callback=function()peri_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=peri_c_6,x=44,y=14,min_width=6,text="Home",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Tool Functions

    ---@param def rtu_peri_definition
    ---@param idx integer
    ---@param type string
    local function edit_peri_entry(idx, def, type)
        -- set inputs BEFORE calling new_peri()
        if def.index ~= nil then self.p_idx.set_value(def.index) end
        if def.unit == nil then
            self.p_assign_btn.set_value(1)
        else
            self.p_unit.set_value(def.unit)
            self.p_assign_btn.set_value(2)
        end

        new_peri(def.name, type)

        -- set editing mode AFTER new_peri()
        self.peri_cfg_editing = idx
    end

    local function delete_peri_entry(idx)
        table.remove(tmp_cfg.Peripherals, idx)
        tool_ctl.gen_peri_summary()
        tool_ctl.update_peri_list()
    end

    -- generate the peripherals summary list
    function tool_ctl.gen_peri_summary()
        peri_list.remove_all()

        local modified = #ini_cfg.Peripherals ~= #tmp_cfg.Peripherals

        for i = 1, #tmp_cfg.Peripherals do
            local def = tmp_cfg.Peripherals[i]

            local t = ppm.get_type(def.name)
            local t_str = "<disconnected> (connect to edit)"
            local disconnected = t == nil

            if not disconnected then t_str = "[" .. t .. "]" end

            local desc = "  \x1a "

            if type(def.index) == "number" then
                desc = desc .. "#" .. def.index .. " "
            end

            if type(def.unit) == "number" then
                desc = desc .. "for unit " .. def.unit
            else
                desc = desc .. "for the facility"
            end

            local entry = Div{parent=peri_list,height=3}
            TextBox{parent=entry,x=1,y=1,text="@ "..def.name,fg_bg=cpair(colors.black,colors.white)}
            TextBox{parent=entry,x=1,y=2,text="  \x1a "..t_str,fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=entry,x=1,y=3,text=desc,fg_bg=cpair(colors.gray,colors.white)}
            local edit_btn = PushButton{parent=entry,x=41,y=2,min_width=8,height=1,text="EDIT",callback=function()edit_peri_entry(i,def,t or "")end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
            PushButton{parent=entry,x=41,y=3,min_width=8,height=1,text="DELETE",callback=function()delete_peri_entry(i)end,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}

            if disconnected then edit_btn.disable() end

            if not modified then
                local a = ini_cfg.Peripherals[i]
                local b = tmp_cfg.Peripherals[i]

                modified = (a.unit ~= b.unit) or (a.index ~= b.index) or (a.name ~= b.name)
            end
        end

        if modified then
            peri_revert_btn.enable()
            peri_apply_btn.enable()
        else
            peri_revert_btn.disable()
            peri_apply_btn.disable()
        end
    end

    --#endregion

    return peri_pane, NEEDS_UNIT
end

return peripherals
