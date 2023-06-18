--
-- Graphics Core Types, Checks, and Constructors
--

local events  = require("graphics.events")
local flasher = require("graphics.flasher")

local core = {}

core.version = "1.0.0-test"

core.flasher = flasher
core.events = events

-- Core Types

---@enum TEXT_ALIGN
core.TEXT_ALIGN = {
    LEFT = 1,
    CENTER = 2,
    RIGHT = 3
}

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
    return {
        width = width,
        color = color,
        even = even or false    -- convert nil to false
    }
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
    return {
        x = x,
        y = y,
        w = w,
        h = h
    }
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
        color_a = a,
        color_b = b,
        blit_a = colors.toBlit(a),
        blit_b = colors.toBlit(b),
        -- aliases
        fgd = a,
        bkg = b,
        blit_fgd = colors.toBlit(a),
        blit_bkg = colors.toBlit(b)
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

return core
