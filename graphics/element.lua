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
---@field width? integer parent width if omitted
---@field height? integer parent height if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

---@alias graphics_args graphics_args_generic
---|waiting_args
---|checkbox_args
---|hazard_button_args
---|multi_button_args
---|push_button_args
---|radio_button_args
---|sidebar_args
---|spinbox_args
---|switch_button_args
---|tabbar_args
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
---|listbox_args
---|multipane_args
---|pipenet_args
---|rectangle_args
---|textbox_args
---|tiling_args

---@class element_subscription
---@field ps psil ps used
---@field key string data key
---@field func function callback

-- a base graphics element, should not be created on its own
---@nodiscard
---@param args graphics_args arguments
---@param child_offset_x? integer mouse event offset x
---@param child_offset_y? integer mouse event offset y
function element.new(args, child_offset_x, child_offset_y)
    local self = {
        id = nil,                                       ---@type element_id|nil
        elem_type = debug.getinfo(2).name,
        define_completed = false,
        p_window = nil,                                 ---@type table
        position = { x = 1, y = 1 },                    ---@type coordinate_2d
        bounds = { x1 = 1, y1 = 1, x2 = 1, y2 = 1 },    ---@class element_bounds
        next_y = 1,
        subscriptions = {},
        mt = {}
    }

    ---@class graphics_base
    local protected = {
        enabled = true,
        value = nil,            ---@type any
        window = nil,           ---@type table
        content_window = nil,   ---@type table|nil
        fg_bg = core.cpair(colors.white, colors.black),
        frame = core.gframe(1, 1, 1, 1),
        children = {}
    }

    local name_brief = "graphics.element{" .. self.elem_type .. "}: "

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
    ---@param offset_x integer x offset for mouse events
    ---@param offset_y integer y offset for mouse events
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
            protected.frame.y = args.y or next_y
            protected.frame.w = args.width or w
            protected.frame.h = args.height or h
        end

        -- adjust window frame if applicable
        local f = protected.frame
        if args.parent ~= nil then
            -- constrain to parent inner width/height
            local w, h = self.p_window.getSize()
            f.w = math.min(f.w, w - (f.x - 1))
            f.h = math.min(f.h, h - (f.y - 1))
        end

        -- check frame
        assert(f.x >= 1, name_brief .. "frame x not >= 1")
        assert(f.y >= 1, name_brief .. "frame y not >= 1")
        assert(f.w >= 1, name_brief .. "frame width not >= 1")
        assert(f.h >= 1, name_brief .. "frame height not >= 1")

        -- create window
        protected.window = window.create(self.p_window, f.x, f.y, f.w, f.h, args.hidden ~= true)

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

        -- shift per parent child offset
        self.position.x = self.position.x + offset_x
        self.position.y = self.position.y + offset_y

        -- calculate mouse event bounds
        self.bounds.x1 = self.position.x
        self.bounds.x2 = self.position.x + f.w - 1
        self.bounds.y1 = self.position.y
        self.bounds.y2 = self.position.y + f.h - 1
    end

    -- check if a coordinate relative to the parent is within the bounds of this element
    ---@param x integer
    ---@param y integer
    function protected.in_window_bounds(x, y)
        local in_x = x >= self.bounds.x1 and x <= self.bounds.x2
        local in_y = y >= self.bounds.y1 and y <= self.bounds.y2
        return in_x and in_y
    end

    -- check if a coordinate relative to this window is within the bounds of this element
    ---@param x integer
    ---@param y integer
    function protected.in_frame_bounds(x, y)
        local in_x = x >= 1 and x <= protected.frame.w
        local in_y = y >= 1 and y <= protected.frame.h
        return in_x and in_y
    end

-- luacheck: push ignore
---@diagnostic disable: unused-local, unused-vararg

    -- handle a child element having been added
    ---@param id element_id element identifier
    ---@param child graphics_element child element
    function protected.on_added(id, child)
    end

    -- handle a child element having been removed
    ---@param id element_id element identifier
    function protected.on_removed(id)
    end

    -- handle a mouse event
    ---@param event mouse_interaction mouse interaction event
    function protected.handle_mouse(event)
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

