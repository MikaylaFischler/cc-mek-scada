--
-- Graphics Style Options
--

local util        = require("scada-common.util")

local core        = require("graphics.core")
local themes      = require("graphics.themes")

local coordinator = require("coordinator.coordinator")

---@class crd_style
local style = {}

local cpair = core.cpair

local config = coordinator.config

-- front panel styling

style.fp_theme = themes.sandstone
style.fp = themes.get_fp_style(style.fp_theme)

style.led_grn = cpair(colors.green, colors.green_off)

-- main GUI styling

---@class theme
local smooth_stone = {
    text = colors.black,
    text_inv = colors.white,
    label = colors.gray,
    label_dark = colors.gray,
    disabled = colors.lightGray,
    bg = colors.lightGray,
    checkbox_bg = colors.black,
    accent_light = colors.white,
    accent_dark = colors.gray,

    fuel_color = colors.black,

    header = cpair(colors.white, colors.gray),

    text_fg = cpair(colors.black, colors._INHERIT),
    label_fg = cpair(colors.gray, colors._INHERIT),
    disabled_fg = cpair(colors.lightGray, colors._INHERIT),

    highlight_box = cpair(colors.black, colors.white),
    highlight_box_bright = cpair(colors.black, colors.white),
    field_box = cpair(colors.black, colors.white),

    colors = themes.smooth_stone.colors,

    -- color re-mappings for assistive modes
    color_modes = themes.smooth_stone.color_modes
}

---@type theme
local deepslate = {
    text = colors.white,
    text_inv = colors.black,
    label = colors.lightGray,
    label_dark = colors.gray,
    disabled = colors.gray,
    bg = colors.black,
    checkbox_bg = colors.gray,
    accent_light = colors.gray,
    accent_dark = colors.lightGray,

    fuel_color = colors.lightGray,

    header = cpair(colors.white, colors.gray),

    text_fg = cpair(colors.white, colors._INHERIT),
    label_fg = cpair(colors.lightGray, colors._INHERIT),
    disabled_fg = cpair(colors.gray, colors._INHERIT),

    highlight_box = cpair(colors.white, colors.gray),
    highlight_box_bright = cpair(colors.black, colors.lightGray),
    field_box = cpair(colors.white, colors.gray),

    colors = themes.deepslate.colors,

    -- color re-mappings for assistive modes
    color_modes = themes.deepslate.color_modes
}

style.theme = smooth_stone

-- set themes per configurations
---@param main UI_THEME main UI theme
---@param fp FP_THEME front panel theme
---@param color_mode COLOR_MODE the color mode to use
function style.set_themes(main, fp, color_mode)
    local colorblind = color_mode ~= themes.COLOR_MODE.STANDARD and color_mode ~= themes.COLOR_MODE.STD_ON_BLACK
    local gray_ind_off = color_mode == themes.COLOR_MODE.STANDARD or color_mode == themes.COLOR_MODE.BLUE_IND

    style.ind_bkg = colors.gray
    style.fp_ind_bkg = util.trinary(gray_ind_off, colors.gray, colors.black)
    style.ind_hi_box_bg = util.trinary(gray_ind_off, colors.gray, colors.black)

    if main == themes.UI_THEME.SMOOTH_STONE then
        style.theme = smooth_stone
        style.ind_bkg = util.trinary(gray_ind_off, colors.gray, colors.black)
    elseif main == themes.UI_THEME.DEEPSLATE then
        style.theme = deepslate
        style.ind_hi_box_bg = util.trinary(gray_ind_off, colors.lightGray, colors.black)
    end

    style.colorblind = colorblind

    style.root = cpair(style.theme.text, style.theme.bg)
    style.label = cpair(style.theme.label, style.theme.bg)

    -- high contrast text (also tags)
    style.hc_text = cpair(style.theme.text, style.theme.text_inv)
    -- text on default background
    style.text_colors = cpair(style.theme.text, style.theme.bg)
    -- label & unit colors
    style.lu_colors = cpair(style.theme.label, style.theme.label)
    -- label & unit colors (darker if set)
    style.lu_colors_dark = cpair(style.theme.label_dark, style.theme.label_dark)

    style.ind_grn = cpair(util.trinary(colorblind, colors.blue, colors.green), style.ind_bkg)
    style.ind_yel = cpair(colors.yellow, style.ind_bkg)
    style.ind_red = cpair(colors.red, style.ind_bkg)
    style.ind_wht = cpair(colors.white, style.ind_bkg)

    if fp == themes.FP_THEME.SANDSTONE then
        style.fp_theme = themes.sandstone
    elseif fp == themes.FP_THEME.BASALT then
        style.fp_theme = themes.basalt
    end

    style.fp = themes.get_fp_style(style.fp_theme)
