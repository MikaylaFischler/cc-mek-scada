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

local self = {
    custom_inputs = {}  ---@type NumberField[]
}

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

    local mek_pane = MultiPane{parent=mek_cfg,y=4,panes={mek_c_1,mek_c_2}}

    TextBox{parent=mek_cfg,y=2,text=" Mekanism Configuration",fg_bg=cpair(colors.black,colors.magenta)}

    TextBox{parent=mek_c_1,y=1,height=3,text="To ensure calculations and control behavior is accurate, please select your Mekanism configuration. In most cases, you should use the default."}
    TextBox{parent=mek_c_1,y=5,height=3,text="If your modpack is listed, select it. If you or your pack creator manually changed Mekanism settings, please select Custom."}

    -- TextBox{parent=mek_c_1,x=39,y=11,text="new!",fg_bg=cpair(colors.red,colors._INHERIT)}  ---@todo remove NEW tag on next revision
    local profile = RadioButton{parent=mek_c_1,y=4,default=1,options=profile_names,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.magenta}

    local function submit_profile()
        -- apply if not custom, otherwise go to the custom config page
        if profile.get_value() < #profile_names then
            tmp_cfg.MekanismConfig = mekanism.profiles[profile.get_value()].fields

            main_pane.set_value(4)
        else mek_pane.set_value(2) end
    end

    PushButton{parent=mek_c_1,y=14,text="\x1b Back",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mek_c_1,x=44,y=14,text="Next \x1a",callback=submit_profile,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=mek_c_2,y=1,height=3,text="Since you selected Custom, check config/Mekanism/generators.toml in your server/world (path/name may vary by Mekanism version) and fill in the following fields."}

    local last_section = ""

    for _, key in ipairs(mekanism.ordered_keys) do
        if key[2] ~= last_section then
            last_section = key[2]

            mek_c_2.line_break()
            TextBox{parent=mek_c_2,height=1,text=key[2]}
        end

        local field = TextBox{parent=mek_c_2,height=1,text="  "..key[3]}

        self.custom_inputs[key[1]] = NumberField{parent=mek_c_2,y=field.get_y(),x=string.len(key[3])+3,width=10,default=ini_cfg.MekanismConfig[key[1]],allow_decimal=true,fg_bg=bw_fg_bg}
    end

    local function submit_custom_profile()
        for field, _ in ipairs(mekanism.profiles[1].fields) do
            tmp_cfg.MekanismConfig[field] = self.custom_inputs[field].get_value()
        end

        main_pane.set_value(4)
    end

    PushButton{parent=mek_c_2,y=14,text="\x1b Back",callback=function()mek_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=mek_c_2,x=44,y=14,text="Next \x1a",callback=submit_custom_profile,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    return mek_pane
end

return mekanism
