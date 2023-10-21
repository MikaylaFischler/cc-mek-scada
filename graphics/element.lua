--
-- Generic Graphics Element
--

local util = require("scada-common.util")

local core = require("graphics.core")

local events = core.events

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
---@field can_focus? boolean true if this element can be focused, false by default

---@alias graphics_args graphics_args_generic
---|waiting_args
---|app_button_args
---|checkbox_args
---|hazard_button_args
---|multi_button_args
---|push_button_args
---|radio_2d_args
---|radio_button_args
---|sidebar_args
---|spinbox_args
---|switch_button_args
---|tabbar_args
---|number_field_args
---|text_field_args
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

-- more detailed assert message for element verification
---@param condition any assert condition
---@param msg string assert message
---@param callstack_offset? integer shift value to change targets of debug.getinfo()
function element.assert(condition, msg, callstack_offset)
    callstack_offset = callstack_offset or 0
    local caller = debug.getinfo(3 + callstack_offset)
    assert(condition, util.c(caller.source, ":", caller.currentline, "{", debug.getinfo(2 + callstack_offset).name, "}: ", msg))
end

-- a base graphics element, should not be created on its own
---@nodiscard
---@param args graphics_args arguments
---@param child_offset_x? integer mouse event offset x
---@param child_offset_y? integer mouse event offset y
function element.new(args, child_offset_x, child_offset_y)
    local self = {
        id = nil,                                       ---@type element_id|nil
        is_root = args.parent == nil,
        elem_type = debug.getinfo(2).name,
        define_completed = false,
        p_window = nil,                                 ---@type table
        position = events.new_coord_2d(1, 1),
        bounds = { x1 = 1, y1 = 1, x2 = 1, y2 = 1 },    ---@class element_bounds
        offset_x = 0,
        offset_y = 0,
        next_y = 1,                                     -- next child y coordinate
        next_id = 0,                                    -- next child ID
        subscriptions = {},
        button_down = { events.new_coord_2d(-1, -1), events.new_coord_2d(-1, -1), events.new_coord_2d(-1, -1) },
        focused = false,
        mt = {}
    }

    ---@class graphics_base
    local protected = {
        enabled = true,
        value = nil,            ---@type any
        window = nil,           ---@type table
        content_window = nil,   ---@type table|nil
        mouse_window_shift = { x = 0, y = 0 },
        fg_bg = core.cpair(colors.white, colors.black),
        frame = core.gframe(1, 1, 1, 1),
        children = {},
        child_id_map = {}
    }

    -- element as string
    function self.mt.__tostring()
        return util.c("graphics.element{", self.elem_type, "} @ ", self)
    end

    ---@class graphics_element
    local public = {}

    setmetatable(public, self.mt)

    -----------------------
    -- PRIVATE FUNCTIONS --
    -----------------------

    -- use tab to jump to the next focusable field
    ---@param reverse boolean
    local function _tab_focusable(reverse)
        local first_f = nil ---@type graphics_element|nil
        local prev_f = nil  ---@type graphics_element|nil
        local cur_f = nil   ---@type graphics_element|nil
        local done = false

        ---@param elem graphics_element
        local function handle_element(elem)
            if elem.is_visible() and elem.is_focusable() and elem.is_enabled() then
                if first_f == nil then first_f = elem end

                if cur_f == nil then
                    if elem.is_focused() then
                        cur_f = elem
                        if (not done) and (reverse and prev_f ~= nil) then
                            cur_f.unfocus()
                            prev_f.focus()
                            done = true
                        end
                    end
                else
                    if elem.is_focused() then
                        elem.unfocus()
                    elseif not (reverse or done) then
                        cur_f.unfocus()
                        elem.focus()
                        done = true
                    end
                end

                prev_f = elem
            end
        end

        ---@param children table
        local function traverse(children)
            for i = 1, #children do
                local child = children[i]   ---@type graphics_base
                handle_element(child.get())
                if child.get().is_visible() then traverse(child.children) end
            end
        end

        traverse(protected.children)

        -- if no element was focused, wrap focus
        if first_f ~= nil and not done then
            if reverse then
                if cur_f ~= nil then cur_f.unfocus() end
                if prev_f ~= nil then prev_f.focus() end
            else
                if cur_f ~= nil then cur_f.unfocus() end
                first_f.focus()
            end
        end
    end

    -------------------------
    -- PROTECTED FUNCTIONS --
    -------------------------

    -- prepare the template
    ---@param offset_x integer x offset for mouse events
    ---@param offset_y integer y offset for mouse events
    ---@param next_y integer next line if no y was provided
    function protected.prepare_template(offset_x, offset_y, next_y)
        -- record offsets in case there is a reposition
        self.offset_x = offset_x
        self.offset_y = offset_y

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
        element.assert(f.x >= 1, "frame x not >= 1", 3)
        element.assert(f.y >= 1, "frame y not >= 1", 3)
        element.assert(f.w >= 1, "frame width not >= 1", 3)
        element.assert(f.h >= 1, "frame height not >= 1", 3)

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

        -- alias functions

        -- window set cursor position
        ---@param x integer
        ---@param y integer
        function protected.w_set_cur(x, y) protected.window.setCursorPos(x, y) end

        -- set background color
        ---@param c color
        function protected.w_set_bkg(c) protected.window.setBackgroundColor(c) end

        -- set foreground (text) color
        ---@param c color
        function protected.w_set_fgd(c) protected.window.setTextColor(c) end

        -- write text
        ---@param str string
        function protected.w_write(str) protected.window.write(str) end

        -- blit text
        ---@param str string
        ---@param fg string
        ---@param bg string
        function protected.w_blit(str, fg, bg) protected.window.blit(str, fg, bg) end
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

    -- protected version of public is_focused()
    ---@nodiscard
    ---@return boolean is_focused
    function protected.is_focused() return self.focused end

    -- defocus this element
    function protected.defocus() public.unfocus_all() end

    -- focus this element and take away focus from all other elements
    function protected.take_focus() args.parent.__focus_child(public) end

    -- action handlers --

