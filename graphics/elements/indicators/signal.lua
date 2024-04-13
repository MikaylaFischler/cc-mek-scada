-- Signal Bars Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")

---@class signal_bar_args
---@field compact? boolean true to use a single character (works better against edges that extend out colors)
---@field colors_low_med? cpair color a for low signal quality, color b for medium signal quality
---@field disconnect_color? color color for the 'x' on disconnect
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors (foreground is used for high signal quality)
---@field hidden? boolean true to hide on initial draw

-- new signal bar
---@nodiscard
---@param args signal_bar_args
---@return graphics_element element, element_id id
local function signal_bar(args)
    args.height = 1
    args.width = util.trinary(args.compact, 1, 2)

    -- create new graphics element base object
    local e = element.new(args)

    e.value = 0

    local blit_bkg = args.fg_bg.blit_bkg
    local blit_0, blit_1, blit_2, blit_3 = args.fg_bg.blit_fgd, args.fg_bg.blit_fgd, args.fg_bg.blit_fgd, args.fg_bg.blit_fgd

    if type(args.colors_low_med) == "table" then
        blit_1 = args.colors_low_med.blit_a or blit_1
        blit_2 = args.colors_low_med.blit_b or blit_2
    end

    if util.is_int(args.disconnect_color) then blit_0 = colors.toBlit(args.disconnect_color) end

    -- on state change (0 = offline, 1 through 3 = low to high signal)
    ---@param new_state integer signal state
    function e.on_update(new_state)
        e.value = new_state
        e.redraw()
    end

    -- set signal state (0 = offline, 1 through 3 = low to high signal)
    ---@param val integer signal state
    function e.set_value(val) e.on_update(val) end

    -- draw label and signal bar
    function e.redraw()
        e.w_set_cur(1, 1)

        if args.compact then
            if e.value == 1 then
                e.w_blit("\x90", blit_1, blit_bkg)
            elseif e.value == 2 then
                e.w_blit("\x94", blit_2, blit_bkg)
            elseif e.value == 3 then
                e.w_blit("\x95", blit_3, blit_bkg)
            else
                e.w_blit("x", blit_0, blit_bkg)
            end
        else
            if e.value == 1 then
                e.w_blit("\x9f ", blit_bkg .. blit_bkg, blit_1 .. blit_bkg)
            elseif e.value == 2 then
                e.w_blit("\x9f\x94", blit_bkg .. blit_2, blit_2 .. blit_bkg)
            elseif e.value == 3 then
                e.w_blit("\x9f\x81", blit_bkg .. blit_bkg, blit_3 .. blit_3)
            else
                e.w_blit(" x", blit_0 .. blit_0, blit_bkg .. blit_bkg)
            end
        end
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return signal_bar
