-- Tri-State Indicator Light Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")
local flasher = require("graphics.flasher")

---@class tristate_indicator_light_args
---@field label string indicator label
---@field c1 color color for state 1
---@field c2 color color for state 2
---@field c3 color color for state 3
---@field min_label_width? integer label length if omitted
---@field flash? boolean whether to flash on state 2 or 3 rather than stay on
---@field period? PERIOD flash period
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new tri-state indicator light
---@nodiscard
---@param args tristate_indicator_light_args
---@return graphics_element element, element_id id
local function tristate_indicator_light(args)
    element.assert(type(args.label) == "string", "label is a required field")
    element.assert(type(args.c1) == "number", "c1 is a required field")
    element.assert(type(args.c2) == "number", "c2 is a required field")
    element.assert(type(args.c3) == "number", "c3 is a required field")

    if args.flash then
        element.assert(util.is_int(args.period), "period is a required field if flash is enabled")
    end

    args.height = 1
    args.width = math.max(args.min_label_width or 1, string.len(args.label)) + 2

    -- create new graphics element base object
    local e = element.new(args)

    e.value = 1

    local flash_on = true

    local c1 = colors.toBlit(args.c1)
    local c2 = colors.toBlit(args.c2)
    local c3 = colors.toBlit(args.c3)

    -- called by flasher when enabled
    local function flash_callback()
        e.w_set_cur(1, 1)

        if flash_on then
            if e.value == 2 then
                e.w_blit(" \x95", "0" .. c2, c2 .. e.fg_bg.blit_bkg)
            elseif e.value == 3 then
                e.w_blit(" \x95", "0" .. c3, c3 .. e.fg_bg.blit_bkg)
            end
        else
            e.w_blit(" \x95", "0" .. c1, c1 .. e.fg_bg.blit_bkg)
        end

        flash_on = not flash_on
    end

    -- on state change
    ---@param new_state integer indicator state
    function e.on_update(new_state)
        local was_off = e.value <= 1

        e.value = new_state
        e.w_set_cur(1, 1)

        if args.flash then
            if was_off and (new_state > 1) then
                flash_on = true
                flasher.start(flash_callback, args.period)
            elseif new_state <= 1 then
                flash_on = false
                flasher.stop(flash_callback)

                e.w_blit(" \x95", "0" .. c1, c1 .. e.fg_bg.blit_bkg)
            end
        elseif new_state == 2 then
            e.w_blit(" \x95", "0" .. c2, c2 .. e.fg_bg.blit_bkg)
        elseif new_state == 3 then
            e.w_blit(" \x95", "0" .. c3, c3 .. e.fg_bg.blit_bkg)
        else
            e.w_blit(" \x95", "0" .. c1, c1 .. e.fg_bg.blit_bkg)
        end
    end

    -- set indicator state
    ---@param val integer indicator state
    function e.set_value(val) e.on_update(val) end

    -- draw light and label
    function e.redraw()
        e.on_update(1)
        e.w_write(args.label)
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return tristate_indicator_light