-- luacheck: push ignore
---@diagnostic disable: unused-local, unused-vararg

    -- handle a child element having been added
    ---@param id element_id element identifier
    ---@param child graphics_element child element
    function protected.on_added(id, child) end

    -- handle a child element having been removed
    ---@param id element_id element identifier
    function protected.on_removed(id) end

    -- handle enabled
    function protected.on_enabled() end

    -- handle disabled
    function protected.on_disabled() end

    -- handle this element having been focused
    function protected.on_focused() end

    -- handle this element having been unfocused
    function protected.on_unfocused() end

    -- handle this element having had a child focused
    ---@param child graphics_element
    function protected.on_child_focused(child) end

    -- handle this element having been shown
    function protected.on_shown() end

    -- handle this element having been hidden
    function protected.on_hidden() end

    -- handle a mouse event
    ---@param event mouse_interaction mouse interaction event
    function protected.handle_mouse(event) end

    -- handle a keyboard event
    ---@param event key_interaction key interaction event
    function protected.handle_key(event) end

    -- handle a paste event
    ---@param text string pasted text
    function protected.handle_paste(text) end

    -- handle data value changes
    ---@vararg any value(s)
    function protected.on_update(...) end

    -- callback on control press responses
    ---@param result any
    function protected.response_callback(result) end

    -- accessors and control --

    -- get value
    ---@nodiscard
    function protected.get_value() return protected.value end

    -- set value
    ---@param value any value to set
    function protected.set_value(value) end

    -- set minimum input value
    ---@param min integer minimum allowed value
    function protected.set_min(min) end

    -- set maximum input value
    ---@param max integer maximum allowed value
    function protected.set_max(max) end

    -- custom recolor command, varies by element if implemented
    ---@vararg cpair|color color(s)
    function protected.recolor(...) end

    -- custom resize command, varies by element if implemented
    ---@vararg integer sizing
    function protected.resize(...) end

