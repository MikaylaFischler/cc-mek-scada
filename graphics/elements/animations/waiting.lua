-- Loading/Waiting Animation Graphics Element

local tcd     = require("scada-common.tcd")

local element = require("graphics.element")

---@class waiting_args
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new waiting animation element
---@param args waiting_args
---@return graphics_element element, element_id id
local function waiting(args)
    local state = 0
    local run_animation = false

    args.width = 4
    args.height = 3

    -- create new graphics element base object
    local e = element.new(args)

    local blit_fg = e.fg_bg.blit_fgd
    local blit_bg = e.fg_bg.blit_bkg
    local blit_fg_2x = e.fg_bg.blit_fgd .. e.fg_bg.blit_fgd
    local blit_bg_2x = e.fg_bg.blit_bkg .. e.fg_bg.blit_bkg

    -- tick the animation
    local function animate()
        e.window.clear()

        if state >= 0 and state < 7 then
            -- top
            e.w_set_cur(1 + math.floor(state / 2), 1)
            if state % 2 == 0 then
                e.w_blit("\x8f", blit_fg, blit_bg)
            else
                e.w_blit("\x8a\x85", blit_fg_2x, blit_bg_2x)
            end

            -- bottom
            e.w_set_cur(4 - math.ceil(state / 2), 3)
            if state % 2 == 0 then
                e.w_blit("\x8f", blit_fg, blit_bg)
            else
                e.w_blit("\x8a\x85", blit_fg_2x, blit_bg_2x)
            end
        else
            local st = state - 7

            -- right
            if st % 3 == 0 then
                e.w_set_cur(4, 1 + math.floor(st / 3))
                e.w_blit("\x83", blit_bg, blit_fg)
            elseif st % 3 == 1 then
                e.w_set_cur(4, 1 + math.floor(st / 3))
                e.w_blit("\x8f", blit_bg, blit_fg)
                e.w_set_cur(4, 2 + math.floor(st / 3))
                e.w_blit("\x83", blit_fg, blit_bg)
            else
                e.w_set_cur(4, 2 + math.floor(st / 3))
                e.w_blit("\x8f", blit_fg, blit_bg)
            end

            -- left
            if st % 3 == 0 then
                e.w_set_cur(1, 3 - math.floor(st / 3))
                e.w_blit("\x83", blit_fg, blit_bg)
                e.w_set_cur(1, 2 - math.floor(st / 3))
                e.w_blit("\x8f", blit_bg, blit_fg)
            elseif st % 3 == 1 then
                e.w_set_cur(1, 2 - math.floor(st / 3))
                e.w_blit("\x83", blit_bg, blit_fg)
            else
                e.w_set_cur(1, 2 - math.floor(st / 3))
                e.w_blit("\x8f", blit_fg, blit_bg)
            end
        end

        state = state + 1
        if state >= 12 then state = 0 end

        if run_animation then
            tcd.dispatch_unique(0.15, animate)
        end
    end

    -- start the animation
    function e.start_anim()
        run_animation = true
        animate()
    end

    -- stop the animation
    function e.stop_anim()
        run_animation = false
    end

    e.start_anim()

    return e.complete()
end

return waiting
