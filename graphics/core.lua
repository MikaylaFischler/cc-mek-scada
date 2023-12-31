--
-- Graphics Core Types, Checks, and Constructors
--

local events  = require("graphics.events")
local flasher = require("graphics.flasher")

local core = {}

core.version = "2.1.0"

core.flasher = flasher
core.events = events

-- Core Types

---@enum ALIGN
core.ALIGN = { LEFT = 1, CENTER = 2, RIGHT = 3 }

---@class graphics_border
---@field width integer
---@field color color
---@field even boolean

---@alias element_id string|integer

-- create a new border definition
---@nodiscard
---@param width integer border width
---@param color color border color
---@param even? boolean whether to pad width extra to account for rectangular pixels, defaults to false
---@return graphics_border
function core.border(width, color, even)
    return { width = width, color = color, even = even or false }
end

---@class graphics_frame
---@field x integer
---@field y integer
---@field w integer
---@field h integer

-- create a new graphics frame definition
---@nodiscard
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@return graphics_frame
function core.gframe(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

---@class cpair
---@field color_a color
---@field color_b color
---@field blit_a string
---@field blit_b string
---@field fgd color
---@field bkg color
---@field blit_fgd string
---@field blit_bkg string

-- create a new color pair definition
---@nodiscard
---@param a color
---@param b color
---@return cpair
function core.cpair(a, b)
    return {
        -- color pairs
        color_a = a, color_b = b, blit_a = colors.toBlit(a), blit_b = colors.toBlit(b),
        -- aliases
        fgd = a, bkg = b, blit_fgd = colors.toBlit(a), blit_bkg = colors.toBlit(b)
    }
end

---@class pipe
---@field x1 integer starting x, origin is 0
---@field y1 integer starting y, origin is 0
---@field x2 integer ending x, origin is 0
---@field y2 integer ending y, origin is 0
---@field w integer width
---@field h integer height
---@field color color pipe color
---@field thin boolean true for 1 subpixel, false (default) for 2
---@field align_tr boolean false to align bottom left (default), true to align top right

-- create a new pipe<br>
-- note: pipe coordinate origin is (0, 0)
---@nodiscard
---@param x1 integer starting x, origin is 0
---@param y1 integer starting y, origin is 0
---@param x2 integer ending x, origin is 0
---@param y2 integer ending y, origin is 0
---@param color color pipe color
---@param thin? boolean true for 1 subpixel, false (default) for 2
---@param align_tr? boolean false to align bottom left (default), true to align top right
---@return pipe
function core.pipe(x1, y1, x2, y2, color, thin, align_tr)
    return {
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        w = math.abs(x2 - x1) + 1,
        h = math.abs(y2 - y1) + 1,
        color = color,
        thin = thin or false,
        align_tr = align_tr or false
    }
end

-- Assertion Handling

-- extract the custom element assert message, dropping the path to the element file
function core.extract_assert_msg(msg)
    return string.sub(msg, (string.find(msg, "@") or 0) + 1)
end

-- Interactive Field Manager

---@param e graphics_base
---@param max_len any
---@param fg_bg any
---@param dis_fg_bg any
function core.new_ifield(e, max_len, fg_bg, dis_fg_bg)
    local self = {
        frame_start = 1,
        visible_text = e.value,
        cursor_pos = string.len(e.value) + 1,
        selected_all = false
    }

    -- update visible text
    local function _update_visible()
        self.visible_text = string.sub(e.value, self.frame_start, self.frame_start + math.min(string.len(e.value), e.frame.w) - 1)
    end

    -- try shifting frame left
    local function _try_lshift()
        if self.frame_start > 1 then
            self.frame_start = self.frame_start - 1
            return true
        end
    end

    -- try shifting frame right
    local function _try_rshift()
        if (self.frame_start + e.frame.w - 1) <= string.len(e.value) then
            self.frame_start = self.frame_start + 1
            return true
        end
    end

    ---@class ifield
    local public = {}

    -- censor the display (for private info, for example) with the provided character<br>
    -- disable by passing no argument
    ---@param censor string? character to hide data with
    function public.censor(censor)
        if type(censor) == "string" and string.len(censor) == 1 then
            self.censor = censor
        else self.censor = nil end
        public.show()
    end

    -- show the field
    function public.show()
        _update_visible()

        if e.enabled then
            e.w_set_bkg(fg_bg.bkg)
            e.w_set_fgd(fg_bg.fgd)
        elseif dis_fg_bg ~= nil then
            e.w_set_bkg(dis_fg_bg.bkg)
            e.w_set_fgd(dis_fg_bg.fgd)
        end

        -- clear and print
        e.w_set_cur(1, 1)
        e.w_write(string.rep(" ", e.frame.w))
        e.w_set_cur(1, 1)

        local function _write()
            if self.censor then
                e.w_write(string.rep(self.censor, string.len(self.visible_text)))
            else
                e.w_write(self.visible_text)
            end
        end

        if e.is_focused() and e.enabled then
            -- write text with cursor
            if self.selected_all then
                e.w_set_bkg(fg_bg.fgd)
                e.w_set_fgd(fg_bg.bkg)
                _write()
            elseif self.cursor_pos >= (string.len(self.visible_text) + 1) then
                -- write text with cursor at the end, no need to blit
                _write()
                e.w_set_fgd(colors.lightGray)
                e.w_write("_")
            else
                local a, b = "", ""

                if self.cursor_pos <= string.len(self.visible_text) then
                    a = fg_bg.blit_bkg
                    b = fg_bg.blit_fgd
                end

                local b_fgd = string.rep(fg_bg.blit_fgd, self.cursor_pos - 1) .. a .. string.rep(fg_bg.blit_fgd, string.len(self.visible_text) - self.cursor_pos)
                local b_bkg = string.rep(fg_bg.blit_bkg, self.cursor_pos - 1) .. b .. string.rep(fg_bg.blit_bkg, string.len(self.visible_text) - self.cursor_pos)

                if self.censor then
                    e.w_blit(string.rep(self.censor, string.len(self.visible_text)), b_fgd, b_bkg)
                else
                    e.w_blit(self.visible_text, b_fgd, b_bkg)
                end
            end
        else
            self.selected_all = false

            -- write text without cursor
            _write()
        end
    end

    -- move cursor to x
    ---@param x integer
    function public.move_cursor(x)
        self.selected_all = false
        self.cursor_pos = math.min(x, string.len(self.visible_text) + 1)
        public.show()
    end

    -- select all text
    function public.select_all()
        self.selected_all = true
        public.show()
    end

    -- set field value
    ---@param val string
    function public.set_value(val)
        e.value = string.sub(val, 1, math.min(max_len, string.len(val)))
        public.nav_end()
    end

    -- try to insert a character if there is space
    ---@param char string
    function public.try_insert_char(char)
        -- limit length
        if string.len(e.value) >= max_len then return end

        -- replace if selected all, insert otherwise
        if self.selected_all then
            self.selected_all = false
            self.cursor_pos = 2
            self.frame_start = 1

            e.value = char
            public.show()
        else
            e.value = string.sub(e.value, 1, self.frame_start + self.cursor_pos - 2) .. char .. string.sub(e.value, self.frame_start + self.cursor_pos - 1, string.len(e.value))
            _update_visible()
            public.nav_right()
        end
    end

    -- remove charcter before cursor if there is anything to remove, or delete all if selected all
    function public.backspace()
        if self.selected_all then
            self.selected_all = false
            e.value = ""
            self.cursor_pos = 1
            self.frame_start = 1
            public.show()
        else
            if self.frame_start + self.cursor_pos > 2 then
                e.value = string.sub(e.value, 1, self.frame_start + self.cursor_pos - 3) .. string.sub(e.value, self.frame_start + self.cursor_pos - 1, string.len(e.value))
                if self.cursor_pos > 1 then
                    self.cursor_pos = self.cursor_pos - 1
                    public.show()
                elseif _try_lshift() then public.show() end
            end
        end
    end

    -- move cursor left by one
    function public.nav_left()
        if self.cursor_pos > 1 then
            self.cursor_pos = self.cursor_pos - 1
            public.show()
        elseif _try_lshift() then public.show() end
    end

    -- move cursor right by one
    function public.nav_right()
        if self.cursor_pos < math.min(string.len(self.visible_text) + 1, e.frame.w) then
            self.cursor_pos = self.cursor_pos + 1
            public.show()
        elseif _try_rshift() then public.show() end
    end

    -- move cursor to the start
    function public.nav_start()
        self.cursor_pos = 1
        self.frame_start = 1
        public.show()
    end

    -- move cursor to the end
    function public.nav_end()
        self.frame_start = math.max(1, string.len(e.value) - e.frame.w + 2)
        _update_visible()
        self.cursor_pos = string.len(self.visible_text) + 1
        public.show()
    end

    return public
end

return core