-- luacheck: pop
---@diagnostic enable: unused-local, unused-vararg

    -- re-draw this element
    function protected.redraw() end

    -- start animations
    function protected.start_anim() end

    -- stop animations
    function protected.stop_anim() end

    -----------
    -- SETUP --
    -----------

    -- get the parent window
    self.p_window = args.window
    if self.p_window == nil and args.parent ~= nil then
        self.p_window = args.parent.window()
    end

    -- check window
    element.assert(self.p_window, "no parent window provided", 1)

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
            v.get().delete()
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

        local id = key  ---@type string|integer|nil
        if id == nil then
            id = self.next_id
            self.next_id = self.next_id + 1
        end

        table.insert(protected.children, child)

        protected.child_id_map[id] = #protected.children

        return id
    end

    -- remove a child element
    ---@param id element_id id
    function public.__remove_child(id)
        local index = protected.child_id_map[id]
        if protected.children[index] ~= nil then
            protected.on_removed(id)
            protected.children[index] = nil
            protected.child_id_map[id] = nil
        end
    end

    -- actions to take upon a child element becoming ready (initial draw/construction completed)
    ---@param key element_id id
    ---@param child graphics_element
    function public.__child_ready(key, child) protected.on_added(key, child) end

    -- focus solely on this child
    ---@param child graphics_element
    function public.__focus_child(child)
        if self.is_root then
            public.unfocus_all()
            child.focus()
        else args.parent.__focus_child(child) end
    end

    -- a child was focused, used to make sure it is actually visible to the user in the content frame
    ---@param child graphics_element
    function public.__child_focused(child)
        protected.on_child_focused(child)
        if not self.is_root then args.parent.__child_focused(public) end
    end

    -- get a child element
    ---@nodiscard
    ---@param id element_id
    ---@return graphics_element
    function public.get_child(id) return protected.children[protected.child_id_map[id]].get() end

    -- remove a child element
    ---@param id element_id
    function public.remove(id)
        local index = protected.child_id_map[id]
        if protected.children[index] ~= nil then
            protected.children[index].get().delete()
            protected.on_removed(id)
            protected.children[index] = nil
            protected.child_id_map[id] = nil
        end
    end

    -- remove all child elements and reset next y
    function public.remove_all()
        for i = 1, #protected.children do
            local child = protected.children[i].get()   ---@type graphics_element
            child.delete()
            protected.on_removed(child.get_id())
        end

        self.next_y = 1
        protected.children = {}
        protected.child_id_map = {}
    end

    -- attempt to get a child element by ID (does not include this element itself)
    ---@nodiscard
    ---@param id element_id
    ---@return graphics_element|nil element
    function public.get_element_by_id(id)
        local index = protected.child_id_map[id]
        if protected.children[index] == nil then
            for _, child in pairs(protected.children) do
                local elem = child.get().get_element_by_id(id)
                if elem ~= nil then return elem end
            end
        else return protected.children[index].get() end
    end

    -- AUTO-PLACEMENT --

    -- skip a line for automatically placed elements
    function public.line_break()
        self.next_y = self.next_y + 1
    end

    -- PROPERTIES --

    -- get element id
    ---@nodiscard
    ---@return element_id
    function public.get_id() return self.id end

    -- get element x
    ---@nodiscard
    ---@return integer x
    function public.get_x() return protected.frame.x end

    -- get element y
    ---@nodiscard
    ---@return integer y
    function public.get_y() return protected.frame.y end

    -- get element width
    ---@nodiscard
    ---@return integer width
    function public.get_width() return protected.frame.w end

    -- get element height
    ---@nodiscard
    ---@return integer height
    function public.get_height() return protected.frame.h end

    -- get the foreground/background colors
    ---@nodiscard
    ---@return cpair fg_bg
    function public.get_fg_bg() return protected.fg_bg end

    -- get the element value
    ---@nodiscard
    ---@return any value
    function public.get_value() return protected.get_value() end

    -- set the element value
    ---@param value any new value
    function public.set_value(value) protected.set_value(value) end

    -- set minimum input value
    ---@param min integer minimum allowed value
    function public.set_min(min) protected.set_min(min) end

    -- set maximum input value
    ---@param max integer maximum allowed value
    function public.set_max(max) protected.set_max(max) end

    -- check if this element is enabled
    function public.is_enabled() return protected.enabled end

    -- enable the element
    function public.enable()
        if not protected.enabled then
            protected.enabled = true
            protected.on_enabled()
        end
    end

    -- disable the element
    function public.disable()
        if protected.enabled then
            protected.enabled = false
            protected.on_disabled()
            public.unfocus_all()
        end
    end

    -- can this element be focused
    function public.is_focusable() return args.can_focus end

    -- is this element focused
    function public.is_focused() return self.focused end

    -- focus the element
    function public.focus()
        if args.can_focus and protected.enabled and not self.focused then
            self.focused = true
            protected.on_focused()
            if not self.is_root then args.parent.__child_focused(public) end
        end
    end

    -- unfocus this element
    function public.unfocus()
        if args.can_focus and self.focused then
            self.focused = false
            protected.on_unfocused()
        end
    end

    -- unfocus this element and all its children
    function public.unfocus_all()
        public.unfocus()
        for _, child in pairs(protected.children) do child.get().unfocus_all() end
    end

    -- custom recolor command, varies by element if implemented
    ---@vararg cpair|color color(s)
    function public.recolor(...) protected.recolor(...) end

    -- resize attributes of the element value if supported
    ---@vararg number dimensions (element specific)
    function public.resize(...) protected.resize(...) end

    -- reposition the element window<br>
    -- offsets relative to parent frame are where (1, 1) would be on top of the parent's top left corner
    ---@param x integer x position relative to parent frame
    ---@param y integer y position relative to parent frame
    function public.reposition(x, y)
        protected.window.reposition(x, y)

        -- record position
        self.position.x, self.position.y = protected.window.getPosition()

        -- shift per parent child offset
        self.position.x = self.position.x + self.offset_x
        self.position.y = self.position.y + self.offset_y

        -- calculate mouse event bounds
        self.bounds.x1 = self.position.x
        self.bounds.x2 = self.position.x + protected.frame.w - 1
        self.bounds.y1 = self.position.y
        self.bounds.y2 = self.position.y + protected.frame.h - 1
    end

    -- FUNCTION CALLBACKS --

    -- handle a monitor touch or mouse click if this element is visible
    ---@param event mouse_interaction mouse interaction event
    function public.handle_mouse(event)
        if protected.window.isVisible() then
            local x_ini, y_ini = event.initial.x, event.initial.y

            local ini_in = protected.in_window_bounds(x_ini, y_ini)

            if ini_in then
                if event.type == events.MOUSE_CLICK.UP or event.type == events.MOUSE_CLICK.DRAG then
                    -- make sure we don't handle mouse events that started before this element was made visible
                    if (event.initial.x ~= self.button_down[event.button].x) or (event.initial.y ~= self.button_down[event.button].y) then
                        return
                    end
                elseif event.type == events.MOUSE_CLICK.DOWN then
                    self.button_down[event.button] = event.initial
                end

                local event_T = events.mouse_transposed(event, self.position.x, self.position.y)
                protected.handle_mouse(event_T)

                -- shift child event if the content window has moved then pass to children
                local c_event_T = events.mouse_transposed(event_T, protected.mouse_window_shift.x + 1, protected.mouse_window_shift.y + 1)
                for _, child in pairs(protected.children) do child.get().handle_mouse(c_event_T) end
            elseif event.type == events.MOUSE_CLICK.DOWN or event.type == events.MOUSE_CLICK.TAP then
                -- clicked out, unfocus this element and children
                public.unfocus_all()
            end
        else
            -- don't track clicks while hidden
            self.button_down[event.button] = events.new_coord_2d(-1, -1)
        end
    end

    -- handle a keyboard click if this element is visible and focused
    ---@param event key_interaction keyboard interaction event
    function public.handle_key(event)
        if protected.window.isVisible() then
            if self.is_root and (event.type == events.KEY_CLICK.DOWN) and (event.key == keys.tab) then
                -- try to jump to the next/previous focusable field
                _tab_focusable(event.shift)
            else
                -- handle the key event then pass to children
                if self.focused then protected.handle_key(event) end
                for _, child in pairs(protected.children) do child.get().handle_key(event) end
            end
        end
    end

    -- handle text paste
    ---@param text string pasted text
    function public.handle_paste(text)
        if protected.window.isVisible() then
            -- handle the paste event then pass to children
            if self.focused then protected.handle_paste(text) end
            for _, child in pairs(protected.children) do child.get().handle_paste(text) end
        end
    end

    -- draw the element given new data
    ---@vararg any new data
    function public.update(...) protected.on_update(...) end

    -- on a control request response
    ---@param result any
    function public.on_response(result) protected.response_callback(result) end

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

    -- check if this element is visible
    function public.is_visible() return protected.window.isVisible() end

    -- show the element and enables animations by default
    ---@param animate? boolean true (default) to automatically resume animations
    function public.show(animate)
        protected.window.setVisible(true)
        if animate ~= false then public.animate_all() end
    end

    -- hide the element and disables animations<br>
    -- this alone does not cause an element to be fully hidden, it only prevents updates from being shown<br>
    ---@see graphics_element.redraw
    ---@see graphics_element.content_redraw
    ---@param clear? boolean true to visibly hide this element (redraws the parent)
    function public.hide(clear)
        public.freeze_all() -- stop animations for efficiency/performance
        public.unfocus_all()
        protected.window.setVisible(false)
        if clear and args.parent then args.parent.redraw() end
    end

    -- start/resume animation(s)
    function public.animate() protected.start_anim() end

    -- start/resume animation(s) for this element and all its children<br>
    -- only animates if a window is visible
    function public.animate_all()
        if protected.window.isVisible() then
            public.animate()
            for _, child in pairs(protected.children) do child.get().animate_all() end
        end
    end

    -- freeze animation(s)
    function public.freeze() protected.stop_anim() end

    -- freeze animation(s) for this element and all its children
    function public.freeze_all()
        public.freeze()
        for _, child in pairs(protected.children) do child.get().freeze_all() end
    end

    -- re-draw this element and all its children
    function public.redraw()
        protected.window.setBackgroundColor(protected.fg_bg.bkg)
        protected.window.setTextColor(protected.fg_bg.fgd)
        protected.window.clear()
        protected.redraw()
        for _, child in pairs(protected.children) do child.get().redraw() end
    end

    -- if a content window is set, clears it then re-draws all children
    function public.content_redraw()
        if protected.content_window ~= nil then
            protected.content_window.clear()
            for _, child in pairs(protected.children) do child.get().redraw() end
        end
    end

    return protected
end

return element
