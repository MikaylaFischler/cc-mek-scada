--
-- Generic Graphics Element
--

local core = require("graphics.core")

local element = {}

---@class graphics_args_generic
---@field window? table
---@field parent? graphics_element
---@field id? string element id
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
        id = -1,
        elem_type = debug.getinfo(2).name,
        define_completed = false,
        p_window = nil, ---@type table
        position = { x = 1, y = 1 },
        child_offset = { x = 0, y = 0 },
        bounds = { x1 = 1, y1 = 1, x2 = 1, y2 = 1},
        children = {},
        mt = {}
    }

    ---@class graphics_template
    local protected = {
        window = nil,   ---@type table
        fg_bg = core.graphics.cpair(colors.white, colors.black),
        frame = core.graphics.gframe(1, 1, 1, 1)
    }

    -- element as string
    function self.mt.__tostring()
        return "graphics.element{" .. self.elem_type .. "} @ " .. tostring(self)
    end

    -- SETUP --

    -- get the parent window
    self.p_window = args.window
    if self.p_window == nil and args.parent ~= nil then
        self.p_window = args.parent.window()
    end

    -- check window
    assert(self.p_window, "graphics.element{" .. self.elem_type .. "}: no parent window provided")

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

    -- adjust window frame if applicable
    local f = protected.frame
    local x = f.x
    local y = f.y

    -- apply offsets
    if args.parent ~= nil then
        -- offset x/y
        local offset_x, offset_y = args.parent.get_offset()
        x = x + offset_x
        y = y + offset_y

        -- constrain to parent inner width/height
        local w, h = self.p_window.getSize()
        f.w = math.min(f.w, w - ((2 * offset_x) + (f.x - 1)))
        f.h = math.min(f.h, h - ((2 * offset_y) + (f.y - 1)))
    end

    -- check frame
    assert(f.x >= 1, "graphics.element{" .. self.elem_type .. "}: frame x not >= 1")
    assert(f.y >= 1, "graphics.element{" .. self.elem_type .. "}: frame y not >= 1")
    assert(f.w >= 1, "graphics.element{" .. self.elem_type .. "}: frame width not >= 1")
    assert(f.h >= 1, "graphics.element{" .. self.elem_type .. "}: frame height not >= 1")

    -- create window
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

    setmetatable(public, self.mt)

    -- get public interface and wrap up element creation
    ---@return graphics_element element, element_id id
    function protected.complete()
        if not self.define_completed then
            self.define_completed = true

            if args.parent then
                self.id = args.parent.__add_child(args.id, public)
            end

            return public, self.id
        else
            assert("graphics.element{" .. self.elem_type .. "}: illegal duplicate call to complete()")
        end
    end

    -- PUBLIC FUNCTIONS --

    -- get the window object
    function public.window() return protected.window end

    -- add a child element
    ---@param key string|nil id
    ---@param child graphics_element
    ---@return graphics_element element, integer|string key
    function public.__add_child(key, child)
        if key == nil then
            table.insert(self.children, child)
            return child, #self.children
        else
            self.children[key] = child
            return child, key
        end
    end

    -- get a child element
    ---@return graphics_element
    function public.get_child(key) return self.children[key] end

    -- remove child
    ---@param key string|integer
    function public.remove(key) self.children[key] = nil end

    ---@param id element_id
    function public.get_element_by_id(id)
    end

    -- get the foreground/background colors
    function public.get_fg_bg() return protected.fg_bg end

    -- get offset from this element's frame
    ---@return integer x, integer y
    function public.get_offset()
        return self.child_offset.x, self.child_offset.y
    end

    -- get element width
    function public.width()
        return protected.frame.w
    end

    -- get element height
    function public.height()
        return protected.frame.h
    end

    -- handle a monitor touch
    ---@param event monitor_touch monitor touch event
    function public.handle_touch(event)
        local in_x = event.x >= self.bounds.x1 and event.x <= self.bounds.x2
        local in_y = event.y >= self.bounds.y1 and event.y <= self.bounds.y2

        if in_x and in_y then
            local event_T = core.events.touch(event.monitor, (event.x - self.position.x) + 1, (event.y - self.position.y) + 1)

            -- handle the touch event, transformed into the window frame
            protected.handle_touch(event_T)

            -- pass on touch event to children
            for _, val in pairs(self.children) do val.handle_touch(event_T) end
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