end

-- COMMON COLOR PAIRS --

style.wh_gray = cpair(colors.white, colors.gray)

style.bw_fg_bg = cpair(colors.black, colors.white)

style.hzd_fg_bg  = style.wh_gray
style.dis_colors = cpair(colors.white, colors.lightGray)

style.lg_gray = cpair(colors.lightGray, colors.gray)
style.lg_white = cpair(colors.lightGray, colors.white)
style.gray_white = cpair(colors.gray, colors.white)

-- UI COMPONENTS --

style.reactor = {
    -- reactor states<br>
    ---@see REACTOR_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "PLC OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "PLC  FAULT" },
        { color = cpair(colors.white, colors.gray),   text = "DISABLED" },
        { color = cpair(colors.black, colors.green),  text = "ACTIVE" },
        { color = cpair(colors.black, colors.red),    text = "SCRAMMED" },
        { color = cpair(colors.black, colors.red),    text = "FORCE DISABLED" }
    }
}

style.boiler = {
    -- boiler states<br>
    ---@see BOILER_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "RTU  FAULT" },
        { color = cpair(colors.white, colors.gray),   text = "IDLE" },
        { color = cpair(colors.black, colors.green),  text = "ACTIVE" }
    }
}

style.turbine = {
    -- turbine states<br>
    ---@see TURBINE_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "RTU  FAULT" },
        { color = cpair(colors.white, colors.gray),   text = "IDLE" },
        { color = cpair(colors.black, colors.green),  text = "ACTIVE" },
        { color = cpair(colors.black, colors.red),    text = "TRIP" }
    }
}

style.dtank = {
    -- dynamic tank states<br>
    ---@see TANK_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "RTU  FAULT" },
        { color = cpair(colors.black, colors.green),  text = "ONLINE" },
        { color = cpair(colors.black, colors.yellow), text = "LOW FILL" },
        { color = cpair(colors.black, colors.green),  text = "FILLED" }
    }
}

style.imatrix = {
    -- induction matrix states<br>
    ---@see IMATRIX_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "RTU  FAULT" },
        { color = cpair(colors.black, colors.green),  text = "ONLINE" },
        { color = cpair(colors.black, colors.yellow), text = "LOW CHARGE" },
        { color = cpair(colors.black, colors.yellow), text = "HIGH  CHARGE" }
    }
}

style.sps = {
    -- SPS states<br>
    ---@see SPS_STATE
    states = {
        { color = cpair(colors.black, colors.yellow), text = "OFF-LINE" },
        { color = cpair(colors.black, colors.orange), text = "NOT FORMED" },
        { color = cpair(colors.black, colors.orange), text = "RTU  FAULT" },
        { color = cpair(colors.white, colors.gray),   text = "IDLE" },
        { color = cpair(colors.black, colors.green),  text = "ACTIVE" }
    }
}

-- get waste styling, which depends on the configuration
---@return { states: { color: color, text: string }, states_abbrv: { color: color, text: string }, options: string[], unit_opts: { text: string, fg_bg: cpair, active_fg_bg:cpair } }
function style.get_waste()
    local pu_color = util.trinary(config.GreenPuPellet, colors.green, colors.cyan)
    local po_color = util.trinary(config.GreenPuPellet, colors.cyan, colors.green)

    return {
        -- auto waste processing states
        states = {
            { color = cpair(colors.black, pu_color),      text = "PLUTONIUM" },
            { color = cpair(colors.black, po_color),      text = "POLONIUM" },
            { color = cpair(colors.black, colors.purple), text = "ANTI MATTER" }
        },
        states_abbrv = {
            { color = cpair(colors.black, pu_color),      text = "Pu" },
            { color = cpair(colors.black, po_color),      text = "Po" },
            { color = cpair(colors.black, colors.purple), text = "AM" }
        },
        -- process radio button options
        options = { "Plutonium", "Polonium", "Antimatter" },
        -- unit waste selection
        unit_opts = {
            { text = "Auto", fg_bg = cpair(colors.black, colors.lightGray), active_fg_bg = cpair(colors.white, colors.gray) },
            { text = "Pu", fg_bg = cpair(colors.black, colors.lightGray), active_fg_bg = cpair(colors.black, pu_color) },
            { text = "Po", fg_bg = cpair(colors.black, colors.lightGray), active_fg_bg = cpair(colors.black, po_color) },
            { text = "AM", fg_bg = cpair(colors.black, colors.lightGray), active_fg_bg = cpair(colors.black, colors.purple) }
        }
    }
end

return style
