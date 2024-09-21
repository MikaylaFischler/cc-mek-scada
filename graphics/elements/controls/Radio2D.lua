-- 2D Radio Button Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

---@class radio_2d_args
---@field rows integer
---@field columns integer
---@field options table
---@field radio_colors cpair radio button colors (inner & outer)
---@field select_color? color color for radio button when selected
---@field color_map? table colors for each radio button when selected
---@field disable_color? color color for radio button when disabled
---@field disable_fg_bg? cpair text colors when disabled
---@field default? integer default state, defaults to options[1]
---@field callback? function function to call on touch
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new 2D radio button list (latch selection, exclusively one color at a time)
---@param args radio_2d_args
---@return graphics_element element, element_id id
local function radio_2d_button(args)
    element.assert(type(args.options) == "table" and #args.options > 0, "options should be a table with length >= 1")
    element.assert(util.is_int(args.rows) and util.is_int(args.columns), "rows/columns must be integers")
    element.assert((args.rows * args.columns) >= #args.options, "rows x columns size insufficient for provided number of options")
    element.assert(type(args.radio_colors) == "table", "radio_colors is a required field")
    element.assert(type(args.select_color) == "number" or type(args.color_map) == "table", "select_color or color_map is required")
    element.assert(type(args.default) == "nil" or (type(args.default) == "number" and args.default > 0), "default must be nil or a number > 0")

    local array = {}
    local col_widths = {}

    local next_idx = 1
    local total_width = 0
    local max_rows = 1

    local focused_opt = 1
    local focus_x, focus_y = 1, 1

    -- build table to display
    for col = 1, args.columns do
        local max_width = 0
        array[col] = {}

        for row = 1, args.rows do
            local len = string.len(args.options[next_idx])
            if len > max_width then max_width = len end
            if row > max_rows then max_rows = row end

            table.insert(array[col], { text = args.options[next_idx], id = next_idx, x_1 = 1 + total_width, x_2 = 2 + total_width + len })

            next_idx = next_idx + 1
            if next_idx > #args.options then break end
        end

        table.insert(col_widths, max_width + 3)
        total_width = total_width + max_width + 3
        if next_idx > #args.options then break end
    end

    args.can_focus = true
    args.width = total_width
    args.height = max_rows

    -- create new graphics element base object
    local e = element.new(args)

    -- selected option (convert nil to 1 if missing)
    e.value = args.default or 1

    -- draw the element
    function e.redraw()
        local col_x = 1

        local radio_color_b = util.trinary(type(args.disable_color) == "number" and not e.enabled, args.disable_color, args.radio_colors.color_b)

        for col = 1, #array do
            for row = 1, #array[col] do
                local opt = array[col][row]
                local select_color = args.select_color

                if type(args.color_map) == "table" and args.color_map[opt.id] then
                    select_color = args.color_map[opt.id]
                end

                local inner_color = util.trinary((e.value == opt.id) and e.enabled, radio_color_b, args.radio_colors.color_a)
                local outer_color = util.trinary((e.value == opt.id) and e.enabled, select_color, radio_color_b)

                e.w_set_cur(col_x, row)

                e.w_set_fgd(inner_color)
                e.w_set_bkg(outer_color)
                e.w_write("\x88")

                e.w_set_fgd(outer_color)
                e.w_set_bkg(e.fg_bg.bkg)
                e.w_write("\x95")

                if opt.id == focused_opt then
                    focus_x, focus_y = row, col
                end

                -- write button text
                if opt.id == focused_opt and e.is_focused() and e.enabled then
                    e.w_set_fgd(e.fg_bg.bkg)
                    e.w_set_bkg(e.fg_bg.fgd)
                elseif type(args.disable_fg_bg) == "table" and not e.enabled then
                    e.w_set_fgd(args.disable_fg_bg.fgd)
                    e.w_set_bkg(args.disable_fg_bg.bkg)
                else
                    e.w_set_fgd(e.fg_bg.fgd)
                    e.w_set_bkg(e.fg_bg.bkg)
                end

                e.w_write(opt.text)
            end

            col_x = col_x + col_widths[col]
        end
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if e.enabled and core.events.was_clicked(event.type) and (event.initial.y == event.current.y) then
            -- determine what was pressed
            for _, row in ipairs(array) do
                local elem = row[event.current.y]
                if elem ~= nil and event.initial.x >= elem.x_1 and event.initial.x <= elem.x_2 and event.current.x >= elem.x_1 and event.current.x <= elem.x_2 then
                    e.value = elem.id
                    focused_opt = elem.id
                    e.redraw()
                    if type(args.callback) == "function" then args.callback(e.value) end
                    break
                end
            end
        end
    end

    -- handle keyboard interaction
    ---@param event key_interaction key event
    function e.handle_key(event)
        if event.type == core.events.KEY_CLICK.DOWN or event.type == core.events.KEY_CLICK.HELD then
            if event.type == core.events.KEY_CLICK.DOWN and (event.key == keys.space or event.key == keys.enter or event.key == keys.numPadEnter) then
                e.value = focused_opt
                e.redraw()
                if type(args.callback) == "function" then args.callback(e.value) end
            elseif event.key == keys.down then
                if focused_opt < #args.options then
                    focused_opt = focused_opt + 1
                    e.redraw()
                end
            elseif event.key == keys.up then
                if focused_opt > 1 then
                    focused_opt = focused_opt - 1
                    e.redraw()
                end
            elseif event.key == keys.right then
                if array[focus_y + 1] and array[focus_y + 1][focus_x] then
                    focused_opt = array[focus_y + 1][focus_x].id
                else focused_opt = array[1][focus_x].id end
                e.redraw()
            elseif event.key == keys.left then
                if array[focus_y - 1] and array[focus_y - 1][focus_x] then
                    focused_opt = array[focus_y - 1][focus_x].id
                    e.redraw()
                elseif array[#array][focus_x] then
                    focused_opt = array[#array][focus_x].id
                    e.redraw()
                end
            end
        end
    end

    -- set the value
    ---@param val integer new value
    function e.set_value(val)
        if type(val) == "number" and val > 0 and val <= #args.options then
            e.value = val
            e.redraw()
        end
    end

    -- handle focus & enable
    e.on_focused = e.redraw
    e.on_unfocused = e.redraw
    e.on_enabled = e.redraw
    e.on_disabled = e.redraw

    -- initial draw
    e.redraw()

    return e.complete()
end

return radio_2d_button
