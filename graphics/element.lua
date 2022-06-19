--
-- Generic Graphics Element
--

local core = require("graphics.core")
local log  = require("scada-common.log")
local util = require("scada-common.util")

local element = {}

---@class graphics_args_generic
---@field window? table
---@field parent? graphics_element
---@field x? integer 1 if omitted
---@field y? integer 1 if omitted
---@field offset_x? integer 0 if omitted
---@field offset_y? integer 0 if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors

-- a base graphics element, should not be created on its own
---@param args graphics_args_generic arguments
function element.new(args)
    local self = {
        elem_type = debug.getinfo(2).name,
        p_window = nil, ---@type table
        position = { x = 1, y = 1 },
        child_offset = { x = 0, y = 0 },
        bounds = { x1 = 1, y1 = 1, x2 = 1, y2 = 1}
    }

    ---@fixme remove debug
    log.dmesg("new " .. self.elem_type)

    local protected = {
        window = nil,   ---@type table
        fg_bg = core.graphics.cpair(colors.white, colors.black),
        frame = core.graphics.gframe(1, 1, 1, 1)
    }

    -- SETUP --

    -- get the parent window
    self.p_window = args.window
    if self.p_window == nil and args.parent ~= nil then
        self.p_window = args.parent.window()
    end

    -- check window
    assert(self.p_window, "graphics.element: no parent window provided")

    -- get frame coordinates/size
    if args.gframe ~= nil then
        protected.frame.x = args.gframe.x
        protected.frame.y = args.gframe.y
        protected.frame.w = args.gframe.w
        protected.frame.h = args.gframe.h
    else
        local w, h = self.p_window.getSize()
        protected.frame.x = args.x or 1
        protected.frame.y = args.y or 1
        protected.frame.w = args.width or w
        protected.frame.h = args.height or h
    end

    -- inner offsets
    if args.offset_x ~= nil then self.child_offset.x = args.offset_x end
    if args.offset_y ~= nil then self.child_offset.y = args.offset_y end

    -- check frame
    assert(protected.frame.x >= 1, "graphics.element: frame x not >= 1")
    assert(protected.frame.y >= 1, "graphics.element: frame y not >= 1")
    assert(protected.frame.w >= 1, "graphics.element: frame width not >= 1")
    assert(protected.frame.h >= 1, "graphics.element: frame height not >= 1")

    -- create window
    local f = protected.frame
    local x = f.x
    local y = f.y

    if args.parent ~= nil then
        local offset_x, offset_y = args.parent.get_offset()
        x = x + offset_x
        y = y + offset_y
    end

    protected.window = window.create(self.p_window, x, y, f.w, f.h, true)

    -- init colors
    if args.fg_bg ~= nil then
        protected.fg_bg = args.fg_bg
    elseif args.parent ~= nil then
        protected.fg_bg = args.parent.get_fg_bg()
    end

    -- set colors
    protected.window.setBackgroundColor(protected.fg_bg.bkg)
    protected.window.setTextColor(protected.fg_bg.fgd)
    protected.window.clear()

    -- record position
    self.position.x, self.position.y = protected.window.getPosition()

    -- calculate bounds
    self.bounds.x1 = self.position.x
    self.bounds.x2 = self.position.x + f.w - 1
    self.bounds.y1 = self.position.y
    self.bounds.y2 = self.position.y + f.h - 1

    -- PROTECTED FUNCTIONS --

    -- handle a touch event
    ---@param event table monitor_touch event
    function protected.handle_touch(event)
    end

    -- handle data value changes
    function protected.on_update(...)
    end

    -- get control value
    function protected.get_value()
        return nil
    end

    ---@class graphics_element
    local public = {}

    -- get public interface
    function protected.get() return public end

    -- PUBLIC FUNCTIONS --

    -- get the window object
    function public.window() return protected.window end

    -- get the foreground/background colors
    function public.get_fg_bg() return protected.fg_bg end

    -- get offset from this element's frame
    ---@return integer x, integer y
    function public.get_offset()
        return self.child_offset.x, self.child_offset.y
    end

    -- handle a monitor touch
    ---@param event monitor_touch monitor touch event
    function public.handle_touch(event)
        local in_x = event.x >= self.bounds.x1 and event.x <= self.bounds.x2
        local in_y = event.y >= self.bounds.y1 and event.y <= self.bounds.y2

        if in_x and in_y then
            -- handle the touch event, transformed into the window frame
            protected.handle_touch(core.events.touch(event.monitor,
                (event.x - self.position.x) + 1,
                (event.y - self.position.y) + 1))
        end
    end

    -- draw the element given new data
    function public.update(...)
        protected.on_update(...)
    end

    -- get the control value reading
    function public.get_value()
        return protected.get_value()
    end

    -- show the element
    function public.show()
        protected.window.setVisible(true)
    end

    -- hide the element
    function public.hide()
        protected.window.setVisible(false)
    end

    -- re-draw the element
    function public.redraw()
        protected.window.redraw()
    end

    return protected
end

return element
