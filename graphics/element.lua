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
---@field y? integer next line if omitted
---@field offset_x? integer 0 if omitted
---@field offset_y? integer 0 if omitted
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors

---@alias graphics_args graphics_args_generic
---|waiting_args
---|hazard_button_args
---|multi_button_args
---|push_button_args
---|radio_button_args
---|spinbox_args
---|switch_button_args
---|alarm_indicator_light
---|core_map_args
---|data_indicator_args
---|hbar_args
---|icon_indicator_args
---|indicator_led_args
---|indicator_led_pair_args
---|indicator_led_rgb_args
---|indicator_light_args
---|power_indicator_args
---|rad_indicator_args
---|state_indicator_args
---|tristate_indicator_light_args
---|vbar_args
---|colormap_args
---|displaybox_args
---|div_args
---|pipenet_args
---|rectangle_args
---|textbox_args
---|tiling_args

-- a base graphics element, should not be created on its own
---@nodiscard
---@param args graphics_args arguments
function element.new(args)
    local self = {
        id = -1,
        elem_type = debug.getinfo(2).name,
        define_completed = false,
        p_window = nil, ---@type table
        position = { x = 1, y = 1 },
        child_offset = { x = 0, y = 0 },
        bounds = { x1 = 1, y1 = 1, x2 = 1, y2 = 1},
        next_y = 1,
        children = {},
        mt = {}
    }

    ---@class graphics_template
    local protected = {
        enabled = true,
        value = nil,    ---@type any
        window = nil,   ---@type table
        fg_bg = core.graphics.cpair(colors.white, colors.black),
        frame = core.graphics.gframe(1, 1, 1, 1)
    }

    -- element as string
    function self.mt.__tostring()
        return "graphics.element{" .. self.elem_type .. "} @ " .. tostring(self)
    end

    ---@class graphics_element
    local public = {}

    setmetatable(public, self.mt)

    -------------------------
    -- PROTECTED FUNCTIONS --
    -------------------------

    -- prepare the template
    ---@param offset_x integer x offset
    ---@param offset_y integer y offset
    ---@param next_y integer next line if no y was provided
    function protected.prepare_template(offset_x, offset_y, next_y)
        -- get frame coordinates/size
        if args.gframe ~= nil then
            protected.frame.x = args.gframe.x
            protected.frame.y = args.gframe.y
            protected.frame.w = args.gframe.w
            protected.frame.h = args.gframe.h
        else
            local w, h = self.p_window.getSize()
            protected.frame.x = args.x or 1

            if args.parent ~= nil then
                protected.frame.y = args.y or (next_y - offset_y)
            else
                protected.frame.y = args.y or next_y
            end

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
            -- constrain to parent inner width/height
            local w, h = self.p_window.getSize()
            f.w = math.min(f.w, w - ((2 * offset_x) + (f.x - 1)))
            f.h = math.min(f.h, h - ((2 * offset_y) + (f.y - 1)))

            -- offset x/y
            f.x = x + offset_x
            f.y = y + offset_y
        end

        -- check frame
        assert(f.x >= 1, "graphics.element{" .. self.elem_type .. "}: frame x not >= 1")
        assert(f.y >= 1, "graphics.element{" .. self.elem_type .. "}: frame y not >= 1")
        assert(f.w >= 1, "graphics.element{" .. self.elem_type .. "}: frame width not >= 1")
        assert(f.h >= 1, "graphics.element{" .. self.elem_type .. "}: frame height not >= 1")

        -- create window
        protected.window = window.create(self.p_window, f.x, f.y, f.w, f.h, true)

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
    end

    -- handle a touch event
    ---@param event table monitor_touch event
    function protected.handle_touch(event)
    end

    -- handle data value changes
    ---@vararg any value(s)
    function protected.on_update(...)
    end

    -- callback on control press responses
    ---@param result any
    function protected.response_callback(result)
    end

    -- get value
    ---@nodiscard
    function protected.get_value()
        return protected.value
    end

    -- set value
    ---@param value any value to set
    function protected.set_value(value)
    end

    -- set minimum input value
    ---@param min integer minimum allowed value
    function protected.set_min(min)
    end

    -- set maximum input value
    ---@param max integer maximum allowed value
    function protected.set_max(max)
    end

    -- enable the control
    function protected.enable()
    end

    -- disable the control
    function protected.disable()
    end

    -- custom recolor command, varies by element if implemented
    ---@vararg cpair|color color(s)
    function protected.recolor(...)
    end

    -- custom resize command, varies by element if implemented
    ---@vararg integer sizing
    function protected.resize(...)
    end

    -- start animations
    function protected.start_anim()
    end

    -- stop animations
    function protected.stop_anim()
    end

    -- get public interface
    ---@nodiscard
    ---@return graphics_element element, element_id id
    function protected.get() return public, self.id end

    -----------
    -- SETUP --
    -----------

    -- get the parent window
    self.p_window = args.window
    if self.p_window == nil and args.parent ~= nil then
        self.p_window = args.parent.window()
    end

    -- check window
    assert(self.p_window, "graphics.element{" .. self.elem_type .. "}: no parent window provided")

    -- prepare the template
    if args.parent == nil then
        protected.prepare_template(0, 0, 1)
    else
        self.id = args.parent.__add_child(args.id, protected)
    end

    ----------------------
    -- PUBLIC FUNCTIONS --
    ----------------------

    -- get the window object
    ---@nodiscard
    function public.window() return protected.window end

    -- CHILD ELEMENTS --

    -- add a child element
    ---@nodiscard
    ---@param key string|nil id
    ---@param child graphics_template
    ---@return integer|string key
    function public.__add_child(key, child)
        -- offset first automatic placement
        if self.next_y <= self.child_offset.y then
            self.next_y = self.child_offset.y + 1
        end

        child.prepare_template(self.child_offset.x, self.child_offset.y, self.next_y)

        self.next_y = child.frame.y + child.frame.h

        local child_element = child.get()

        if key == nil then
            table.insert(self.children, child_element)
            return #self.children
        else
            self.children[key] = child_element
            return key
        end
    end

    -- get a child element
    ---@nodiscard
    ---@return graphics_element
    function public.get_child(key) return self.children[key] end

    -- remove child
    ---@param key string|integer
    function public.remove(key) self.children[key] = nil end

    -- attempt to get a child element by ID (does not include this element itself)
    ---@nodiscard
    ---@param id element_id
    ---@return graphics_element|nil element
    function public.get_element_by_id(id)
        if self.children[id] == nil then
            for _, child in pairs(self.children) do
                local elem = child.get_element_by_id(id)
                if elem ~= nil then return elem end
            end
        else
            return self.children[id]
        end

        return nil
    end

    -- AUTO-PLACEMENT --

    -- skip a line for automatically placed elements
    function public.line_break()
        self.next_y = self.next_y + 1
    end

    -- PROPERTIES --

    -- get the foreground/background colors
    ---@nodiscard
    ---@return cpair fg_bg
    function public.get_fg_bg()
        return protected.fg_bg
    end

    -- get element x
    ---@nodiscard
    ---@return integer x
    function public.get_x()
        return protected.frame.x
    end

    -- get element y
    ---@nodiscard
    ---@return integer y
    function public.get_y()
        return protected.frame.y
    end

    -- get element width
    ---@nodiscard
    ---@return integer width
    function public.width()
        return protected.frame.w
    end

    -- get element height
    ---@nodiscard
    ---@return integer height
    function public.height()
        return protected.frame.h
    end

    -- get the element value
    ---@nodiscard
    ---@return any value
    function public.get_value()
        return protected.get_value()
    end

    -- set the element value
    ---@param value any new value
    function public.set_value(value)
        protected.set_value(value)
    end

    -- set minimum input value
    ---@param min integer minimum allowed value
    function public.set_min(min)
        protected.set_min(min)
    end

    -- set maximum input value
    ---@param max integer maximum allowed value
    function public.set_max(max)
        protected.set_max(max)
    end

    -- enable the element
    function public.enable()
        protected.enabled = true
        protected.enable()
    end

    -- disable the element
    function public.disable()
        protected.enabled = false
        protected.disable()
    end

    -- custom recolor command, varies by element if implemented
    ---@vararg cpair|color color(s)
    function public.recolor(...)
        protected.recolor(...)
    end

    -- resize attributes of the element value if supported
    ---@vararg number dimensions (element specific)
    function public.resize(...)
        protected.resize(...)
    end

    -- FUNCTION CALLBACKS --

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
    ---@vararg any new data
    function public.update(...)
        protected.on_update(...)
    end

    -- on a control request response
    ---@param result any
    function public.on_response(result)
        protected.response_callback(result)
    end

    -- VISIBILITY --

    -- show the element
    function public.show()
        protected.window.setVisible(true)
        protected.start_anim()

        for i = 1, #self.children do
            self.children[i].show()
        end
    end

    -- hide the element
    function public.hide()
        protected.stop_anim()
        for i = 1, #self.children do
            self.children[i].hide()
        end

        protected.window.setVisible(false)
    end

    -- re-draw the element
    function public.redraw()
        protected.window.redraw()
    end

    return protected
end

return element
