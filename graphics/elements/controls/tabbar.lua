-- Tab Bar Graphics Element

local util    = require("scada-common.util")

local core    = require("graphics.core")
local element = require("graphics.element")

---@class tabbar_tab
---@field name string tab name
---@field color cpair tab colors (fg/bg)
---@field _start_x integer starting touch x range (inclusive)
---@field _end_x integer ending touch x range (inclusive)

---@class tabbar_args
---@field tabs table tab options
---@field callback function function to call on tab change
---@field min_width? integer text length + 2 if omitted
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width? integer parent width if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- new tab selector
---@param args tabbar_args
---@return graphics_element element, element_id id
local function tabbar(args)
    element.assert(type(args.tabs) == "table", "tabs is a required field")
    element.assert(#args.tabs > 0, "at least one tab is required")
    element.assert(type(args.callback) == "function", "callback is a required field")
    element.assert(type(args.min_width) == "nil" or (type(args.min_width) == "number" and args.min_width > 0), "min_width must be nil or a number > 0")

    args.height = 1

    -- determine widths
    local max_width = 1
    for i = 1, #args.tabs do
        local opt = args.tabs[i]    ---@type tabbar_tab
        if string.len(opt.name) > max_width then
            max_width = string.len(opt.name)
        end
    end

    local button_width = math.max(max_width, args.min_width or 0)

    -- create new graphics element base object
    local e = element.new(args)

    element.assert(e.frame.w >= (button_width * #args.tabs), "width insufficent to display all tabs")

    -- default to 1st tab
    e.value = 1

    -- calculate required tab dimension information
    local next_x = 1
    for i = 1, #args.tabs do
        local tab = args.tabs[i] ---@type tabbar_tab

        tab._start_x = next_x
        tab._end_x = next_x + button_width - 1

        next_x = next_x + button_width
    end

    -- show the tab state
    function e.redraw()
        for i = 1, #args.tabs do
            local tab = args.tabs[i]    ---@type tabbar_tab

            e.w_set_cur(tab._start_x, 1)

            if e.value == i then
                e.w_set_fgd(tab.color.fgd)
                e.w_set_bkg(tab.color.bkg)
            else
                e.w_set_fgd(e.fg_bg.fgd)
                e.w_set_bkg(e.fg_bg.bkg)
            end

            e.w_write(util.pad(tab.name, button_width))
        end
    end

    -- check which tab a given x is within
    ---@return integer|nil button index or nil if not within a tab
    local function which_tab(x)
        for i = 1, #args.tabs do
            local tab = args.tabs[i]    ---@type tabbar_tab
            if x >= tab._start_x and x <= tab._end_x then return i end
        end

        return nil
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        -- determine what was pressed
        if e.enabled and core.events.was_clicked(event.type) then
            -- a button may have been pressed, which one was it?
            local tab_ini = which_tab(event.initial.x)
            local tab_cur = which_tab(event.current.x)

            -- mouse up must always have started with a mouse down on the same tab to count as a click
            -- tap always has identical coordinates, so this always passes for taps
            if tab_ini == tab_cur and tab_cur ~= nil then
                e.value = tab_cur
                e.redraw()
                args.callback(e.value)
            end
        end
    end

    -- set the value
    ---@param val integer new value
    function e.set_value(val)
        e.value = val
        e.redraw()
    end

    -- initial draw
    e.redraw()

    return e.complete()
end

return tabbar
