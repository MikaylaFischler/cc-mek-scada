-- Indicator LED Pair Graphics Element (two LEDs provide: off, color_a, color_b)

local util    = require("scada-common.util")

local element = require("graphics.element")
local flasher = require("graphics.flasher")

---@class indicator_led_pair_args
---@field label string indicator label
---@field off color color for off
---@field c1 color color for #1 on
---@field c2 color color for #2 on
---@field min_label_width? integer label length if omitted
---@field flash? boolean whether to flash when on rather than stay on
---@field period? PERIOD flash period
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new dual LED indicator light
---@nodiscard
---@param args indicator_led_pair_args
---@return graphics_element element, element_id id
local function indicator_led_pair(args)
    assert(type(args.label) == "string", "graphics.elements.indicators.ledpair: label is a required field")
    assert(type(args.off) == "number", "graphics.elements.indicators.ledpair: off is a required field")
    assert(type(args.c1) == "number", "graphics.elements.indicators.ledpair: c1 is a required field")
    assert(type(args.c2) == "number", "graphics.elements.indicators.ledpair: c2 is a required field")

    if args.flash then
        assert(util.is_int(args.period), "graphics.elements.indicators.ledpair: period is a required field if flash is enabled")
    end

    -- single line
    args.height = 1

    -- determine width
    args.width = math.max(args.min_label_width or 0, string.len(args.label)) + 2

    -- flasher state
    local flash_on = true

    -- blit translations
    local co = colors.toBlit(args.off)
    local c1 = colors.toBlit(args.c1)
    local c2 = colors.toBlit(args.c2)

    -- create new graphics element base object
    local e = element.new(args)

    -- init value for initial check in on_update
    e.value = 1

    -- called by flasher when enabled
    local function flash_callback()
        e.w_set_cur(1, 1)

        if flash_on then
            if e.value == 2 then
                e.w_blit("\x8c", c1, e.fg_bg.blit_bkg)
            elseif e.value == 3 then
                e.w_blit("\x8c", c2, e.fg_bg.blit_bkg)
            end
        else
            e.w_blit("\x8c", co, e.fg_bg.blit_bkg)
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

                e.w_blit("\x8c", co, e.fg_bg.blit_bkg)
            end
        elseif new_state == 2 then
            e.w_blit("\x8c", c1, e.fg_bg.blit_bkg)
        elseif new_state == 3 then
            e.w_blit("\x8c", c2, e.fg_bg.blit_bkg)
        else
            e.w_blit("\x8c", co, e.fg_bg.blit_bkg)
        end
    end

    -- set indicator state
    ---@param val integer indicator state
    function e.set_value(val) e.on_update(val) end

    -- write label and initial indicator light
    e.on_update(1)
    if string.len(args.label) > 0 then
        e.w_set_cur(3, 1)
        e.w_write(args.label)
    end

    return e.complete()
end

return indicator_led_pair