-- luacheck: pop
---@diagnostic enable: unused-local, unused-vararg

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

    -- report completion of element instantiation and get the public interface
    ---@nodiscard
    ---@return graphics_element element, element_id id
    function protected.complete()
        if args.parent ~= nil then args.parent.__child_ready(self.id, public) end
        return public, self.id
    end

    -----------
    -- SETUP --
    -----------

    -- get the parent window
    self.p_window = args.window
    if self.p_window == nil and args.parent ~= nil then
        self.p_window = args.parent.window()
    end

    -- check window
    assert(self.p_window, name_brief .. "no parent window provided")

    -- prepare the template
    if args.parent == nil then
        self.id = args.id or "__ROOT__"
        protected.prepare_template(0, 0, 1)
    else
        self.id = args.parent.__add_child(args.id, protected)
    end

    ----------------------
    -- PUBLIC FUNCTIONS --
    ----------------------

    -- get the window object
    ---@nodiscard
    function public.window() return protected.content_window or protected.window end

    -- delete this element (hide and unsubscribe from PSIL)
    function public.delete()
        local fg_bg = protected.fg_bg

        if args.parent ~= nil then
            -- grab parent fg/bg so we can clear cleanly as a child element
            fg_bg = args.parent.get_fg_bg()
        end

        -- clear, hide, and stop animations
        protected.window.setBackgroundColor(fg_bg.bkg)
        protected.window.setTextColor(fg_bg.fgd)
        protected.window.clear()
        public.hide()

        -- unsubscribe from PSIL
        for i = 1, #self.subscriptions do
            local s = self.subscriptions[i] ---@type element_subscription
            s.ps.unsubscribe(s.key, s.func)
        end

        -- delete all children
        for k, v in pairs(protected.children) do
            v.delete()
            protected.children[k] = nil
        end

        if args.parent ~= nil then
            -- remove self from parent
            args.parent.__remove_child(self.id)
        end
    end

    -- ELEMENT TREE --

    -- add a child element
    ---@nodiscard
    ---@param key string|nil id
    ---@param child graphics_base
    ---@return integer|string key
    function public.__add_child(key, child)
        child.prepare_template(child_offset_x or 0, child_offset_y or 0, self.next_y)

        self.next_y = child.frame.y + child.frame.h

        local child_element = child.get()

        if key == nil then
            table.insert(protected.children, child_element)
            return #protected.children
        else
            protected.children[key] = child_element
            return key
        end
    end

    -- remove a child element
    ---@param key element_id id
    function public.__remove_child(key)
        if protected.children[key] ~= nil then
            protected.on_removed(key)
            protected.children[key] = nil
        end
    end

    -- actions to take upon a child element becoming ready (initial draw/construction completed)
    ---@param key element_id id
    ---@param child graphics_element
    function public.__child_ready(key, child)
        protected.on_added(key, child)
    end

    -- get a child element
    ---@nodiscard
    ---@param id element_id
    ---@return graphics_element
    function public.get_child(id) return protected.children[id] end

    -- remove a child element
    ---@param id element_id
    function public.remove(id)
        if protected.children[id] ~= nil then
            protected.children[id].delete()
            protected.on_removed(id)
            protected.children[id] = nil
        end
    end

    -- attempt to get a child element by ID (does not include this element itself)
    ---@nodiscard
    ---@param id element_id
    ---@return graphics_element|nil element
    function public.get_element_by_id(id)
        if protected.children[id] == nil then
            for _, child in pairs(protected.children) do
                local elem = child.get_element_by_id(id)
                if elem ~= nil then return elem end
            end
        else
            return protected.children[id]
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
    function public.get_width()
        return protected.frame.w
    end

    -- get element height
    ---@nodiscard
    ---@return integer height
    function public.get_height()
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

    -- reposition the element window<br>
    -- offsets relative to parent frame are where (1, 1) would be on top of the parent's top left corner
    ---@param x integer x position relative to parent frame
    ---@param y integer y position relative to parent frame
    function public.reposition(x, y)
        protected.window.reposition(x, y)
    end

    -- FUNCTION CALLBACKS --

    -- handle a monitor touch or mouse click
    ---@param event mouse_interaction mouse interaction event
    function public.handle_mouse(event)
        local x_ini, y_ini = event.initial.x, event.initial.y

        local ini_in = protected.in_window_bounds(x_ini, y_ini)

        if ini_in then
            local event_T = core.events.mouse_transposed(event, self.position.x, self.position.y)

            -- handle the mouse event then pass to children
            protected.handle_mouse(event_T)
            for _, child in pairs(protected.children) do child.handle_mouse(event_T) end
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

    -- register a callback with a PSIL, allowing for automatic unregister on delete<br>
    -- do not use graphics elements directly with PSIL subscribe()
    ---@param ps psil PSIL to subscribe to
    ---@param key string key to subscribe to
    ---@param func function function to link
    function public.register(ps, key, func)
        table.insert(self.subscriptions, { ps = ps, key = key, func = func })
        ps.subscribe(key, func)
    end

    -- VISIBILITY & ANIMATIONS --

    -- show the element and enables animations by default
    ---@param animate? boolean true (default) to automatically resume animations
    function public.show(animate)
        protected.window.setVisible(true)
        if animate ~= false then public.animate_all() end
    end

    -- hide the element and disables animations<br>
    -- this alone does not cause an element to be fully hidden, it only prevents updates from being shown<br>
    ---@see graphics_element.content_redraw
    function public.hide()
        public.freeze_all() -- stop animations for efficiency/performance
        protected.window.setVisible(false)
    end

    -- start/resume animation(s)
    function public.animate()
        protected.start_anim()
    end

    -- start/resume animation(s) for this element and all its children<br>
    -- only animates if a window is visible
    function public.animate_all()
        if protected.window.isVisible() then
            public.animate()
            for _, child in pairs(protected.children) do child.animate_all() end
        end
    end

    -- freeze animation(s)
    function public.freeze()
        protected.stop_anim()
    end

    -- freeze animation(s) for this element and all its children
    function public.freeze_all()
        public.freeze()
        for _, child in pairs(protected.children) do child.freeze_all() end
    end

    -- re-draw the element
    function public.redraw()
        protected.window.redraw()
    end

    -- if a content window is set, clears it then re-draws all children
    function public.content_redraw()
        if protected.content_window ~= nil then
            protected.content_window.clear()
            for _, child in pairs(protected.children) do child.redraw() end
        end
    end

    return protected
end

return element
