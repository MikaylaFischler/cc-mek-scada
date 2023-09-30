-- Indicator "LED" Graphics Element

local util    = require("scada-common.util")

local element = require("graphics.element")
local flasher = require("graphics.flasher")

---@class indicator_led_args
---@field label string indicator label
---@field colors cpair on/off colors (a/b respectively)
---@field min_label_width? integer label length if omitted
---@field flash? boolean whether to flash on true rather than stay on
---@field period? PERIOD flash period
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new indicator LED
---@nodiscard
---@param args indicator_led_args
---@return graphics_element element, element_id id
local function indicator_led(args)
    element.assert(type(args.label) == "string", "label is a required field")
    element.assert(type(args.colors) == "table", "colors is a required field")

    if args.flash then
        element.assert(util.is_int(args.period), "period is a required field if flash is enabled")
    end

    args.height = 1
    args.width = math.max(args.min_label_width or 0, string.len(args.label)) + 2

    local flash_on = true

    -- create new graphics element base object
    local e = element.new(args)

    e.value = false

    -- called by flasher when enabled
    local function flash_callback()
        e.w_set_cur(1, 1)

        if flash_on then
            e.w_blit("\x8c", args.colors.blit_a, e.fg_bg.blit_bkg)
        else
            e.w_blit("\x8c", args.colors.blit_b, e.fg_bg.blit_bkg)
        end

        flash_on = not flash_on
    end

    -- enable light or start flashing
    local function enable()
        if args.flash then
            flash_on = true
            flasher.start(flash_callback, args.period)
        else
            e.w_set_cur(1, 1)
            e.w_blit("\x8c", args.colors.blit_a, e.fg_bg.blit_bkg)
        end
    end

    -- disable light or stop flashing
    local function disable()
        if args.flash then
            flash_on = false
            flasher.stop(flash_callback)
        end

        e.w_set_cur(1, 1)
        e.w_blit("\x8c", args.colors.blit_b, e.fg_bg.blit_bkg)
    end

    -- on state change
    ---@param new_state boolean indicator state
    function e.on_update(new_state)
        e.value = new_state
        if new_state then enable() else disable() end
    end

    -- set indicator state
    ---@param val boolean indicator state
    function e.set_value(val) e.on_update(val) end

    -- draw label and indicator light
    function e.redraw()
        e.on_update(e.value)
        if string.len(args.label) > 0 then
            e.w_set_cur(3, 1)
            e.w_write(args.label)
        end
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return indicator_led
