local util        = require("scada-common.util")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local PushButton  = require("graphics.elements.controls.PushButton")
local RadioButton = require("graphics.elements.controls.RadioButton")

local NumberField = require("graphics.elements.form.NumberField")

local tri = util.trinary

local cpair = core.cpair

local mekanism = {}

mekanism.ordered_keys = {
    { "energyPerFissionFuel", "fission_reactor", "energyPerFissionFuel" },
    { "turbineDisperserChemicalFlow", "turbine", "disperserChemicalFlow" },
    { "turbineVentChemicalFlow", "turbine", "ventChemicalFlow" },
    { "turbineChemicalPerTank", "turbine", "chemicalPerTank" }
}

mekanism.profiles = {
    {
        name = "Default",
        ---@class mekanism_configs
        fields = {
            energyPerFissionFuel         = 1000000,
            turbineDisperserChemicalFlow = 1280,
            turbineVentChemicalFlow      = 32000,
            turbineChemicalPerTank       = 64000
        }
    },
    {
        name = "ATM10",
        ---@type mekanism_configs
        fields = {
            energyPerFissionFuel         = 250000,
            turbineDisperserChemicalFlow = 1280,
            turbineVentChemicalFlow      = 43478.262,
            turbineChemicalPerTank       = 6400
        }
    },
    {
        name = "ATM10 To The Sky",
        ---@type mekanism_configs
        fields = {
            energyPerFissionFuel         = 2800000,
            turbineDisperserChemicalFlow = 1280,
            turbineVentChemicalFlow      = 43478.262,
            turbineChemicalPerTank       = 64000
        }
    }
}

local profile_names = {}

for _, p in ipairs(mekanism.profiles) do
    table.insert(profile_names, p.name)
end

table.insert(profile_names, "Custom")

-- create the mekanism configuration view
---@param tool_ctl _svr_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ svr_config, svr_config, svr_config, table, function ]
---@param mek_cfg Div
---@param style { [string]: cpair }
---@return MultiPane fac_pane
function mekanism.create(tool_ctl, main_pane, cfg_sys, mek_cfg, style)
    local _, ini_cfg, tmp_cfg, _, _ = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg

    --#region Mekanism Configuration

    local mek_c_1 = Div{parent=mek_cfg,x=2,y=4,width=49}
    local mek_c_2 = Div{parent=mek_cfg,x=2,y=4,width=49}
    local mek_c_3 = Div{parent=mek_cfg,x=2,y=4,width=49}

    local mek_pane = MultiPane{parent=mek_cfg,y=4,panes={mek_c_1,mek_c_2,mek_c_3}}

    TextBox{parent=mek_cfg,y=2,text=" Mekanism Configuration",fg_bg=cpair(colors.white,colors.brown)}

    TextBox{parent=mek_c_1,y=1,height=3,text="To ensure calculations and behavior are correct, please select your Mekanism configuration. In most cases, you should use the default."}
    TextBox{parent=mek_c_1,y=5,height=3,text="If your modpack is listed, select it. If you or your pack creator manually changed Mekanism settings, please select Custom."}

    local initial = #profile_names

    for i = 1, #profile_names do
        if profile_names[i] == ini_cfg.MekanismProfile then
            initial = i
            break
        end
    end

    TextBox{parent=mek_c_1,x=33,y=7,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision
    local profile = RadioButton{parent=mek_c_1,y=9,default=initial,options=profile_names,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.brown}

    local function submit_profile()
        tmp_cfg.MekanismProfile = profile_names[profile.get_value()] or "Custom"

        -- apply if not custom, otherwise go to the custom config page
        if profile.get_value() < #profile_names then
            tmp_cfg.MekanismConfig = mekanism.profiles[profile.get_value()].fields

            local is_atm10 = tmp_cfg.MekanismProfile == "ATM10"

            tmp_cfg.MekanismWasteToPu[1] = tri(is_atm10, 5, 10)
            tmp_cfg.MekanismWasteToPu[2] = 1
            tmp_cfg.MekanismWasteToPo[1] = tri(is_atm10, 5, 10)
            tmp_cfg.MekanismWasteToPo[2] = 1

            main_pane.set_value(4)
        else mek_pane.set_value(2) end
    end

    tool_ctl.mek_profile = profile

    PushButton{parent=mek_c_1,y=14,text="\x1b Back",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mek_c_1,x=44,y=14,text="Next \x1a",callback=submit_profile,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=mek_c_2,y=1,height=4,text="For Custom, check config/Mekanism/generators.toml on your server/world and fill in the following fields. This path or config names may vary by Mekanism version (e.g. gas instead of chemical)."}

    local last_section = ""

    for _, key in ipairs(mekanism.ordered_keys) do
        if key[2] ~= last_section then
            last_section = key[2]

            mek_c_2.line_break()
            TextBox{parent=mek_c_2,height=1,text="["..key[2].."]"}
        end

        local field = TextBox{parent=mek_c_2,height=1,text="  "..key[3].." ="}

        tool_ctl.custom_configs[key[1]] = NumberField{parent=mek_c_2,y=field.get_y(),x=string.len(key[3])+6,width=10,default=ini_cfg.MekanismConfig[key[1]],allow_decimal=true,fg_bg=bw_fg_bg}
        TextBox{parent=mek_c_2,x=string.len(key[3])+17,y=field.get_y(),text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision
    end

    local function submit_custom_profile()
        for _, key in ipairs(mekanism.ordered_keys) do
            tmp_cfg.MekanismConfig[key[1]] = tool_ctl.custom_configs[key[1]].get_value()
        end

        mek_pane.set_value(3)
    end

    PushButton{parent=mek_c_2,y=14,text="\x1b Back",callback=function()mek_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mek_c_2,x=44,y=14,text="Next \x1a",callback=submit_custom_profile,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=mek_c_3,y=1,height=3,text="Some modpacks also change the nuclear waste to product ratios. These are usually 10:1, where 10mB waste makes 1mB plutonium or polonium."}

    TextBox{parent=mek_c_3,y=5,text="Nuclear Waste to Plutonium     :"}
    tool_ctl.waste_ratios[1] = NumberField{parent=mek_c_3,y=5,x=28,width=4,default=ini_cfg.MekanismWasteToPu[1],min=1,max=99,allow_decimal=false,align_right=true,fg_bg=bw_fg_bg}
    tool_ctl.waste_ratios[2] = NumberField{parent=mek_c_3,y=5,x=33,width=4,default=ini_cfg.MekanismWasteToPu[2],min=1,max=99,allow_decimal=false,fg_bg=bw_fg_bg}
    TextBox{parent=mek_c_3,x=38,y=5,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision

    TextBox{parent=mek_c_3,y=6,text="Nuclear Waste to Polonium      :"}
    tool_ctl.waste_ratios[3] = NumberField{parent=mek_c_3,y=6,x=28,width=4,default=ini_cfg.MekanismWasteToPo[1],min=1,max=99,allow_decimal=false,align_right=true,fg_bg=bw_fg_bg}
    tool_ctl.waste_ratios[4] = NumberField{parent=mek_c_3,y=6,x=33,width=4,default=ini_cfg.MekanismWasteToPo[2],min=1,max=99,allow_decimal=false,fg_bg=bw_fg_bg}
    TextBox{parent=mek_c_3,x=38,y=6,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision

    TextBox{parent=mek_c_3,y=8,height=2,text="Tip: the easist way to check these are their receipes in JEI.",fg_bg=g_lg_fg_bg}

    local function submit_waste_ratios()
        tmp_cfg.MekanismWasteToPu[1] = tool_ctl.waste_ratios[1].get_value()
        tmp_cfg.MekanismWasteToPu[2] = tool_ctl.waste_ratios[2].get_value()
        tmp_cfg.MekanismWasteToPo[1] = tool_ctl.waste_ratios[3].get_value()
        tmp_cfg.MekanismWasteToPo[2] = tool_ctl.waste_ratios[4].get_value()

        main_pane.set_value(4)
    end

    PushButton{parent=mek_c_3,y=14,text="\x1b Back",callback=function()mek_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mek_c_3,x=44,y=14,text="Next \x1a",callback=submit_waste_ratios,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    return mek_pane
end

return mekanism
